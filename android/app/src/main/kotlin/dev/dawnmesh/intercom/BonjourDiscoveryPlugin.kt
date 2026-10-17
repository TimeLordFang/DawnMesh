package dev.dawnmesh.intercom

import android.annotation.TargetApi
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.util.UUID
import java.util.concurrent.Executor

/** Standard LAN Bonjour, independent of Android Wi-Fi P2P service discovery. */
class BonjourDiscoveryPlugin(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val manager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executor { handler.post(it) }
    private val method = MethodChannel(messenger, "dev.dawnmesh.intercom/bonjour")
    private val events = EventChannel(messenger, "dev.dawnmesh.intercom/bonjour_events")
    private var sink: EventChannel.EventSink? = null
    private val clients = mutableMapOf<String, Client>()
    private val resolutions = ArrayDeque<Pair<Client, NsdServiceInfo>>()
    private var resolving = false
    private var disposed = false

    private inner class Client(val id: String, val magic: String, val type: String) {
        var discovery: NsdManager.DiscoveryListener? = null
        val known = mutableSetOf<String>()
        val trackers = mutableMapOf<String, () -> Unit>()
        var publication: NsdManager.RegistrationListener? = null
        var advertised: Map<String, String>? = null
        fun active() = !disposed && clients[id] === this
    }

    init { method.setMethodCallHandler(this); events.setStreamHandler(this) }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }
    private fun key(info: NsdServiceInfo) = info.serviceName + "@" +
        if (Build.VERSION.SDK_INT >= 33) info.network.toString() else info.serviceType
    private fun error(client: Client, message: String) {
        if (client.active()) sink?.success(mapOf("id" to client.id, "type" to "error", "message" to message))
    }
    private fun removed(client: Client, key: String) {
        if (client.active()) sink?.success(mapOf("id" to client.id, "type" to "removed", "service" to key))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val magic = call.argument<String>("magic")
        val type = magic?.let(BonjourRoomMetadata::serviceType)
        if (id == null || magic == null || type == null || manager == null || disposed) {
            result.success(false); return
        }
        when (call.method) {
            "start" -> {
                stop(id)
                val client = Client(id, magic, type)
                clients[id] = client
                val started = start(client)
                if (!started) stop(id)
                result.success(started)
            }
            "advertise" -> {
                val client = clients[id]
                val port = call.argument<Int>("port") ?: 0
                val room = call.argument<String>("roomId").orEmpty()
                if (client == null || client.magic != magic || port !in 1..65535 || room.isBlank()) result.success(false)
                else {
                    val values = mapOf(
                        "magic" to magic, "roomId" to BonjourRoomMetadata.text(room),
                        "roomName" to BonjourRoomMetadata.text(call.argument<String>("roomName").orEmpty()),
                        "hostNickname" to BonjourRoomMetadata.text(call.argument<String>("hostNickname").orEmpty()),
                        "members" to (call.argument<Int>("members") ?: 1).coerceIn(0, 99).toString(),
                        "port" to port.toString(),
                    )
                    advertise(client, values, port); result.success(true)
                }
            }
            "stopAdvertising" -> { clients[id]?.let(::stopAdvertising); result.success(null) }
            "stop" -> { stop(id); result.success(null) }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION") // API 26-32 discovery; tracked resolution is used on API 34+.
    private fun start(client: Client): Boolean {
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) = Unit
            override fun onDiscoveryStopped(type: String) = Unit
            override fun onStartDiscoveryFailed(type: String, code: Int) { handler.post {
                runCatching { manager!!.stopServiceDiscovery(this) }
                error(client, "同网 Wi-Fi 发现启动失败（$code），请检查附近设备/本地网络权限后刷新")
            } }
            override fun onStopDiscoveryFailed(type: String, code: Int) = Unit
            override fun onServiceFound(info: NsdServiceInfo) { handler.post {
                if (!client.active() || info.serviceType.trimEnd('.') != client.type.trimEnd('.')) return@post
                val key = key(info)
                if (client.known.size >= 64 || !client.known.add(key)) return@post
                if (Build.VERSION.SDK_INT >= 34) track(client, info, key)
                else { resolutions.add(client to info); resolveNext() }
            } }
            override fun onServiceLost(info: NsdServiceInfo) { handler.post {
                val key = key(info)
                client.known.remove(key); client.trackers.remove(key)?.invoke(); removed(client, key)
            } }
        }
        client.discovery = listener
        return try {
            manager!!.discoverServices(client.type, NsdManager.PROTOCOL_DNS_SD, listener); true
        } catch (failure: RuntimeException) {
            error(client, "同网 Wi-Fi 发现不可用：${failure.message}"); false
        }
    }

    @TargetApi(34)
    private fun track(client: Client, info: NsdServiceInfo, key: String) {
        val callback = object : NsdManager.ServiceInfoCallback {
            override fun onServiceUpdated(serviceInfo: NsdServiceInfo) { publishRoom(client, serviceInfo, key) }
            override fun onServiceLost() { removed(client, key) }
            override fun onServiceInfoCallbackRegistrationFailed(code: Int) {
                client.trackers.remove(key); client.known.remove(key)
                error(client, "同网 Wi-Fi 房间解析失败（$code），请刷新重试")
            }
            override fun onServiceInfoCallbackUnregistered() = Unit
        }
        client.trackers[key] = { runCatching { manager!!.unregisterServiceInfoCallback(callback) } }
        try { manager!!.registerServiceInfoCallback(info, executor, callback) }
        catch (failure: RuntimeException) {
            client.trackers.remove(key); client.known.remove(key)
            error(client, "同网 Wi-Fi 房间解析失败：${failure.message}")
        }
    }

    @Suppress("DEPRECATION") // Older Android supports only one active resolve operation.
    private fun resolveNext() {
        if (resolving || disposed) return
        while (resolutions.isNotEmpty()) {
            val (client, info) = resolutions.removeFirst()
            val key = key(info)
            if (!client.active() || key !in client.known) continue
            resolving = true
            try {
                manager!!.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, code: Int) { handler.post {
                        client.known.remove(key); resolving = false; resolveNext()
                    } }
                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) { handler.post {
                        publishRoom(client, serviceInfo, key); resolving = false; resolveNext()
                    } }
                })
            } catch (failure: RuntimeException) { resolving = false; client.known.remove(key); continue }
            return
        }
    }

    @Suppress("DEPRECATION")
    private fun publishRoom(client: Client, info: NsdServiceInfo, key: String) {
        if (!client.active() || key !in client.known) return
        val addresses = if (Build.VERSION.SDK_INT >= 34) info.hostAddresses else listOfNotNull(info.host)
        val address = addresses.firstOrNull { it is Inet4Address } ?: addresses.firstOrNull() ?: return
        val fields = info.attributes.mapValues { it.value?.toString(Charsets.UTF_8).orEmpty() }
        val room = BonjourRoomMetadata.room(fields, client.magic, address.hostAddress.orEmpty(), info.port) ?: return
        sink?.success(room + mapOf("id" to client.id, "service" to key))
    }

    private fun advertise(client: Client, values: Map<String, String>, port: Int) {
        if (client.advertised == values && client.publication != null) return
        stopAdvertising(client)
        val info = NsdServiceInfo().apply {
            serviceType = client.type
            serviceName = "DawnMesh-${UUID.randomUUID().toString().take(8)}"
            this.port = port
            values.forEach { (key, value) -> setAttribute(key, value) }
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) { handler.post {
                if (!client.active() || client.publication !== this) runCatching { manager!!.unregisterService(this) }
            } }
            override fun onRegistrationFailed(info: NsdServiceInfo, code: Int) { handler.post {
                if (client.publication === this) {
                    client.publication = null; client.advertised = null
                    error(client, "同网 Wi-Fi 房间发布失败（$code）")
                }
            } }
            override fun onServiceUnregistered(info: NsdServiceInfo) = Unit
            override fun onUnregistrationFailed(info: NsdServiceInfo, code: Int) = Unit
        }
        client.advertised = values; client.publication = listener
        try { manager!!.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener) }
        catch (failure: RuntimeException) {
            client.publication = null; client.advertised = null
            error(client, "同网 Wi-Fi 房间发布失败：${failure.message}")
        }
    }

    private fun stopAdvertising(client: Client) {
        client.publication?.let { runCatching { manager!!.unregisterService(it) } }
        client.publication = null; client.advertised = null
    }
    private fun stop(id: String) {
        val client = clients.remove(id) ?: return
        client.discovery?.let { runCatching { manager!!.stopServiceDiscovery(it) } }
        client.trackers.values.toList().forEach { it() }; client.trackers.clear()
        client.known.clear(); stopAdvertising(client)
        resolutions.removeAll { it.first === client }
    }
    fun onLocalNetworkPermissionGranted() {
        // The home screen may have started browsing before the first system
        // permission dialog completed. Retry without requiring an app restart.
        clients.values.toList().forEach { old ->
            val values = old.advertised
            stop(old.id)
            val client = Client(old.id, old.magic, old.type)
            clients[client.id] = client
            start(client)
            if (values != null) advertise(client, values, values.getValue("port").toInt())
        }
    }
    fun dispose() {
        disposed = true
        clients.keys.toList().forEach(::stop)
        resolutions.clear(); sink = null
        method.setMethodCallHandler(null); events.setStreamHandler(null)
    }
}
