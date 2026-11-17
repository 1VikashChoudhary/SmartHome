package com.smarthome.smarthome_app

import android.app.KeyguardManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

object SmartHomeTileRefreshHelper {
    private val tileClasses: List<Class<out TileService>> = listOf(
        SmartHomeTileService1::class.java,
        SmartHomeTileService2::class.java,
        SmartHomeTileService3::class.java,
        SmartHomeTileService4::class.java,
        SmartHomeTileService5::class.java,
        SmartHomeTileService6::class.java,
        SmartHomeTileService7::class.java,
        SmartHomeTileService8::class.java,
        SmartHomeTileService9::class.java,
        SmartHomeTileService10::class.java,
        SmartHomeTileService11::class.java,
        SmartHomeTileService12::class.java
    )

    fun slotForClassName(className: String?): Int? {
        if (className == null) return null
        val match = Regex("SmartHomeTileService(\\d+)$").find(className) ?: return null
        val slot = match.groupValues[1].toIntOrNull() ?: return null
        return if (slot in 1..NativeControlStore.MAX_TILE_SLOTS) slot else null
    }

    fun requestTileUpdate(context: Context, slot: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val cls = tileClasses.getOrNull(slot - 1) ?: return
        try {
            TileService.requestListeningState(context, ComponentName(context, cls))
        } catch (_: Exception) {
        }
    }

    fun requestAllTilesUpdate(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        for (cls in tileClasses) {
            try {
                TileService.requestListeningState(context, ComponentName(context, cls))
            } catch (_: Exception) {
            }
        }
    }
}

@RequiresApi(Build.VERSION_CODES.N)
abstract class BaseSmartHomeTileService(private val slotNumber: Int) : TileService() {
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onTileAdded() {
        super.onTileAdded()
        refreshTileState(fetchLive = true)
    }

    override fun onStartListening() {
        super.onStartListening()
        refreshTileState(fetchLive = true)
    }

    override fun onClick() {
        super.onClick()
        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val needsUnlock = (km?.isDeviceLocked == true || km?.isKeyguardLocked == true) &&
            !NativeControlStore.getAllowLockscreenControls(this)
        if (needsUnlock) {
            unlockAndRun { performTileClick() }
            return
        }
        performTileClick()
    }

    private fun performTileClick() {
        val assignment = NativeControlStore.getTileSlot(this, slotNumber)
        if (assignment == null) {
            openTileConfiguration()
            return
        }
        val device = NativeControlStore.getDeviceById(this, assignment.deviceId)
        if (device == null) {
            openTileConfiguration()
            return
        }
        if (device.authLocked) {
            openDeviceScreen(device.id)
            return
        }
        if (assignment.relayId != NativeControlStore.ALL_RELAYS_ID) {
            val targetRelay = resolveRelay(device, assignment.relayId)
            if (targetRelay != null && !targetRelay.enabled) {
                applyTileVisual(assignment, device)
                return
            }
        }

        val currentOn = resolveCurrentState(device, assignment.relayId)
        val nextAction = if (assignment.relayId == NativeControlStore.ALL_RELAYS_ID) {
            if (currentOn) "off" else "on"
        } else {
            "toggle"
        }

        // Optimistic immediate tile feedback
        applyTileVisual(assignment, device, overrideState = !currentOn, statusLabel = if (!currentOn) "ON" else "OFF")

        NativeEspClient.executor.execute {
            val (ok, unauthorized) = NativeEspClient.setRelay(this, device, assignment.relayId, nextAction)
            var refreshedDevice = device
            var effectiveOnline = ok
            var overrideState: Boolean? = if (ok) !currentOn else currentOn

            if (ok) {
                val statusRes = NativeEspClient.fetchStatus(this, device)
                if (statusRes.ok) {
                    refreshedDevice = NativeControlStore.getDeviceById(this, device.id) ?: device
                    overrideState = null
                    effectiveOnline = true
                } else {
                    NativeControlStore.updateDeviceOnlineAndRelayState(
                        this,
                        device.id,
                        isOnline = true,
                        relayId = assignment.relayId,
                        newState = !currentOn
                    )
                    refreshedDevice = NativeControlStore.getDeviceById(this, device.id) ?: device
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    SmartHomeControlsService.notifyDeviceUpdated(this, refreshedDevice.id)
                }
            } else if (!unauthorized) {
                effectiveOnline = false
            }

            mainHandler.post {
                if (unauthorized) {
                    applyAuthErrorTile(assignment, device)
                } else {
                    applyTileVisual(
                        assignment,
                        refreshedDevice,
                        overrideOnline = effectiveOnline,
                        overrideState = overrideState
                    )
                }
            }
        }
    }

