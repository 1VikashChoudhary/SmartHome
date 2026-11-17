package com.smarthome.smarthome_app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles Emergency Alarm notification buttons (Silence Phone, Mute ESP Buzzer,
 * and Emergency All-Relay Shutoff) even when the Flutter UI is closed.
 */
class AlarmNotificationReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_STOP_SIREN = "com.smarthome.smarthome_app.ACTION_ALARM_STOP_SIREN"
        const val ACTION_MUTE_BUZZER = "com.smarthome.smarthome_app.ACTION_ALARM_MUTE_BUZZER"
        const val ACTION_SHUTOFF_ALL = "com.smarthome.smarthome_app.ACTION_ALARM_SHUTOFF_ALL"
        const val EXTRA_DEVICE_ID = "device_id"
        const val EXTRA_ALARM_TYPE = "alarm_type"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val devId = intent.getStringExtra(EXTRA_DEVICE_ID).orEmpty()
        val alarmType = intent.getStringExtra(EXTRA_ALARM_TYPE).orEmpty()

        AlarmSoundPlayer.stopSiren(context)
        if (devId.isNotEmpty()) {
            if (alarmType.isNotEmpty()) {
                SafetyMonitorService.markEpisodeSilenced(devId, alarmType)
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.cancel(SafetyMonitorService.notificationIdForDevice(devId))
        }

        if (intent.action == ACTION_MUTE_BUZZER || intent.action == ACTION_SHUTOFF_ALL) {
            val device = if (devId.isNotEmpty()) NativeControlStore.getDeviceById(context, devId) else null
            if (device != null) {
                val pendingResult = goAsync()
                val isShutoff = (intent.action == ACTION_SHUTOFF_ALL)
                NativeEspClient.executor.execute {
                    try {
                        if (isShutoff) {
                            NativeEspClient.setRelay(context, device, NativeControlStore.ALL_RELAYS_ID, "off")
                        }
                        NativeEspClient.muteBuzzer(context, device)
                    } finally {
                        pendingResult.finish()
                    }
                }
            }
        }
    }
}
