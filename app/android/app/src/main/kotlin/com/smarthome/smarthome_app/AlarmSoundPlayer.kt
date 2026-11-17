package com.smarthome.smarthome_app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Plays loud looping emergency sirens over Android's ALARM stream (`USAGE_ALARM`),
 * ensuring critical gas/temperature hazards sound even when media volume is muted
 * or the phone is locked.
 */
object AlarmSoundPlayer {
    private val lock = Any()
    private var mediaPlayer: MediaPlayer? = null
    private var toneGenerator: ToneGenerator? = null
    private var toneRunnable: Runnable? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var playing = false

    fun isPlaying(): Boolean = playing

    fun startSiren(context: Context, force: Boolean = false) {
        if (!force && !NativeControlStore.getAlarmSirenEnabled(context)) return
        synchronized(lock) {
            if (playing) return
            playing = true
            acquireSirenWakeLock(context)
            startVibration(context)
            if (tryStartMediaPlayer(context)) {
                return
            }
            startFallbackToneLoop()
        }
    }

    fun stopSiren(context: Context) {
        synchronized(lock) {
            playing = false
            try {
                mediaPlayer?.let { mp ->
                    if (mp.isPlaying) mp.stop()
                    mp.reset()
                    mp.release()
                }
            } catch (_: Exception) {
            } finally {
                mediaPlayer = null
            }

            toneRunnable?.let { mainHandler.removeCallbacks(it) }
            toneRunnable = null
            try {
                toneGenerator?.release()
            } catch (_: Exception) {
            } finally {
                toneGenerator = null
            }

            stopVibration(context)
            releaseSirenWakeLock()
        }
    }

    private fun acquireSirenWakeLock(context: Context) {
        try {
            val pm = context.applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            if (wakeLock == null) {
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SmartHome:AlarmSirenLock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(5 * 60 * 1000L)
            }
        } catch (_: Exception) {
        }
    }

    private fun releaseSirenWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {
        }
    }

    private fun tryStartMediaPlayer(context: Context): Boolean {
        val candidates = listOf<Uri?>(
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        )
        for (uri in candidates) {
            if (uri == null) continue
            try {
                val mp = MediaPlayer()
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                mp.setAudioAttributes(attrs)
                mp.setDataSource(context.applicationContext, uri)
                mp.isLooping = true
                mp.prepare()
                mp.setVolume(1.0f, 1.0f)
                mp.start()
                mediaPlayer = mp
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun startFallbackToneLoop() {
        try {
            val tg = ToneGenerator(AudioManager.STREAM_ALARM, 100)
            toneGenerator = tg
            val r = object : Runnable {
                override fun run() {
                    if (!playing) return
                    try {
                        toneGenerator?.startTone(ToneGenerator.TONE_CDMA_EMERGENCY_RINGBACK, 700)
                    } catch (_: Exception) {
                    }
                    mainHandler.postDelayed(this, 1000L)
                }
            }
            toneRunnable = r
            mainHandler.post(r)
        } catch (_: Exception) {
        }
    }

    @Suppress("DEPRECATION")
    private fun getVibrator(context: Context): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vm?.defaultVibrator
        } else {
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    @Suppress("DEPRECATION")
    private fun startVibration(context: Context) {
        try {
            val vib = getVibrator(context) ?: return
            if (!vib.hasVibrator()) return
            val pattern = longArrayOf(0, 500, 250, 500, 250)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                vib.vibrate(pattern, 0)
            }
        } catch (_: Exception) {
        }
    }

    private fun stopVibration(context: Context) {
        try {
            getVibrator(context)?.cancel()
        } catch (_: Exception) {
        }
    }
}
