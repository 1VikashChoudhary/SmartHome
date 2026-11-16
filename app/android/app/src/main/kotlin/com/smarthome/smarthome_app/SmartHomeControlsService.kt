package com.smarthome.smarthome_app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.controls.Control
import android.service.controls.ControlsProviderService
import android.service.controls.DeviceTypes
import android.service.controls.actions.BooleanAction
import android.service.controls.actions.ControlAction
import android.service.controls.templates.ControlButton
import android.service.controls.templates.ToggleTemplate
import androidx.annotation.RequiresApi
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Flow
import java.util.concurrent.atomic.AtomicBoolean
import java.util.function.Consumer

@RequiresApi(Build.VERSION_CODES.R)
class SmartHomeControlsService : ControlsProviderService() {

    private class ActiveSession(
        val controlIds: List<String>,
        val subscriber: Flow.Subscriber<in Control>
    ) {
        val cancelled = AtomicBoolean(false)
    }

    companion object {
        private const val DELIM_RELAY = "::relay::"
        private const val SUFFIX_ALL = "::all"
        private val activeSessions = CopyOnWriteArrayList<ActiveSession>()

        fun relayControlId(deviceId: String, relayId: Int): String = "$deviceId$DELIM_RELAY$relayId"
        fun allControlId(deviceId: String): String = "$deviceId$SUFFIX_ALL"

        fun parseControlId(controlId: String): Pair<String, Int>? {
            if (controlId.endsWith(SUFFIX_ALL)) {
                val devId = controlId.removeSuffix(SUFFIX_ALL)
                return if (devId.isNotEmpty()) Pair(devId, NativeControlStore.ALL_RELAYS_ID) else null
            }
            val idx = controlId.lastIndexOf(DELIM_RELAY)
            if (idx <= 0) return null
            val devId = controlId.substring(0, idx)
            val relayId = controlId.substring(idx + DELIM_RELAY.length).toIntOrNull() ?: return null
            return Pair(devId, relayId)
        }

        fun mapIconToDeviceType(iconType: String?, relayId: Int = 0): Int {
            if (relayId == NativeControlStore.ALL_RELAYS_ID) return DeviceTypes.TYPE_SWITCH
            return when (iconType?.trim()?.lowercase()) {
                "fan" -> DeviceTypes.TYPE_FAN
                "ac" -> DeviceTypes.TYPE_AC_HEATER
                "geyser", "heater" -> DeviceTypes.TYPE_WATER_HEATER
                "tv" -> DeviceTypes.TYPE_TV
                "socket", "plug" -> DeviceTypes.TYPE_OUTLET
                "pump", "router", "switch" -> DeviceTypes.TYPE_SWITCH
                "light" -> DeviceTypes.TYPE_LIGHT
                else -> DeviceTypes.TYPE_LIGHT
            }
        }

        fun notifyDeviceUpdated(context: Context, deviceId: String) {
            if (activeSessions.isEmpty()) return
            val dev = NativeControlStore.getDeviceById(context, deviceId) ?: return
            for (session in activeSessions) {
                if (session.cancelled.get()) continue
                for (cid in session.controlIds) {
                    val parsed = parseControlId(cid) ?: continue
                    if (parsed.first == deviceId) {
                        val control = buildStatefulControl(context, cid, dev, parsed.second, online = dev.isOnline)
                        try {
                            session.subscriber.onNext(control)
                        } catch (_: Exception) {
                        }
                    }
                }
            }
        }

        private fun buildAppIntent(context: Context, deviceId: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = MainActivity.ACTION_OPEN_DEVICE
                putExtra(MainActivity.EXTRA_OPEN_DEVICE_ID, deviceId)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun buildStatelessControl(
            context: Context,
            controlId: String,
            device: NativeDevice,
            relay: NativeRelay?,
            relayId: Int
        ): Control {
            val title = if (relayId == NativeControlStore.ALL_RELAYS_ID) {
                "All Relays"
            } else {
                relay?.name ?: "Relay ${relayId + 1}"
            }
            val iconRes = NativeControlStore.iconDrawableFor(relay?.icon, relayId)
            val pi = buildAppIntent(context, device.id, controlId.hashCode())
            return Control.StatelessBuilder(controlId, pi)
                .setTitle(title)
                .setSubtitle(device.name)
                .setZone(device.room)
                .setStructure("SmartHome Pro")
                .setDeviceType(mapIconToDeviceType(relay?.icon, relayId))
                .setCustomIcon(Icon.createWithResource(context, iconRes))
                .build()
        }

        fun buildStatefulControl(
            context: Context,
            controlId: String,
            device: NativeDevice?,
            relayId: Int,
            online: Boolean = device?.isOnline ?: false,
            unauthorized: Boolean = false
        ): Control {
            val devId = device?.id ?: (parseControlId(controlId)?.first ?: "smarthome")
            val pi = buildAppIntent(context, devId, controlId.hashCode())
            if (device == null) {
                return Control.StatefulBuilder(controlId, pi)
                    .setTitle("Removed Relay")
                    .setSubtitle("Controller removed")
                    .setStructure("SmartHome Pro")
                    .setDeviceType(DeviceTypes.TYPE_SWITCH)
                    .setStatus(Control.STATUS_NOT_FOUND)
                    .setStatusText("Removed")
                    .build()
            }

            val relay = if (relayId == NativeControlStore.ALL_RELAYS_ID) null
            else device.relays.firstOrNull { it.id == relayId }

            if (relayId != NativeControlStore.ALL_RELAYS_ID && (relay == null || !relay.enabled)) {
                return Control.StatefulBuilder(controlId, pi)
                    .setTitle(relay?.name ?: "Relay ${relayId + 1}")
                    .setSubtitle(device.name)
                    .setZone(device.room)
                    .setStructure("SmartHome Pro")
                    .setDeviceType(mapIconToDeviceType(relay?.icon, relayId))
                    .setCustomIcon(Icon.createWithResource(context, NativeControlStore.iconDrawableFor(relay?.icon, relayId)))
                    .setStatus(if (relay == null) Control.STATUS_NOT_FOUND else Control.STATUS_DISABLED)
                    .setStatusText(if (relay == null) "Not found" else "Disabled")
                    .build()
            }

            val isChecked = if (relayId == NativeControlStore.ALL_RELAYS_ID) {
                device.relays.any { it.enabled && it.state }
            } else {
                relay?.state ?: false
            }

            val title = if (relayId == NativeControlStore.ALL_RELAYS_ID) {
                "All Relays"
            } else {
                relay?.name ?: "Relay ${relayId + 1}"
            }
            val iconRes = NativeControlStore.iconDrawableFor(relay?.icon, relayId)
            val status = when {
                unauthorized || device.authLocked -> Control.STATUS_ERROR
                !online -> Control.STATUS_ERROR
                else -> Control.STATUS_OK
            }
            val statusText = when {
                unauthorized || device.authLocked -> "Login Required"
                !online -> "Offline"
                isChecked -> "ON"
                else -> "OFF"
            }

            val builder = Control.StatefulBuilder(controlId, pi)
                .setTitle(title)
                .setSubtitle(device.name)
                .setZone(device.room)
                .setStructure("SmartHome Pro")
                .setDeviceType(mapIconToDeviceType(relay?.icon, relayId))
                .setCustomIcon(Icon.createWithResource(context, iconRes))
                .setStatus(status)
                .setStatusText(statusText)
                .setControlTemplate(
                    ToggleTemplate(
                        controlId,
                        ControlButton(isChecked, if (isChecked) "Turn off" else "Turn on")
                    )
                )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                builder.setAuthRequired(false)
            }
            return builder.build()
        }
    }

