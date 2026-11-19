package com.smarthome.smarthome_app

import android.Manifest
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
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
        const val EXTRA_OPEN_ALARM_TYPE = "open_alarm_type"
        private const val REQ_POST_NOTIFICATIONS = 4102
    }

    private var methodChannel: MethodChannel? = null
    private var pendingTileSlot: Int? = null
    private var pendingDeviceId: String? = null
    private var pendingAlarmType: String? = null
    private var pendingNotifPermResult: MethodChannel.Result? = null

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
        val alarmType = pendingAlarmType
        if (tileSlot != null || deviceId != null) {
            val payload = hashMapOf<String, Any?>(
                "tileSlot" to tileSlot,
                "deviceId" to deviceId,
                "alarmType" to alarmType
            )
            methodChannel?.let { ch ->
                pendingTileSlot = null
                pendingDeviceId = null
                pendingAlarmType = null
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

        val devExtra = intent.getStringExtra(EXTRA_OPEN_DEVICE_ID)?.trim()
        val allowedAlarms = setOf("gas", "temperature", "sensor_fault")
        var openedForAlarm = false
        if (NativeControlStore.isValidDeviceId(devExtra) &&
            NativeControlStore.getDeviceById(applicationContext, devExtra!!) != null) {
            pendingDeviceId = devExtra
            val alarmExtra = intent.getStringExtra(EXTRA_OPEN_ALARM_TYPE)?.trim()
            if (!alarmExtra.isNullOrEmpty() && alarmExtra in allowedAlarms) {
                pendingAlarmType = alarmExtra
                openedForAlarm = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    setShowWhenLocked(true)
                    setTurnScreenOn(true)
                }
            }
        }
        if (!openedForAlarm && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                SafetyMonitorService.syncServiceState(applicationContext)
            }
            pendingNotifPermResult?.success(granted)
            pendingNotifPermResult = null
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
                    SafetyMonitorService.syncServiceState(applicationContext)
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
                        "deviceId" to pendingDeviceId,
                        "alarmType" to pendingAlarmType
                    )
                    pendingTileSlot = null
                    pendingDeviceId = null
                    pendingAlarmType = null
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

                "getAllowLockscreenControls" -> {
                    result.success(NativeControlStore.getAllowLockscreenControls(applicationContext))
                }

                "setAllowLockscreenControls" -> {
                    val allow = call.argument<Boolean>("allow") ?: false
                    NativeControlStore.setAllowLockscreenControls(applicationContext, allow)
                    SmartHomeTileRefreshHelper.requestAllTilesUpdate(applicationContext)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        for (dev in NativeControlStore.getDevices(applicationContext)) {
                            SmartHomeControlsService.notifyDeviceUpdated(applicationContext, dev.id)
                        }
                    }
                    result.success(true)
                }

                "getSafetyMonitorState" -> {
                    SafetyMonitorService.ensureChannels(applicationContext)
                    result.success(
                        hashMapOf(
                            "monitorEnabled" to NativeControlStore.getSafetyMonitorEnabled(applicationContext),
                            "sirenEnabled" to NativeControlStore.getAlarmSirenEnabled(applicationContext),
                            "notificationPermissionGranted" to hasNotificationPermission(),
                            "isSirenPlaying" to AlarmSoundPlayer.isPlaying(),
                            "ignoringBatteryOptimizations" to isIgnoringBatteryOptimizations(),
                            "monitorChannelHidden" to SafetyMonitorService.isMonitorChannelHidden(applicationContext)
                        )
                    )
                }

                "openMonitorChannelSettings" -> {
                    SafetyMonitorService.ensureChannels(applicationContext)
                    try {
                        val i = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                putExtra(Settings.EXTRA_CHANNEL_ID, SafetyMonitorService.MONITOR_CHANNEL_ID)
                            }
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.fromParts("package", packageName, null)
                            }
                        }
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }

                "openNotificationSettings" -> {
                    try {
                        val i = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.fromParts("package", packageName, null)
                            }
                        }
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }

                "openAppDetailsSettings" -> {
                    try {
                        val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(i)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }

                "requestNotificationPermission" -> {
                    if (hasNotificationPermission() || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                        result.success(true)
                    } else {
                        pendingNotifPermResult?.success(false)
                        pendingNotifPermResult = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_POST_NOTIFICATIONS)
                    }
                }

                "setSafetyMonitorEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    NativeControlStore.setSafetyMonitorEnabled(applicationContext, enabled)
                    SafetyMonitorService.syncServiceState(applicationContext)
                    result.success(true)
                }

                "setAlarmSirenEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    NativeControlStore.setAlarmSirenEnabled(applicationContext, enabled)
                    if (!enabled) AlarmSoundPlayer.stopSiren(applicationContext)
                    result.success(true)
                }

                "startInAppSiren" -> {
                    val force = call.argument<Boolean>("force") ?: false
                    AlarmSoundPlayer.startSiren(applicationContext, force = force)
                    result.success(true)
                }

                "stopInAppSiren" -> {
                    AlarmSoundPlayer.stopSiren(applicationContext)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        setShowWhenLocked(false)
                        setTurnScreenOn(false)
                    }
                    result.success(true)
                }

                "silenceAlarmEpisode" -> {
                    val devId = call.argument<String>("deviceId").orEmpty()
                    val alarmType = call.argument<String>("alarmType").orEmpty()
                    AlarmSoundPlayer.stopSiren(applicationContext)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        setShowWhenLocked(false)
                        setTurnScreenOn(false)
                    }
                    if (devId.isNotEmpty()) {
                        if (alarmType.isNotEmpty()) {
                            SafetyMonitorService.markEpisodeSilenced(devId, alarmType)
                        }
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                        nm?.cancel(SafetyMonitorService.notificationIdForDevice(devId))
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }
}
