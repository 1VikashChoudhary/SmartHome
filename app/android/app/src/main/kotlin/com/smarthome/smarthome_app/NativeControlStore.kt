package com.smarthome.smarthome_app

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class NativeRelay(
    val id: Int,
    val name: String,
    val state: Boolean,
    val enabled: Boolean,
    val icon: String
)

data class NativeDevice(
    val id: String,
    val name: String,
    val room: String,
    val ip: String,
    val authRequired: Boolean,
    val authLocked: Boolean,
    val isOnline: Boolean,
    val numRelays: Int,
    val relays: List<NativeRelay>,
    val authUsername: String?,
    val authPassword: String?
)

data class TileSlotAssignment(
    val slot: Int,
    val deviceId: String,
    val relayId: Int, // -1 = All Relays Master
    val customLabel: String?
)

object NativeControlStore {
    const val MAX_TILE_SLOTS = 12
    const val ALL_RELAYS_ID = -1

    private const val PREF_STORE = "smarthome_native_controls"
    private const val PREF_CREDS = "smarthome_native_creds_enc"
    private const val KEY_DEVICES = "devices_json"
    private const val KEY_SLOTS = "tile_slots_json"
    private const val KEY_CRED_PREFIX = "cred_"
    private const val KEYSTORE_ALIAS = "smarthome_native_cred_key"
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"

    private val lock = Any()

    @JvmStatic
    fun sanitizeHost(raw: String?): String {
        if (raw == null) return ""
        var s = raw.trim()
        if (s.startsWith("http://", ignoreCase = true)) {
            s = s.substring(7)
        } else if (s.startsWith("https://", ignoreCase = true)) {
            s = s.substring(8)
        }
        val slashIdx = s.indexOf('/')
        if (slashIdx >= 0) {
            s = s.substring(0, slashIdx)
        }
        return s.trim()
    }

    fun iconDrawableFor(iconType: String?, relayId: Int = 0): Int {
        if (relayId == ALL_RELAYS_ID) return R.drawable.ic_qs_switch
        return when (iconType?.trim()?.lowercase()) {
            "fan" -> R.drawable.ic_qs_fan
            "ac" -> R.drawable.ic_qs_ac
            "geyser", "heater" -> R.drawable.ic_qs_heater
            "tv" -> R.drawable.ic_qs_tv
            "socket", "plug" -> R.drawable.ic_qs_outlet
            "pump" -> R.drawable.ic_qs_pump
            "router", "switch" -> R.drawable.ic_qs_switch
            "light" -> R.drawable.ic_qs_light
            else -> R.drawable.ic_qs_light
        }
    }

