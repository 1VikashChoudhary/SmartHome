package com.smarthome.smarthome_app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Local-LAN Background Safety Monitor (Android Foreground Service).
 * Polls paired SmartHome controllers on home Wi-Fi/Ethernet and fires loud
 * USAGE_ALARM emergency notifications + lock-screen actions even when the UI
 * is backgrounded or swiped away.
 */
class SafetyMonitorService : Service() {
    companion object {
        const val MONITOR_CHANNEL_ID = "smarthome_safety_monitor"
        const val ALARM_CHANNEL_ID = "smarthome_emergency_alarms"
        const val MONITOR_NOTIFICATION_ID = 7100
        const val ALARM_NOTIFICATION_BASE_ID = 7200
        private const val POLL_WAKE_REQ_CODE = 7105
        private const val RESTART_WAKE_REQ_CODE = 7106

        const val ACTION_START = "com.smarthome.smarthome_app.ACTION_START_MONITOR"
        const val ACTION_STOP = "com.smarthome.smarthome_app.ACTION_STOP_MONITOR"
        const val ACTION_POLL_NOW = "com.smarthome.smarthome_app.ACTION_POLL_NOW"
        const val ACTION_SILENCE_EPISODE = "com.smarthome.smarthome_app.ACTION_SILENCE_EPISODE"
        const val EXTRA_EPISODE_KEY = "episode_key"

        private val silencedEpisodes = ConcurrentHashMap.newKeySet<String>()
        private val activeNotifications = ConcurrentHashMap<String, Int>()
        private val activeAlarmTypes = ConcurrentHashMap<String, String>()

        fun notificationIdForDevice(deviceId: String): Int {
            return ALARM_NOTIFICATION_BASE_ID + ((deviceId.hashCode() and 0x7FFFFFFF) % 500)
        }

        fun markEpisodeSilenced(deviceId: String, alarmType: String) {
            silencedEpisodes.add("$deviceId:$alarmType")
            activeNotifications.remove(deviceId)
            activeAlarmTypes.remove(deviceId)
        }

        fun isMonitorChannelHidden(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return false
            if (!nm.areNotificationsEnabled()) return true
            val ch = nm.getNotificationChannel(MONITOR_CHANNEL_ID) ?: return false
            return ch.importance == NotificationManager.IMPORTANCE_NONE
        }

        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

            val monitorChannel = NotificationChannel(
                MONITOR_CHANNEL_ID,
                "Background Safety Monitor",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Optional status indicator while local Wi-Fi safety monitoring is active (safe to hide without stopping alarms)"
                setShowBadge(false)
            }
            nm.createNotificationChannel(monitorChannel)

            val alarmChannel = NotificationChannel(
                ALARM_CHANNEL_ID,
                "Emergency Gas & Temp Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Critical gas, smoke, VOC, and high temperature hazards"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 250, 500, 250)
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                setSound(alarmUri, attrs)
            }
            nm.createNotificationChannel(alarmChannel)
        }

        fun syncServiceState(context: Context) {
            val enabled = NativeControlStore.getSafetyMonitorEnabled(context) &&
                NativeControlStore.getDevices(context).isNotEmpty()
            val intent = Intent(context, SafetyMonitorService::class.java).apply {
                action = if (enabled) ACTION_START else ACTION_STOP
            }
            try {
                if (enabled) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                } else {
                    context.stopService(intent)
                }
            } catch (_: Exception) {
            }
        }
    }

    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val isPolling = AtomicBoolean(false)
    private var pollFuture: ScheduledFuture<*>? = null
    private var lastNotifiedDeviceCount = -1

    override fun onCreate() {
        super.onCreate()
        ensureChannels(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                NativeControlStore.setSafetyMonitorEnabled(applicationContext, false)
                cancelDozeWakeups()
                AlarmSoundPlayer.stopSiren(applicationContext)
                stopMonitor()
                return START_NOT_STICKY
            }
            ACTION_SILENCE_EPISODE -> {
                val key = intent.getStringExtra(EXTRA_EPISODE_KEY)
                if (!key.isNullOrEmpty()) silencedEpisodes.add(key)
                AlarmSoundPlayer.stopSiren(applicationContext)
                return START_STICKY
            }
        }

        if (!NativeControlStore.getSafetyMonitorEnabled(applicationContext) ||
            NativeControlStore.getDevices(applicationContext).isEmpty()) {
            stopMonitor()
            return START_NOT_STICKY
        }

        val notif = buildMonitorNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                MONITOR_NOTIFICATION_ID,
                notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(MONITOR_NOTIFICATION_ID, notif)
        }

        if (pollFuture == null || pollFuture?.isCancelled == true) {
            pollFuture = scheduler.scheduleWithFixedDelay(
                { runSafetyPollCycle() },
                1L,
                6L,
                TimeUnit.SECONDS
            )
        } else if (intent?.action == ACTION_POLL_NOW) {
            scheduler.execute { runSafetyPollCycle() }
        }
        scheduleNextDozeWakeup()
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (NativeControlStore.getSafetyMonitorEnabled(applicationContext) &&
            NativeControlStore.getDevices(applicationContext).isNotEmpty()) {
            try {
                val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
                val restartIntent = Intent(applicationContext, SafetyMonitorService::class.java).apply {
                    action = ACTION_START
                }
                val pi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    PendingIntent.getForegroundService(
                        applicationContext,
                        RESTART_WAKE_REQ_CODE,
                        restartIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                } else {
                    PendingIntent.getService(
                        applicationContext,
                        RESTART_WAKE_REQ_CODE,
                        restartIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                }
                am.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 1500L,
                    pi
                )
            } catch (_: Exception) {
            }
        }
    }

    override fun onDestroy() {
        cancelDozeWakeups()
        pollFuture?.cancel(true)
        pollFuture = null
        scheduler.shutdownNow()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun stopMonitor() {
        pollFuture?.cancel(true)
        pollFuture = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun scheduleNextDozeWakeup() {
        if (!NativeControlStore.getSafetyMonitorEnabled(applicationContext)) return
        try {
            val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val pi = PendingIntent.getService(
                applicationContext,
                POLL_WAKE_REQ_CODE,
                Intent(applicationContext, SafetyMonitorService::class.java).apply {
                    action = ACTION_POLL_NOW
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val triggerAt = SystemClock.elapsedRealtime() + 15_000L
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
            } else {
                am.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
            }
        } catch (_: Exception) {
        }
    }

    private fun cancelDozeWakeups() {
        try {
            val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val pi = PendingIntent.getService(
                applicationContext,
                POLL_WAKE_REQ_CODE,
                Intent(applicationContext, SafetyMonitorService::class.java).apply {
                    action = ACTION_POLL_NOW
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.cancel(pi)
        } catch (_: Exception) {
        }
    }

    private fun isOnLocalCapableNetwork(): Boolean {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                @Suppress("DEPRECATION")
                val networks = cm.allNetworks
                for (net in networks) {
                    val caps = cm.getNetworkCapabilities(net) ?: continue
                    if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ||
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                        return true
                    }
                }
                val active = cm.activeNetwork ?: return false
                val activeCaps = cm.getNetworkCapabilities(active) ?: return false
                activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ||
                    activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            } else {
                @Suppress("DEPRECATION")
                val info = cm.activeNetworkInfo
                @Suppress("DEPRECATION")
                info != null && info.isConnected
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun runSafetyPollCycle() {
        if (!isPolling.compareAndSet(false, true)) return
        val pm = applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = try {
            pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SmartHome:SafetyPollLock")?.apply {
                setReferenceCounted(false)
                acquire(5000L)
            }
        } catch (_: Exception) {
            null
        }
        try {
            if (!NativeControlStore.getSafetyMonitorEnabled(applicationContext)) {
                stopMonitor()
                return
            }
            if (!isOnLocalCapableNetwork()) return

            val devices = NativeControlStore.getDevices(applicationContext)
            if (devices.size != lastNotifiedDeviceCount) {
                lastNotifiedDeviceCount = devices.size
                updateMonitorNotificationText(devices.size)
            }
            if (devices.isEmpty()) return

            for (dev in devices) {
                if (dev.authLocked && dev.authPassword.isNullOrEmpty()) continue
                val res = NativeEspClient.fetchStatus(applicationContext, dev)
                if (!res.ok || res.statusJson == null) continue

                val json = res.statusJson
                var gasAlarm = json.optBoolean("gas_alarm", false)
                val gasRaw = json.optInt("gas_raw", 0)
                val gasThr = json.optInt("gas_threshold", 0)
                val gasEnabled = json.optBoolean("gas_enabled", false)
                if (!gasAlarm && gasEnabled && gasThr > 0 && gasRaw >= gasThr && !json.optBoolean("gas_warming", false)) {
                    gasAlarm = true
                }
                val mq2Arr = json.optJSONArray("mq2s") ?: json.optJSONArray("mq2_sensors")
                if (!gasAlarm && mq2Arr != null) {
                    for (idx in 0 until mq2Arr.length()) {
                        val m = mq2Arr.optJSONObject(idx) ?: continue
                        if (m.optBoolean("enabled", false) && m.optBoolean("alarm", false)) {
                            gasAlarm = true
                            break
                        }
                    }
                }

                val dhtEnabled = json.optBoolean("dht_enabled", false)
                val dhtFault = json.optBoolean("dht_fault", false)
                val probeFault = json.optBoolean("probe_fault", false)
                val temp = json.optDouble("temperature", 0.0)
                val tempThr = json.optDouble("temp_threshold", 40.0)
                var tempAlarm = json.optBoolean("temp_alarm", false)
                if (!tempAlarm && dhtEnabled && !dhtFault && tempThr > 0.0 && temp >= tempThr) {
                    tempAlarm = true
                }

                var sensorFault = json.optBoolean("sensor_fault", false) ||
                    (dhtEnabled && dhtFault) ||
                    (json.optBoolean("probe_enabled", false) && probeFault)

                val climatesArr = json.optJSONArray("climates")
                if (climatesArr != null) {
                    for (idx in 0 until climatesArr.length()) {
                        val c = climatesArr.optJSONObject(idx) ?: continue
                        if (!c.optBoolean("enabled", false)) continue
                        if (c.optBoolean("fault", false)) {
                            sensorFault = true
                        } else if (c.optBoolean("temp_alarm", false)) {
                            tempAlarm = true
                        }
                    }
                }

                if (!gasAlarm) silencedEpisodes.remove("${dev.id}:gas")
                if (!tempAlarm) silencedEpisodes.remove("${dev.id}:temperature")
                if (!sensorFault) silencedEpisodes.remove("${dev.id}:sensor_fault")

                val activeType = when {
                    gasAlarm -> "gas"
                    tempAlarm -> "temperature"
                    sensorFault -> "sensor_fault"
                    else -> null
                }

                if (activeType == null) {
                    val prevId = activeNotifications.remove(dev.id)
                    activeAlarmTypes.remove(dev.id)
                    if (prevId != null) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                        nm?.cancel(prevId)
                    }
                    if (activeNotifications.isEmpty()) {
                        AlarmSoundPlayer.stopSiren(applicationContext)
                    }
                    continue
                }

                val epKey = "${dev.id}:$activeType"
                if (silencedEpisodes.contains(epKey)) continue

                val unit = json.optString("gas_unit", "ADC")
                val gasModel = json.optString("gas_type_name", "MQ-2").ifEmpty { "MQ-2" }
                val title = when (activeType) {
                    "gas" -> if (unit.equals("VOC", ignoreCase = true)) {
                        "VOC AIR ALERT: ${dev.name}"
                    } else {
                        "GAS / SMOKE ALARM: ${dev.name}"
                    }
                    "temperature" -> "HIGH TEMPERATURE ALARM: ${dev.name}"
                    else -> "SENSOR HARDWARE FAULT: ${dev.name}"
                }
                val body = when (activeType) {
                    "gas" -> "${dev.room} — $gasModel: $gasRaw $unit (Limit: $gasThr $unit). Tap to inspect or cut power."
                    "temperature" -> "${dev.room} — Temperature: " + String.format(java.util.Locale.US, "%.1f°C (Limit: %.1f°C).", temp, tempThr)
                    else -> "${dev.room} — Climate sensor failed to respond; safety failsafe activated."
                }

                AlarmSoundPlayer.startSiren(applicationContext)
                if (activeAlarmTypes[dev.id] != activeType) {
                    activeAlarmTypes[dev.id] = activeType
                    showEmergencyNotification(dev, activeType, title, body)
                }
            }
            scheduleNextDozeWakeup()
        } finally {
            try {
                if (wakeLock?.isHeld == true) wakeLock.release()
            } catch (_: Exception) {
            }
            isPolling.set(false)
        }
    }

    private fun showEmergencyNotification(
        dev: NativeDevice,
        alarmType: String,
        title: String,
        body: String
    ) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val notifId = notificationIdForDevice(dev.id)
        activeNotifications[dev.id] = notifId

        val openIntent = Intent(applicationContext, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_DEVICE
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_OPEN_DEVICE_ID, dev.id)
            putExtra(MainActivity.EXTRA_OPEN_ALARM_TYPE, alarmType)
        }
        val openPi = PendingIntent.getActivity(
            applicationContext,
            notifId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val silencePi = PendingIntent.getBroadcast(
            applicationContext,
            notifId * 10 + 1,
            Intent(applicationContext, AlarmNotificationReceiver::class.java).apply {
                action = AlarmNotificationReceiver.ACTION_STOP_SIREN
                putExtra(AlarmNotificationReceiver.EXTRA_DEVICE_ID, dev.id)
                putExtra(AlarmNotificationReceiver.EXTRA_ALARM_TYPE, alarmType)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val mutePi = PendingIntent.getBroadcast(
            applicationContext,
            notifId * 10 + 2,
            Intent(applicationContext, AlarmNotificationReceiver::class.java).apply {
                action = AlarmNotificationReceiver.ACTION_MUTE_BUZZER
                putExtra(AlarmNotificationReceiver.EXTRA_DEVICE_ID, dev.id)
                putExtra(AlarmNotificationReceiver.EXTRA_ALARM_TYPE, alarmType)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val shutoffPi = PendingIntent.getBroadcast(
            applicationContext,
            notifId * 10 + 3,
            Intent(applicationContext, AlarmNotificationReceiver::class.java).apply {
                action = AlarmNotificationReceiver.ACTION_SHUTOFF_ALL
                putExtra(AlarmNotificationReceiver.EXTRA_DEVICE_ID, dev.id)
                putExtra(AlarmNotificationReceiver.EXTRA_ALARM_TYPE, alarmType)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(applicationContext, ALARM_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(applicationContext)
                .setPriority(Notification.PRIORITY_MAX)
        }

        builder.setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(openPi)
            .setFullScreenIntent(openPi, true)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(applicationContext, android.R.drawable.ic_lock_silent_mode),
                    "Silence",
                    silencePi
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(applicationContext, android.R.drawable.ic_media_pause),
                    "Mute ESP",
                    mutePi
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(applicationContext, android.R.drawable.ic_lock_power_off),
                    "Shutoff All",
                    shutoffPi
                ).build()
            )

        nm.notify(notifId, builder.build())
    }

    private fun buildMonitorNotification(deviceCount: Int = NativeControlStore.getDevices(applicationContext).size): Notification {
        val openAppIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPi = PendingIntent.getActivity(
            applicationContext,
            MONITOR_NOTIFICATION_ID,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopPi = PendingIntent.getService(
            applicationContext,
            MONITOR_NOTIFICATION_ID + 1,
            Intent(applicationContext, SafetyMonitorService::class.java).apply {
                action = ACTION_STOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val text = if (deviceCount > 0) {
            "Monitoring $deviceCount controller(s) on local Wi-Fi"
        } else {
            "Waiting for paired controllers on local Wi-Fi"
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(applicationContext, MONITOR_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(applicationContext)
                .setPriority(Notification.PRIORITY_MIN)
        }

        return builder.setSmallIcon(R.drawable.ic_qs_tile)
            .setContentTitle("SmartHome Safety Guard Active")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(openPi)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(applicationContext, android.R.drawable.ic_menu_close_clear_cancel),
                    "Pause",
                    stopPi
                ).build()
            )
            .build()
    }

    private fun updateMonitorNotificationText(deviceCount: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        nm.notify(MONITOR_NOTIFICATION_ID, buildMonitorNotification(deviceCount))
    }
}