    private fun refreshTileState(fetchLive: Boolean) {
        val assignment = NativeControlStore.getTileSlot(this, slotNumber)
        if (assignment == null) {
            applyUnassignedTile()
            return
        }
        val device = NativeControlStore.getDeviceById(this, assignment.deviceId)
        if (device == null) {
            applyMissingTile()
            return
        }
        if (device.authLocked) {
            applyAuthErrorTile(assignment, device)
            return
        }

        applyTileVisual(assignment, device)
        if (!fetchLive) return

        NativeEspClient.executor.execute {
            val status = NativeEspClient.fetchStatus(this, device)
            val latest = NativeControlStore.getDeviceById(this, device.id) ?: device
            mainHandler.post {
                if (status.unauthorized) {
                    applyAuthErrorTile(assignment, latest)
                } else {
                    applyTileVisual(assignment, latest, overrideOnline = status.ok)
                }
            }
        }
    }

    private fun resolveCurrentState(device: NativeDevice, relayId: Int): Boolean {
        return if (relayId == NativeControlStore.ALL_RELAYS_ID) {
            device.relays.any { it.enabled && it.state }
        } else {
            device.relays.firstOrNull { it.id == relayId }?.state ?: false
        }
    }

    private fun resolveRelay(device: NativeDevice, relayId: Int): NativeRelay? {
        if (relayId == NativeControlStore.ALL_RELAYS_ID) return null
        return device.relays.firstOrNull { it.id == relayId }
    }

    private fun applyUnassignedTile() {
        val tile = qsTile ?: return
        tile.label = "Tile $slotNumber"
        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_tile)
        tile.state = Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = "Tap to assign"
        }
        tile.updateTile()
    }

    private fun applyMissingTile() {
        val tile = qsTile ?: return
        tile.label = "Tile $slotNumber"
        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_tile)
        tile.state = Tile.STATE_UNAVAILABLE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = "Not linked"
        }
        tile.updateTile()
    }

    private fun applyAuthErrorTile(assignment: TileSlotAssignment, device: NativeDevice) {
        val tile = qsTile ?: return
        val relay = resolveRelay(device, assignment.relayId)
        val label = assignment.customLabel
            ?: if (assignment.relayId == NativeControlStore.ALL_RELAYS_ID) "All Relays" else (relay?.name ?: "Relay ${assignment.relayId + 1}")
        tile.label = label
        tile.icon = Icon.createWithResource(
            this,
            NativeControlStore.iconDrawableFor(relay?.icon, assignment.relayId)
        )
        tile.state = Tile.STATE_UNAVAILABLE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = "Login needed"
        }
        tile.updateTile()
    }

    private fun applyTileVisual(
        assignment: TileSlotAssignment,
        device: NativeDevice,
        overrideOnline: Boolean? = null,
        overrideState: Boolean? = null,
        statusLabel: String? = null
    ) {
        val tile = qsTile ?: return
        val relay = resolveRelay(device, assignment.relayId)
        if (assignment.relayId != NativeControlStore.ALL_RELAYS_ID && relay != null && !relay.enabled) {
            tile.label = assignment.customLabel ?: relay.name
            tile.icon = Icon.createWithResource(this, NativeControlStore.iconDrawableFor(relay.icon, assignment.relayId))
            tile.state = Tile.STATE_UNAVAILABLE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = "Disabled"
            }
            tile.updateTile()
            return
        }

        val isOnline = overrideOnline ?: device.isOnline
        val isOn = overrideState ?: resolveCurrentState(device, assignment.relayId)

        val title = assignment.customLabel
            ?: if (assignment.relayId == NativeControlStore.ALL_RELAYS_ID) {
                "${device.name} All"
            } else {
                relay?.name ?: "Relay ${assignment.relayId + 1}"
            }

        tile.label = title
        tile.icon = Icon.createWithResource(
            this,
            NativeControlStore.iconDrawableFor(relay?.icon, assignment.relayId)
        )
        tile.state = when {
            !isOnline -> Tile.STATE_UNAVAILABLE
            isOn -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = when {
                !isOnline -> "${device.name} • Offline"
                statusLabel != null -> "${device.name} • $statusLabel"
                else -> device.name
            }
        }
        tile.updateTile()
    }

    private fun openDeviceScreen(deviceId: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_DEVICE
            putExtra(MainActivity.EXTRA_OPEN_DEVICE_ID, deviceId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        launchActivityWithCollapse(intent, 6000 + slotNumber)
    }

    private fun openTileConfiguration() {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_QUICK_TILE
            putExtra(MainActivity.EXTRA_OPEN_TILE_SLOT, slotNumber)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        launchActivityWithCollapse(intent, 5000 + slotNumber)
    }

    private fun launchActivityWithCollapse(intent: Intent, requestCode: Int) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val pi = PendingIntent.getActivity(
                    this,
                    requestCode,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                startActivityAndCollapse(pi)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        } catch (_: Exception) {
        }
    }
}
