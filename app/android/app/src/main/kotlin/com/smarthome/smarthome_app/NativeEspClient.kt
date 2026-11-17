package com.smarthome.smarthome_app

import android.content.Context
import android.util.Base64
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

data class NativeStatusResult(
    val ok: Boolean,
    val unauthorized: Boolean,
    val statusJson: JSONObject?
)

object NativeEspClient {
    val executor = Executors.newFixedThreadPool(4)

    private fun buildAuthHeader(username: String?, password: String?): String? {
        val cleanUser = username?.trim().orEmpty()
        val pass = password.orEmpty()
        val hasPassword = pass.isNotEmpty()
        val hasCustomUser = cleanUser.isNotEmpty() && !cleanUser.equals("admin", ignoreCase = true)
        if (!hasPassword && !hasCustomUser) return null

        val effectiveUser = if (cleanUser.isNotEmpty()) cleanUser else "admin"
        val token = Base64.encodeToString(
            "$effectiveUser:$pass".toByteArray(StandardCharsets.UTF_8),
            Base64.NO_WRAP
        )
        return "Basic $token"
    }

    fun fetchStatus(context: Context, device: NativeDevice): NativeStatusResult {
        val host = NativeControlStore.sanitizeHost(device.ip)
        if (host.isEmpty()) return NativeStatusResult(false, false, null)
        if (device.authLocked && device.authPassword.isNullOrEmpty()) return NativeStatusResult(false, true, null)

        var conn: HttpURLConnection? = null
        return try {
            val url = URL("http://$host/api/status")
            conn = (url.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                requestMethod = "GET"
                connectTimeout = 2500
                readTimeout = 3500
                useCaches = false
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Connection", "close")
                setRequestProperty("X-Requested-With", "SmartHome")
                buildAuthHeader(device.authUsername, device.authPassword)?.let {
                    setRequestProperty("Authorization", it)
                }
            }
            val code = conn.responseCode
            if (code == 401) {
                NativeControlStore.setDeviceAuthLocked(context, device.id, true)
                NativeStatusResult(false, true, null)
            } else if (code == 200) {
                val body = conn.inputStream.use { stream ->
                    BufferedReader(InputStreamReader(stream, StandardCharsets.UTF_8)).readText()
                }
                val json = JSONObject(body)
                NativeControlStore.updateDeviceFromStatus(context, device.id, json)
                NativeStatusResult(true, false, json)
            } else {
                NativeStatusResult(false, false, null)
            }
        } catch (_: Exception) {
            NativeControlStore.updateDeviceOnlineAndRelayState(context, device.id, isOnline = false)
            NativeStatusResult(false, false, null)
        } finally {
            try {
                conn?.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    fun setRelay(
        context: Context,
        device: NativeDevice,
        relayId: Int,
        action: String
    ): Pair<Boolean, Boolean> {
        val endpoint = if (relayId == NativeControlStore.ALL_RELAYS_ID) {
            "/api/relay/all"
        } else {
            "/api/relay"
        }
        val payload = JSONObject().apply {
            if (relayId != NativeControlStore.ALL_RELAYS_ID) {
                put("id", relayId)
            }
            put("action", action)
        }.toString()
        return postJson(context, device, endpoint, payload)
    }

    fun muteBuzzer(context: Context, device: NativeDevice): Pair<Boolean, Boolean> {
        val payload = JSONObject().put("action", "mute").toString()
        return postJson(context, device, "/api/buzzer", payload)
    }

    private fun postJson(
        context: Context,
        device: NativeDevice,
        endpoint: String,
        payload: String
    ): Pair<Boolean, Boolean> {
        val host = NativeControlStore.sanitizeHost(device.ip)
        if (host.isEmpty()) return Pair(false, false)
        if (device.authLocked && device.authPassword.isNullOrEmpty()) return Pair(false, true)

        var conn: HttpURLConnection? = null
        return try {
            val url = URL("http://$host$endpoint")
            conn = (url.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 2500
                readTimeout = 3500
                useCaches = false
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("X-Requested-With", "SmartHome")
                setRequestProperty("Connection", "close")
                buildAuthHeader(device.authUsername, device.authPassword)?.let {
                    setRequestProperty("Authorization", it)
                }
            }
            OutputStreamWriter(conn.outputStream, StandardCharsets.UTF_8).use { writer ->
                writer.write(payload)
                writer.flush()
            }
            val code = conn.responseCode
            if (code == 401) {
                NativeControlStore.setDeviceAuthLocked(context, device.id, true)
                Pair(false, true)
            } else if (code in 200..299) {
                Pair(true, false)
            } else {
                Pair(false, false)
            }
        } catch (_: Exception) {
            NativeControlStore.updateDeviceOnlineAndRelayState(context, device.id, isOnline = false)
            Pair(false, false)
        } finally {
            try {
                conn?.disconnect()
            } catch (_: Exception) {
            }
        }
    }
}