    override fun createPublisherForAllAvailable(): Flow.Publisher<Control> {
        return createStatelessPublisher(maxItems = Int.MAX_VALUE)
    }

    override fun createPublisherForSuggested(): Flow.Publisher<Control> {
        return createStatelessPublisher(maxItems = 8)
    }

    private fun createStatelessPublisher(maxItems: Int): Flow.Publisher<Control> {
        return Flow.Publisher { subscriber ->
            val items = mutableListOf<Control>()
            val devices = NativeControlStore.getDevices(this)
            for (dev in devices) {
                val enabledRelays = dev.relays.filter { it.enabled }
                for (relay in enabledRelays) {
                    if (items.size >= maxItems) break
                    items.add(
                        buildStatelessControl(
                            this,
                            relayControlId(dev.id, relay.id),
                            dev,
                            relay,
                            relay.id
                        )
                    )
                }
                if (enabledRelays.size >= 2 && items.size < maxItems) {
                    items.add(
                        buildStatelessControl(
                            this,
                            allControlId(dev.id),
                            dev,
                            null,
                            NativeControlStore.ALL_RELAYS_ID
                        )
                    )
                }
                if (items.size >= maxItems) break
            }

            val cancelled = AtomicBoolean(false)
            val completed = AtomicBoolean(false)
            var cursor = 0
            subscriber.onSubscribe(object : Flow.Subscription {
                override fun request(n: Long) {
                    if (n <= 0 || cancelled.get() || completed.get()) return
                    var remaining = n
                    while (remaining > 0 && cursor < items.size && !cancelled.get()) {
                        subscriber.onNext(items[cursor])
                        cursor++
                        remaining--
                    }
                    if (cursor >= items.size && !cancelled.get() && completed.compareAndSet(false, true)) {
                        subscriber.onComplete()
                    }
                }

                override fun cancel() {
                    cancelled.set(true)
                }
            })
        }
    }

