package com.smarthome.smarthome_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Automatically resumes the Background Safety Alarm Monitor after phone reboot
 * when the user has enabled it in App Settings.
 */
class SafetyBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED &&
            NativeControlStore.getSafetyMonitorEnabled(context)) {
            SafetyMonitorService.syncServiceState(context)
        }
    }
}
