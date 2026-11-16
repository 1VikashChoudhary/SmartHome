package com.smarthome.smarthome_app

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.quicksettings.TileService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.smarthome.smarthome_app/native_controls"
        const val ACTION_OPEN_QUICK_TILE = "com.smarthome.smarthome_app.ACTION_OPEN_QUICK_TILE"
        const val ACTION_OPEN_DEVICE = "com.smarthome.smarthome_app.ACTION_OPEN_DEVICE"
        const val EXTRA_OPEN_TILE_SLOT = "open_tile_slot"
        const val EXTRA_OPEN_DEVICE_ID = "open_device_id"
    }

    private var methodChannel: MethodChannel? = null
    private var pendingTileSlot: Int? = null
    private var pendingDeviceId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractIntentExtras(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractIntentExtras(intent)
        val tileSlot = pendingTileSlot
        val deviceId = pendingDeviceId
        if (tileSlot != null || deviceId != null) {
            val payload = hashMapOf<String, Any?>(
                "tileSlot" to tileSlot,
                "deviceId" to deviceId
            )
            methodChannel?.let { ch ->
                pendingTileSlot = null
                pendingDeviceId = null
                ch.invokeMethod("onLaunchAction", payload)
            }
        }
    }

    private fun extractIntentExtras(intent: Intent?) {
        if (intent == null) return
        val slotExtra = intent.getIntExtra(EXTRA_OPEN_TILE_SLOT, -1)
        if (slotExtra in 1..NativeControlStore.MAX_TILE_SLOTS) {
            pendingTileSlot = slotExtra
            return
        }

        if (intent.action == TileService.ACTION_QS_TILE_PREFERENCES) {
            val comp: ComponentName? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_COMPONENT_NAME, ComponentName::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_COMPONENT_NAME)
            }
            val parsedSlot = SmartHomeTileRefreshHelper.slotForClassName(comp?.className)
            if (parsedSlot != null) {
                pendingTileSlot = parsedSlot
                return
            }
        }

        val devExtra = intent.getStringExtra(EXTRA_OPEN_DEVICE_ID)
        if (!devExtra.isNullOrBlank()) {
            pendingDeviceId = devExtra
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = ch

        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "syncDevices" -> {
                    @Suppress("UNCHECKED_CAST")
                    val list = call.argument<List<Map<String, Any?>>>("devices") ?: emptyList()
                    NativeControlStore.syncDevicesFromMaps(applicationContext, list)
                    SmartHomeTileRefreshHelper.requestAllTilesUpdate(applicationContext)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        for (dev in NativeControlStore.getDevices(applicationContext)) {
                            SmartHomeControlsService.notifyDeviceUpdated(applicationContext, dev.id)
                        }
                    }
                    result.success(true)
                }

                "getTileSlots" -> {
                    val slots = NativeControlStore.getAllTileSlots(applicationContext)
                    val out = (1..NativeControlStore.MAX_TILE_SLOTS).map { s ->
                        val item = slots[s]
                        hashMapOf<String, Any?>(
                            "slot" to s,
                            "deviceId" to item?.deviceId,
                            "relayId" to item?.relayId,
                            "customLabel" to item?.customLabel
                        )
                    }
                    result.success(out)
                }

                "setTileSlot" -> {
                    val slot = call.argument<Int>("slot") ?: 0
                    val deviceId = call.argument<String>("deviceId").orEmpty()
                    val relayId = call.argument<Int>("relayId") ?: 0
                    val customLabel = call.argument<String>("customLabel")
                    if (slot !in 1..NativeControlStore.MAX_TILE_SLOTS || deviceId.isEmpty()) {
                        result.error("INVALID_ARGS", "Invalid tile slot or deviceId", null)
                    } else {
                        NativeControlStore.setTileSlot(applicationContext, slot, deviceId, relayId, customLabel)
                        SmartHomeTileRefreshHelper.requestTileUpdate(applicationContext, slot)
                        result.success(true)
                    }
                }

                "clearTileSlot" -> {
                    val slot = call.argument<Int>("slot") ?: 0
                    if (slot in 1..NativeControlStore.MAX_TILE_SLOTS) {
                        NativeControlStore.clearTileSlot(applicationContext, slot)
                        SmartHomeTileRefreshHelper.requestTileUpdate(applicationContext, slot)
                    }
                    result.success(true)
                }

                "autoAssignTileSlots" -> {
                    val assigned = NativeControlStore.autoAssignSlots(applicationContext)
                    SmartHomeTileRefreshHelper.requestAllTilesUpdate(applicationContext)
                    result.success(assigned)
                }

                "consumeLaunchAction" -> {
                    val payload = hashMapOf<String, Any?>(
                        "tileSlot" to pendingTileSlot,
                        "deviceId" to pendingDeviceId
                    )
                    pendingTileSlot = null
                    pendingDeviceId = null
                    result.success(payload)
                }

                "getPlatformCapabilities" -> {
                    result.success(
                        hashMapOf(
                            "supportsQuickTiles" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N),
                            "supportsDeviceControls" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R),
                            "apiLevel" to Build.VERSION.SDK_INT,
                            "maxTileSlots" to NativeControlStore.MAX_TILE_SLOTS
                        )
                    )
                }

                else -> result.notImplemented()
            }
        }
    }
}