    override fun createPublisherFor(controlIds: MutableList<String>): Flow.Publisher<Control> {
        val idsCopy = controlIds.toList()
        return Flow.Publisher { subscriber ->
            val session = ActiveSession(idsCopy, subscriber)
            activeSessions.add(session)
            val started = AtomicBoolean(false)

            subscriber.onSubscribe(object : Flow.Subscription {
                override fun request(n: Long) {
                    if (n <= 0 || session.cancelled.get() || !started.compareAndSet(false, true)) return

                    // Emit immediate cached snapshot first so UI shows tiles without blank delay
                    val cachedDevices = NativeControlStore.getDevices(this@SmartHomeControlsService)
                        .associateBy { it.id }
                    val uniqueDeviceIds = linkedSetOf<String>()
                    for (cid in idsCopy) {
                        if (session.cancelled.get()) return
                        val parsed = parseControlId(cid)
                        if (parsed != null) {
                            uniqueDeviceIds.add(parsed.first)
                            val dev = cachedDevices[parsed.first]
                            subscriber.onNext(buildStatefulControl(this@SmartHomeControlsService, cid, dev, parsed.second))
                        } else {
                            subscriber.onNext(buildStatefulControl(this@SmartHomeControlsService, cid, null, 0))
                        }
                    }

                    // Poll each unique controller over LAN in parallel and push authoritative status
                    for (devId in uniqueDeviceIds) {
                        val dev = cachedDevices[devId] ?: continue
                        NativeEspClient.executor.execute {
                            if (session.cancelled.get()) return@execute
                            val res = NativeEspClient.fetchStatus(this@SmartHomeControlsService, dev)
                            if (session.cancelled.get()) return@execute
                            val latest = NativeControlStore.getDeviceById(this@SmartHomeControlsService, devId) ?: dev
                            for (cid in idsCopy) {
                                if (session.cancelled.get()) return@execute
                                val parsed = parseControlId(cid) ?: continue
                                if (parsed.first == devId) {
                                    subscriber.onNext(
                                        buildStatefulControl(
                                            this@SmartHomeControlsService,
                                            cid,
                                            latest,
                                            parsed.second,
                                            online = res.ok,
                                            unauthorized = res.unauthorized
                                        )
                                    )
                                }
                            }
                            SmartHomeTileRefreshHelper.requestAllTilesUpdate(this@SmartHomeControlsService)
                        }
                    }
                }

                override fun cancel() {
                    session.cancelled.set(true)
                    activeSessions.remove(session)
                }
            })
        }
    }

    override fun performControlAction(
        controlId: String,
        action: ControlAction,
        consumer: Consumer<Int>
    ) {
        val parsed = parseControlId(controlId)
        if (parsed == null || action !is BooleanAction) {
            consumer.accept(ControlAction.RESPONSE_FAIL)
            return
        }
        val (deviceId, relayId) = parsed
        val device = NativeControlStore.getDeviceById(this, deviceId)
        if (device == null) {
            consumer.accept(ControlAction.RESPONSE_FAIL)
            return
        }

        val targetState = action.newState
        val actionStr = if (targetState) "on" else "off"

        NativeEspClient.executor.execute {
            val (ok, unauthorized) = NativeEspClient.setRelay(this, device, relayId, actionStr)
            consumer.accept(
                if (ok) ControlAction.RESPONSE_OK else ControlAction.RESPONSE_FAIL
            )

            if (ok) {
                val statusRes = NativeEspClient.fetchStatus(this, device)
                if (!statusRes.ok) {
                    NativeControlStore.updateDeviceOnlineAndRelayState(
                        this,
                        device.id,
                        isOnline = true,
                        relayId = relayId,
                        newState = targetState
                    )
                }
                notifyDeviceUpdated(this, device.id)
                SmartHomeTileRefreshHelper.requestAllTilesUpdate(this)
            } else if (unauthorized) {
                for (session in activeSessions) {
                    if (session.cancelled.get()) continue
                    for (cid in session.controlIds) {
                        val p = parseControlId(cid) ?: continue
                        if (p.first == deviceId) {
                            try {
                                session.subscriber.onNext(
                                    buildStatefulControl(this, cid, device, p.second, online = false, unauthorized = true)
                                )
                            } catch (_: Exception) {
                            }
                        }
                    }
                }
            }
        }
    }
}
