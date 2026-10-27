package dev.dawnmesh.intercom

import android.Manifest
import android.annotation.SuppressLint
import androidx.annotation.RequiresApi
import android.content.*
import android.content.pm.PackageManager
import android.net.*
import android.net.wifi.aware.*
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Semaphore

/** Opt-in NAN pairing + TCP bridge. Never binds the process/default network. */
@RequiresApi(37)
@SuppressLint("MissingPermission")
internal class WifiAwarePlugin(private val context: Context, messenger: BinaryMessenger) {
    private val handler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "dev.dawnmesh.intercom/wifi_aware")
    private val events = EventChannel(messenger, "dev.dawnmesh.intercom/wifi_aware_events")
    private var sink: EventChannel.EventSink? = null
    private val manager get() = context.getSystemService(WifiAwareManager::class.java)
    private var owner: String? = null
    @Volatile private var generation = 0
    private var isHost = false
    private var localPort = 0
    private var aware: WifiAwareSession? = null
    private var discovery: DiscoverySession? = null
    private var listener: ServerSocket? = null
    private var receiver: BroadcastReceiver? = null
    private val peers = LinkedHashMap<String, PeerHandle>()
    private val paths = mutableMapOf<String, PeerHandle>()
    private val connectedPaths = mutableSetOf<String>()
    private val proxies = ConcurrentHashMap<String, ServerSocket>()
    private val pipes = ConcurrentHashMap<Socket, Socket>()
    private val slots = Semaphore(4)
    private val allowedAddresses = ConcurrentHashMap.newKeySet<InetAddress>()
    private var pin = ""
    private var pairingRequests = 0
    private var pendingPin: Pair<PeerHandle, String>? = null
    private val service = "_dawnmesh._tcp"

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "capabilities" -> result.success(capabilities())
                "start" -> {
                    val requested = call.argument<String>("owner")
                    val port = call.argument<Int>("port")
                    if (requested == null || port == null || port !in 1..65535) {
                        result.error("AWARE_ARGUMENT", "连接参数无效", null)
                    } else if (owner != null && owner != requested) {
                        result.success(mapOf("started" to false, "status" to "另一个房间正在使用 Wi-Fi Aware"))
                    } else if (capabilities()["available"] != true) {
                        result.success(mapOf("started" to false, "status" to capabilities()["reason"]))
                    } else {
                        stop(); owner = requested; localPort = port; isHost = call.argument<Boolean>("host") == true
                        pin = (100000 + java.security.SecureRandom().nextInt(900000)).toString()
                        start(); result.success(mapOf("started" to true, "status" to "等待附近设备与配对"))
                    }
                }
                "pair" -> {
                    if (call.argument<String>("owner") != owner) { result.success(null); return@setMethodCallHandler }
                    val peer = peers[call.argument<String>("peer")]
                    val entered = call.argument<String>("pin").orEmpty()
                    if (isHost) emit("pair", mapOf("pin" to pin, "status" to "请让对方选择本机并输入此配对码"))
                    else if (peer != null && entered.matches(Regex("[0-9]{6,12}"))) {
                        try {
                            pendingPin = peer to entered
                            discovery?.initiateBootstrappingRequest(peer, AwarePairingConfig.PAIRING_BOOTSTRAPPING_PIN_CODE_KEYPAD)
                        } catch (_: Exception) { status("系统无法开始配对") }
                    } else status("请先发现设备，再输入对方显示的配对码")
                    result.success(null)
                }
                "stop" -> { if (call.argument<String>("owner") == owner) stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    private fun capabilities(): Map<String, Any> {
        val hardware = context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_AWARE)
        val pairing = hardware && try { manager?.characteristics?.isAwarePairingSupported == true } catch (_: Exception) { false }
        val permission = context.checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES) == PackageManager.PERMISSION_GRANTED
        val available = pairing && permission && try { manager?.isAvailable == true } catch (_: Exception) { false }
        val reason = when {
            !hardware -> "需要提供标准配对数据通道的 Android 17 或更新系统及 Wi-Fi Aware 硬件"
            !pairing -> "设备未提供标准 Wi-Fi Aware 配对能力"
            !permission -> "请在系统设置允许附近 Wi-Fi 设备权限"
            !available -> "Wi-Fi Aware 暂不可用，可能与热点或 Wi-Fi 直连资源冲突"
            else -> "可以尝试系统配对；实际互通取决于两台设备"
        }
        return mapOf("supported" to pairing, "available" to available, "pairing" to pairing, "reason" to reason)
    }
    private fun start() {
        val token = generation
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                if (generation == token) { status("Wi-Fi Aware 状态变化，原连接继续", false); stop() }
            }
        }
        this.receiver = receiver
        try {
            context.registerReceiver(receiver, IntentFilter(WifiAwareManager.ACTION_WIFI_AWARE_STATE_CHANGED), Context.RECEIVER_NOT_EXPORTED)
            manager?.attach(object : AttachCallback() {
                override fun onAttached(session: WifiAwareSession) {
                    if (generation != token) { session.close(); return }
                    aware = session
                    if (isHost && !listen(token)) { status("加速监听未能开启", false); stop(); return }
                    val pairing = AwarePairingConfig.Builder().setPairingSetupEnabled(true)
                        .setPairingVerificationEnabled(true).setPairingCacheEnabled(true)
                        .setBootstrappingMethods(if (isHost) AwarePairingConfig.PAIRING_BOOTSTRAPPING_PIN_CODE_DISPLAY else AwarePairingConfig.PAIRING_BOOTSTRAPPING_PIN_CODE_KEYPAD).build()
                    val callback = discoveryCallback(token)
                    if (isHost) session.publish(PublishConfig.Builder().setServiceName(service)
                        .setPublishType(PublishConfig.PUBLISH_TYPE_UNSOLICITED).setPairingConfig(pairing)
                        .setServiceSpecificInfo("DawnMesh".toByteArray()).build(), callback, handler)
                    else session.subscribe(SubscribeConfig.Builder().setServiceName(service)
                        .setSubscribeType(SubscribeConfig.SUBSCRIBE_TYPE_ACTIVE).setPairingConfig(pairing).build(), callback, handler)
                }
                override fun onAttachFailed() { if (generation == token) { status("系统无法启用 Wi-Fi Aware", false); stop() } }
            }, handler)
        } catch (_: Exception) { status("系统未允许启用 Wi-Fi Aware", false); stop() }
    }
    private fun discoveryCallback(token: Int) = object : DiscoverySessionCallback() {
        override fun onPublishStarted(session: PublishDiscoverySession) { if (generation == token) { discovery = session; emit("pair", mapOf("pin" to pin, "status" to "等待对方配对；请将配对码告知对方")) } else session.close() }
        override fun onSubscribeStarted(session: SubscribeDiscoverySession) { if (generation == token) discovery = session else session.close() }
        override fun onServiceDiscovered(peer: PeerHandle, info: ByteArray, filter: List<ByteArray>) {
            if (generation != token || peers.size >= 4) return
            val id = peer.hashCode().toString(); peers[id] = peer
            emit("pair", mapOf("peer" to id, "status" to "发现附近设备，请输入该设备显示的配对码"))
        }
        override fun onBootstrappingSucceeded(peer: PeerHandle, method: Int) {
            if (generation != token) return
            if (isHost) emit("pair", mapOf("pin" to pin, "status" to "将配对码输入对方设备"))
            else pendingPin?.takeIf { it.first == peer }?.let {
                try { discovery?.initiatePairingRequest(peer, "DawnMesh-${peer.hashCode()}", Characteristics.WIFI_AWARE_CIPHER_SUITE_NCS_PK_PASN_128, it.second) }
                catch (_: Exception) { status("系统无法完成配对请求") }
                pendingPin = null
            }
        }
        override fun onPairingSetupRequestReceived(peer: PeerHandle, requestId: Int) {
            if (generation != token || !isHost) return
            if (++pairingRequests > 8) {
                try { discovery?.rejectPairingRequest(requestId, peer) } catch (_: Exception) {}
                status("配对尝试已达上限；可关闭加速后重试")
                return
            }
            try { discovery?.acceptPairingRequest(requestId, peer, "DawnMesh-${peer.hashCode()}", Characteristics.WIFI_AWARE_CIPHER_SUITE_NCS_PK_PASN_128, pin) }
            catch (_: Exception) { status("配对未完成") }
        }
        override fun onPairingSetupSucceeded(peer: PeerHandle, alias: String) { if (generation == token) requestPath(peer, token) }
        override fun onPairingVerificationSucceed(peer: PeerHandle, alias: String) { if (generation == token) requestPath(peer, token) }
        override fun onDataPathRequestReceived(peer: PeerHandle) {
            if (generation != token || !isHost) return
            val session = discovery as? PublishDiscoverySession ?: return
            try {
                val id = peer.hashCode().toString()
                if (!paths.containsKey(id)) { session.rejectDataPathRequest(peer); return }
                val request = AwareDataPathRequest.Builder().setPort(listener!!.localPort).setTransportProtocol(6).build()
                if (!session.acceptDataPathRequest(peer, request)) status("系统未接受加速通道，原连接继续")
            } catch (_: Exception) { status("加速通道未建立，原连接继续") }
        }
        override fun onDataPathConnected(peer: PeerHandle, info: WifiAwareNetworkInfo) {
            if (generation != token) return
            val id = peer.hashCode().toString()
            if (!paths.containsKey(id) || !connectedPaths.add(id)) return
            if (!isHost) {
                val address = info.peerIpv6Addr
                if (address == null || info.port !in 1..65535) { releasePath(id); return }
                openProxy(id, address, info.port, token)
            } else {
                info.peerIpv6Addr?.let { allowedAddresses.add(it) }
                status("已配对的加速通道可用")
            }
        }
        override fun onDataPathDisconnected(peer: PeerHandle) {
            if (generation == token) { releasePath(peer.hashCode().toString()); status("加速通道断开，原连接继续") }
        }
        override fun onDataPathRequestFailed(peer: PeerHandle, reason: Int) {
            if (generation == token) { releasePath(peer.hashCode().toString()); status("加速通道未建立，原连接继续") }
        }
        override fun onPairingSetupFailed(peer: PeerHandle) { if (generation == token) status("配对未完成，请确认对方的配对码") }
        override fun onBootstrappingFailed(peer: PeerHandle) { if (generation == token) status("设备未能完成配对引导，原连接继续") }
        override fun onSessionConfigFailed() { if (generation == token) { status("系统拒绝 Wi-Fi Aware 服务配置", false); stop() } }
        override fun onSessionTerminated() { if (generation == token) { status("Wi-Fi Aware 已停止，原连接继续", false); stop() } }
    }
    private fun requestPath(peer: PeerHandle, token: Int) {
        val session = discovery ?: return
        val id = peer.hashCode().toString()
        if (paths.containsKey(id) || paths.size >= 4) return
        paths[id] = peer
        // Use the framework-managed paired data-path API. The old Network
        // specifier API requires application PMK material and cannot substitute
        // for a PASN pairing cache. Never downgrade to an open NAN data path.
        if (!isHost) {
            val subscriber = session as? SubscribeDiscoverySession ?: return
            try {
                if (!subscriber.initiateDataPathRequest(peer, AwareDataPathRequest.Builder().build())) {
                    releasePath(id); status("系统无法建立已配对的加速通道")
                }
            } catch (_: Exception) { releasePath(id); status("系统无法建立已配对的加速通道") }
        }
        handler.postDelayed({
            if (generation == token && paths.containsKey(id) && !connectedPaths.contains(id)) {
                releasePath(id); status("加速通道未建立，原连接继续")
            }
        }, 15000)
    }
    private fun listen(token: Int): Boolean = try {
        val server = ServerSocket().apply { reuseAddress = true; bind(InetSocketAddress(InetAddress.getByName("::"), 0), 4) }
        listener = server
        Thread({
            while (generation == token && !server.isClosed) {
                val incoming = try { server.accept() } catch (_: Exception) { break }
                if (!allowedAddresses.contains(incoming.inetAddress) || !slots.tryAcquire()) { incoming.close(); continue }
                Thread({
                    val local = Socket()
                    try { local.connect(InetSocketAddress("127.0.0.1", localPort), 4000); pipe(incoming, local, token) }
                    catch (_: Exception) { incoming.close(); try { local.close() } catch (_: Exception) {}; slots.release() }
                }, "dawn-aware-host").start()
            }
        }, "dawn-aware-accept").start(); true
    } catch (_: Exception) { false }
    private fun openProxy(id: String, address: InetAddress, port: Int, token: Int) {
        if (!slots.tryAcquire()) return
        val server = try { ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).apply { soTimeout = 15000 } }
            catch (_: Exception) { slots.release(); return }
        proxies[id] = server
        emit("endpoint", mapOf("port" to server.localPort))
        Thread({
            var local: Socket? = null
            var remote: Socket? = null
            try {
                local = server.accept(); server.close(); proxies.remove(id, server)
                // The API supplies the scoped link-local IPv6 address for its NAN
                // interface; never change the process's default network.
                remote = Socket()
                remote.connect(InetSocketAddress(address, port), 4000)
                pipe(local, remote, token)
            } catch (_: Exception) { try { local?.close(); remote?.close() } catch (_: Exception) {}; slots.release() }
            finally { try { server.close() } catch (_: Exception) {}; proxies.remove(id, server) }
        }, "dawn-aware-proxy").start()
    }
    private fun pipe(a: Socket, b: Socket, token: Int) {
        if (generation != token) { a.close(); b.close(); slots.release(); return }
        a.tcpNoDelay = true; b.tcpNoDelay = true
        a.soTimeout = 30000; b.soTimeout = 30000
        pipes[a] = b
        val closed = java.util.concurrent.atomic.AtomicBoolean()
        fun close() { if (closed.compareAndSet(false, true)) { pipes.remove(a); try { a.close() } catch (_: Exception) {}; try { b.close() } catch (_: Exception) {}; slots.release() } }
        fun copy(source: Socket, target: Socket) {
            try { val buffer = ByteArray(16384); val input = source.getInputStream(); val output = target.getOutputStream()
                while (!closed.get()) { val size = input.read(buffer); if (size < 0) break; output.write(buffer, 0, size) }
            } catch (_: Exception) {} finally { close() }
        }
        Thread({ copy(a,b) }, "dawn-aware-up").start()
        Thread({ copy(b,a) }, "dawn-aware-down").start()
    }
    private fun releasePath(id: String) {
        paths.remove(id)?.let { try { discovery?.releaseDataPath(it) } catch (_: Exception) {} }
        connectedPaths.remove(id)
        allowedAddresses.clear()
        try { proxies.remove(id)?.close() } catch (_: Exception) {}
        // An interface loss can invalidate several native paths at once. Close
        // accelerator sockets promptly; room LAN/cloud sockets are independent.
        pipes.forEach { (a,b) -> try { a.close(); b.close() } catch (_: Exception) {} }
    }
    private fun emit(type: String, values: Map<String, Any> = emptyMap()) { sink?.success(mapOf("owner" to owner, "type" to type) + values) }
    private fun status(text: String, active: Boolean = true) { emit("status", mapOf("status" to text, "active" to active)) }
    private fun stop() {
        generation++
        receiver?.let { try { context.unregisterReceiver(it) } catch (_: Exception) {} }; receiver = null
        try { listener?.close() } catch (_: Exception) {}; listener = null
        paths.keys.toList().forEach(::releasePath)
        pipes.forEach { (a,b) -> try { a.close(); b.close() } catch (_: Exception) {} }; pipes.clear()
        discovery?.close(); discovery = null; aware?.close(); aware = null
        peers.clear(); pendingPin = null; pin = ""; pairingRequests = 0; owner = null
    }
    fun dispose() { stop(); channel.setMethodCallHandler(null); events.setStreamHandler(null); sink = null }
}