    fun syncDevicesFromMaps(context: Context, rawDevices: List<Map<String, Any?>>) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREF_STORE, Context.MODE_PRIVATE)
            val credsPrefs = context.getSharedPreferences(PREF_CREDS, Context.MODE_PRIVATE)
            val arr = JSONArray()
            val validDeviceIds = mutableSetOf<String>()

            val credsEditor = credsPrefs.edit()

            for (devMap in rawDevices) {
                val id = devMap["id"]?.toString()?.trim().orEmpty()
                val ip = sanitizeHost(devMap["ip"]?.toString())
                if (id.isEmpty() || ip.isEmpty()) continue
                validDeviceIds.add(id)

                val name = devMap["name"]?.toString()?.ifBlank { "SmartHome" } ?: "SmartHome"
                val room = devMap["room"]?.toString()?.ifBlank { "Home" } ?: "Home"
                val authRequired = devMap["authRequired"] as? Boolean ?: false
                val authLocked = devMap["authLocked"] as? Boolean ?: false
                val isOnline = devMap["isOnline"] as? Boolean ?: false
                val numRelays = (devMap["numRelays"] as? Number)?.toInt() ?: 0

                val obj = JSONObject()
                obj.put("id", id)
                obj.put("name", name)
                obj.put("room", room)
                obj.put("ip", ip)
                obj.put("authRequired", authRequired)
                obj.put("authLocked", authLocked)
                obj.put("isOnline", isOnline)
                obj.put("numRelays", numRelays)

                val relaysArr = JSONArray()
                val rawRelays = devMap["relays"] as? List<*>
                if (rawRelays != null) {
                    for (rItem in rawRelays) {
                        val rMap = rItem as? Map<*, *> ?: continue
                        val rId = (rMap["id"] as? Number)?.toInt() ?: continue
                        val rObj = JSONObject()
                        rObj.put("id", rId)
                        rObj.put("name", rMap["name"]?.toString()?.ifBlank { "Relay ${rId + 1}" } ?: "Relay ${rId + 1}")
                        rObj.put("state", rMap["state"] as? Boolean ?: false)
                        rObj.put("enabled", rMap["enabled"] as? Boolean ?: true)
                        rObj.put("icon", rMap["icon"]?.toString()?.lowercase() ?: "light")
                        relaysArr.put(rObj)
                    }
                }
                obj.put("relays", relaysArr)
                arr.put(obj)

                val username = devMap["authUsername"]?.toString()?.trim()
                val password = devMap["authPassword"]?.toString()
                if (!password.isNullOrEmpty() || (!username.isNullOrEmpty() && !username.equals("admin", ignoreCase = true))) {
                    val credJson = JSONObject().apply {
                        put("u", if (username.isNullOrEmpty()) "admin" else username)
                        put("p", password ?: "")
                    }.toString()
                    val enc = encryptString(credJson)
                    if (enc != null) {
                        credsEditor.putString(KEY_CRED_PREFIX + id, enc)
                    }
                } else {
                    credsEditor.remove(KEY_CRED_PREFIX + id)
                }
            }

            // Clean up credentials for removed controllers
            for (k in credsPrefs.all.keys) {
                if (k.startsWith(KEY_CRED_PREFIX)) {
                    val devId = k.removePrefix(KEY_CRED_PREFIX)
                    if (!validDeviceIds.contains(devId)) {
                        credsEditor.remove(k)
                    }
                }
            }
            credsEditor.apply()
            prefs.edit().putString(KEY_DEVICES, arr.toString()).apply()
        }
    }

    fun getDevices(context: Context): List<NativeDevice> {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREF_STORE, Context.MODE_PRIVATE)
            val credsPrefs = context.getSharedPreferences(PREF_CREDS, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_DEVICES, null) ?: return emptyList()
            return try {
                val arr = JSONArray(raw)
                val out = mutableListOf<NativeDevice>()
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    val id = obj.optString("id", "")
                    val ip = sanitizeHost(obj.optString("ip", ""))
                    if (id.isEmpty() || ip.isEmpty()) continue

                    val relaysArr = obj.optJSONArray("relays")
                    val relays = mutableListOf<NativeRelay>()
                    if (relaysArr != null) {
                        for (j in 0 until relaysArr.length()) {
                            val ro = relaysArr.optJSONObject(j) ?: continue
                            relays.add(
                                NativeRelay(
                                    id = ro.optInt("id", j),
                                    name = ro.optString("name", "Relay ${j + 1}"),
                                    state = ro.optBoolean("state", false),
                                    enabled = ro.optBoolean("enabled", true),
                                    icon = ro.optString("icon", "light")
                                )
                            )
                        }
                    }

                    var user: String? = null
                    var pass: String? = null
                    val encCred = credsPrefs.getString(KEY_CRED_PREFIX + id, null)
                    if (!encCred.isNullOrEmpty()) {
                        val dec = decryptString(encCred)
                        if (!dec.isNullOrEmpty()) {
                            try {
                                val co = JSONObject(dec)
                                user = co.optString("u", "")
                                pass = co.optString("p", "")
                            } catch (_: Exception) {
                            }
                        }
                    }

                    out.add(
                        NativeDevice(
                            id = id,
                            name = obj.optString("name", "SmartHome"),
                            room = obj.optString("room", "Home"),
                            ip = ip,
                            authRequired = obj.optBoolean("authRequired", false),
                            authLocked = obj.optBoolean("authLocked", false),
                            isOnline = obj.optBoolean("isOnline", false),
                            numRelays = obj.optInt("numRelays", relays.size),
                            relays = relays,
                            authUsername = user,
                            authPassword = pass
                        )
                    )
                }
                out
            } catch (_: Exception) {
                emptyList()
            }
        }
    }

    fun getDeviceById(context: Context, deviceId: String): NativeDevice? {
        return getDevices(context).firstOrNull { it.id == deviceId }
    }

    fun updateDeviceFromStatus(context: Context, deviceId: String, statusJson: JSONObject) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREF_STORE, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_DEVICES, null) ?: return
            try {
                val arr = JSONArray(raw)
                var changed = false
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    if (obj.optString("id") != deviceId) continue

                    obj.put("isOnline", true)
                    obj.put("authLocked", false)
                    val devName = statusJson.optString("device_name", "")
                    if (devName.isNotEmpty()) obj.put("name", devName)
                    if (statusJson.has("auth_required")) {
                        obj.put("authRequired", statusJson.optBoolean("auth_required", obj.optBoolean("authRequired")))
                    }
                    val statusRelays = statusJson.optJSONArray("relays")
                    if (statusRelays != null) {
                        val existingRelays = obj.optJSONArray("relays")
                        val updatedRelays = JSONArray()
                        for (rIdx in 0 until statusRelays.length()) {
                            val sr = statusRelays.optJSONObject(rIdx) ?: continue
                            val id = sr.optInt("id", rIdx)
                            var prevIcon = "light"
                            if (existingRelays != null) {
                                for (k in 0 until existingRelays.length()) {
                                    val er = existingRelays.optJSONObject(k)
                                    if (er != null && er.optInt("id", k) == id) {
                                        prevIcon = er.optString("icon", "light")
                                        break
                                    }
                                }
                            }
                            val icon = sr.optString("icon", "").trim().lowercase().ifEmpty { prevIcon }
                            val rObj = JSONObject()
                            rObj.put("id", id)
                            rObj.put("name", sr.optString("name", "Relay ${id + 1}").ifBlank { "Relay ${id + 1}" })
                            rObj.put("state", sr.optBoolean("state", false))
                            rObj.put("enabled", sr.optBoolean("enabled", true))
                            rObj.put("icon", icon)
                            updatedRelays.put(rObj)
                        }
                        obj.put("relays", updatedRelays)
                        obj.put("numRelays", statusJson.optInt("num_relays", updatedRelays.length()))
                    }
                    changed = true
                    break
                }
                if (changed) {
                    prefs.edit().putString(KEY_DEVICES, arr.toString()).apply()
                }
            } catch (_: Exception) {
            }
        }
    }

    fun setDeviceAuthLocked(context: Context, deviceId: String, locked: Boolean) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREF_STORE, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_DEVICES, null) ?: return
            try {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    if (obj.optString("id") != deviceId) continue
                    obj.put("authLocked", locked)
                    if (locked) obj.put("authRequired", true)
                    prefs.edit().putString(KEY_DEVICES, arr.toString()).apply()
                    break
                }
            } catch (_: Exception) {
            }
        }
    }

    fun updateDeviceOnlineAndRelayState(
        context: Context,
        deviceId: String,
        isOnline: Boolean,
        relayId: Int? = null,
        newState: Boolean? = null
    ) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREF_STORE, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_DEVICES, null) ?: return
            try {
                val arr = JSONArray(raw)
                var changed = false
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    if (obj.optString("id") != deviceId) continue
                    obj.put("isOnline", isOnline)
                    if (relayId != null && newState != null) {
                        val relays = obj.optJSONArray("relays")
                        if (relays != null) {
                            for (j in 0 until relays.length()) {
                                val ro = relays.optJSONObject(j) ?: continue
                                if (relayId == ALL_RELAYS_ID || ro.optInt("id", j) == relayId) {
                                    if (ro.optBoolean("enabled", true)) {
                                        ro.put("state", newState)
                                    }
                                }
                            }
                        }
                    }
                    changed = true
                    break
                }
                if (changed) {
                    prefs.edit().putString(KEY_DEVICES, arr.toString()).apply()
                }
            } catch (_: Exception) {
            }
        }
    }

    fun getAllTileSlots(context: Context): Map<Int, TileSlotAssignment> {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREF_STORE, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_SLOTS, null) ?: return emptyMap()
            return try {
                val obj = JSONObject(raw)
                val out = mutableMapOf<Int, TileSlotAssignment>()
                val keys = obj.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val slot = key.toIntOrNull() ?: continue
                    if (slot !in 1..MAX_TILE_SLOTS) continue
                    val so = obj.optJSONObject(key) ?: continue
                    val deviceId = so.optString("deviceId", "")
                    if (deviceId.isEmpty()) continue
                    val relayId = so.optInt("relayId", 0)
                    val customLabel = so.optString("customLabel", "").trim().ifEmpty { null }
                    out[slot] = TileSlotAssignment(slot, deviceId, relayId, customLabel)
                }
                out
            } catch (_: Exception) {
                emptyMap()
            }
        }
    }

    fun getTileSlot(context: Context, slot: Int): TileSlotAssignment? {
        if (slot !in 1..MAX_TILE_SLOTS) return null
        return getAllTileSlots(context)[slot]
    }

    fun setTileSlot(
        context: Context,
        slot: Int,
        deviceId: String,
        relayId: Int,
        customLabel: String?
    ) {
        if (slot !in 1..MAX_TILE_SLOTS) return
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREF_STORE, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_SLOTS, null)
            val obj = try {
                if (raw.isNullOrEmpty()) JSONObject() else JSONObject(raw)
            } catch (_: Exception) {
                JSONObject()
            }
            val so = JSONObject()
            so.put("deviceId", deviceId)
            so.put("relayId", relayId)
            val trimmed = customLabel?.trim()
            if (!trimmed.isNullOrEmpty()) {
                so.put("customLabel", trimmed)
            }
            obj.put(slot.toString(), so)
            prefs.edit().putString(KEY_SLOTS, obj.toString()).apply()
        }
    }

    fun clearTileSlot(context: Context, slot: Int) {
        if (slot !in 1..MAX_TILE_SLOTS) return
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREF_STORE, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_SLOTS, null) ?: return
            try {
                val obj = JSONObject(raw)
                obj.remove(slot.toString())
                prefs.edit().putString(KEY_SLOTS, obj.toString()).apply()
            } catch (_: Exception) {
            }
        }
    }

    fun autoAssignSlots(context: Context): Int {
        val devices = getDevices(context)
        var slot = 1
        val newSlots = JSONObject()
        for (dev in devices) {
            val enabledRelays = dev.relays.filter { it.enabled }
            for (r in enabledRelays) {
                if (slot > MAX_TILE_SLOTS) break
                val so = JSONObject()
                so.put("deviceId", dev.id)
                so.put("relayId", r.id)
                newSlots.put(slot.toString(), so)
                slot++
            }
            if (slot > MAX_TILE_SLOTS) break
        }
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREF_STORE, Context.MODE_PRIVATE)
            prefs.edit().putString(KEY_SLOTS, newSlots.toString()).apply()
        }
        return slot - 1
    }

    private fun getOrCreateAesKey(): SecretKey? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        return try {
            val ks = KeyStore.getInstance(KEYSTORE_PROVIDER)
            ks.load(null)
            val existing = ks.getKey(KEYSTORE_ALIAS, null) as? SecretKey
            if (existing != null) return existing

            val keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
            val spec = KeyGenParameterSpec.Builder(
                KEYSTORE_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
            keyGen.init(spec)
            keyGen.generateKey()
        } catch (_: Exception) {
            null
        }
    }

    private fun encryptString(plaintext: String): String? {
        val key = getOrCreateAesKey() ?: return null
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val iv = cipher.iv
            val enc = cipher.doFinal(plaintext.toByteArray(StandardCharsets.UTF_8))
            val ivB64 = Base64.encodeToString(iv, Base64.NO_WRAP)
            val encB64 = Base64.encodeToString(enc, Base64.NO_WRAP)
            "v1:$ivB64:$encB64"
        } catch (_: Exception) {
            null
        }
    }

    private fun decryptString(payload: String): String? {
        if (!payload.startsWith("v1:")) return null
        val key = getOrCreateAesKey() ?: return null
        return try {
            val parts = payload.split(":")
            if (parts.size != 3) return null
            val iv = Base64.decode(parts[1], Base64.NO_WRAP)
            val cipherBytes = Base64.decode(parts[2], Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            String(cipher.doFinal(cipherBytes), StandardCharsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }
}
