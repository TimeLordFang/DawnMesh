package dev.dawnmesh.intercom

import android.Manifest
import android.annotation.TargetApi
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.EOFException
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * 蓝牙房的 BLE L2CAP CoC（面向连接通道）实现。
 *
 * 为什么不是经典蓝牙 RFCOMM：L2CAP CoC 在 iOS 侧有 CBL2CAPChannel 对应物、
 * 不需要 MFi，鸿蒙 NEXT 也有原生支持，是三端能共用同一套协议的唯一选择。
 *
 * 关键约束：**PSM 由系统动态分配，不能写死**。房主用
 * `listenUsingInsecureL2capChannel()` 拿到真实 PSM 后，把它放进 BLE 广播的
 * 厂商自定义数据里；客户端扫描时读出来，再用它建立 L2CAP 通道。
 *
 * 广播预算（各 31 字节）：
 *   主包    flags(3) + 128 位服务 UUID(18) + 厂商 PSM/人数(7) = 28
 *   扫描响应 厂商数据 = 1+1+2(公司ID) + 2(PSM) + 1(人数) + 房名 UTF-8(≤24)
 *
 * L2CAP CoC 需要 API 29（Android 10）；低于此版本的设备开不了蓝牙房。
 */
class BleL2capPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "DawnBle"

        private const val METHOD_CHANNEL = "dev.dawnmesh.intercom/ble_l2cap"
        private const val DATA_CHANNEL = "dev.dawnmesh.intercom/ble_l2cap_data"
        private const val SCAN_CHANNEL = "dev.dawnmesh.intercom/ble_l2cap_scan"

        /** 蓝牙房的服务标识，客户端按它过滤扫描结果。 */
        private val SERVICE_UUID: UUID =
            UUID.fromString("7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004")

        /** 0xFFFF 是蓝牙 SIG 保留给内部/测试用的公司标识。 */
        private const val MANUFACTURER_ID = 0xFFFF

        private const val FRAME_HEADER_SIZE = 6

        /** 与 Dart 侧 Frame.maxPayloadSize 严格一致：协议帧载荷上限就是 512。 */
        private const val MAX_PAYLOAD = 512

        /** 房主 1 台 + 客户端 5 台。 */
        private const val MAX_PEERS = 5

        /** 扫描响应里留给房名的字节数。 */
        private const val ROOM_NAME_BUDGET = 24
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val dataChannel = EventChannel(messenger, DATA_CHANNEL)
    private val scanChannel = EventChannel(messenger, SCAN_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var dataSink: EventChannel.EventSink? = null
    private var scanSink: EventChannel.EventSink? = null

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    // 房主侧
    private var serverSocket: BluetoothServerSocket? = null
    private var acceptThread: Thread? = null
    private val accepting = AtomicBoolean(false)
    private var advertiseCallback: AdvertiseCallback? = null
    private var pendingAdvertisingResult: MethodChannel.Result? = null
    private var pendingConnectSocket: BluetoothSocket? = null
    private var connectionGeneration = 0
    private var advertisedRoomName: String = ""
    private var advertisedPsm: Int = 0
    private var advertisedMemberCount: Int = 1
    private var hostRadioRecoveryPending = false
    private var hostRadioRecoveryGeneration = 0
    private var receiverRegistered = false

    // 客户端侧
    private var hostLink: PeerLink? = null

    /** address -> 链路。房主侧是全部客户端，客户端侧只有房主一条。 */
    private val peers = ConcurrentHashMap<String, PeerLink>()

    private var isHost = false
    private var scanning = false

    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(receiverContext: Context?, intent: Intent?) {
            if (intent?.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
            val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
            val previous = intent.getIntExtra(
                BluetoothAdapter.EXTRA_PREVIOUS_STATE,
                BluetoothAdapter.ERROR,
            )
            Log.i(TAG, "蓝牙适配器状态变化：$previous -> $state；isHost=$isHost")
            when (state) {
                BluetoothAdapter.STATE_TURNING_OFF,
                BluetoothAdapter.STATE_OFF -> if (isHost) suspendHostRadioForAdapterRestart()
                BluetoothAdapter.STATE_ON -> if (isHost && hostRadioRecoveryPending) {
                    scheduleHostRadioRecovery(delayMillis = 1_000)
                }
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        dataChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                dataSink = events
            }

            override fun onCancel(arguments: Any?) {
                dataSink = null
            }
        })
        scanChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                scanSink = events
            }

            override fun onCancel(arguments: Any?) {
                scanSink = null
            }
        })
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // 蓝牙状态广播由独立的系统蓝牙进程发出，Android 官方要求此类
            // 非 system-UID 广播使用 RECEIVER_EXPORTED 才能收到。
            context.registerReceiver(
                bluetoothStateReceiver,
                filter,
                Context.RECEIVER_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            context.registerReceiver(bluetoothStateReceiver, filter)
        }
        receiverRegistered = true
    }

    fun dispose() {
        stopEverything()
        if (receiverRegistered) {
            try {
                context.unregisterReceiver(bluetoothStateReceiver)
            } catch (_: IllegalArgumentException) {
            }
            receiverRegistered = false
        }
        methodChannel.setMethodCallHandler(null)
        dataChannel.setStreamHandler(null)
        scanChannel.setStreamHandler(null)
    }

    // --------------------------------------------------------- MethodChannel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(supportError() == null)

            "startAdvertising" -> {
                val error = supportError()
                if (error != null) {
                    result.error("UNSUPPORTED", error, null)
                    return
                }
                val roomName = call.argument<String>("roomName") ?: "蓝牙房"
                val memberCount = call.argument<Int>("memberCount") ?: 1
                startAdvertising(roomName, memberCount, result)
            }

            "updateMemberCount" -> {
                val count = call.argument<Int>("memberCount") ?: 1
                if (isHost && count != advertisedMemberCount) {
                    advertisedMemberCount = count
                    restartAdvertisingData()
                }
                result.success(true)
            }

            "startScan" -> {
                val error = supportError(scanning = true)
                if (error != null) {
                    result.error("UNSUPPORTED", error, null)
                    return
                }
                result.success(startScan())
            }

            "stopScan" -> {
                stopScan()
                result.success(true)
            }

            "connectL2cap" -> {
                val error = supportError()
                if (error != null) {
                    result.error("UNSUPPORTED", error, null)
                    return
                }
                val address = call.argument<String>("address")
                val psm = call.argument<Int>("psm") ?: 0
                if (address.isNullOrBlank() || psm !in 1..255) {
                    result.error("BAD_ARGS", "connectL2cap 需要 address 与有效的 psm", null)
                    return
                }
                connectL2cap(address, psm, result)
            }

            "sendL2capData" -> {
                val data = call.argument<ByteArray>("data")
                val realtime = call.argument<Boolean>("realtime") ?: false
                if (data == null) {
                    result.error("BAD_ARGS", "sendL2capData 缺少 data", null)
                    return
                }
                result.success(sendData(data, excludeAddress = null, realtime = realtime))
            }

            "flush" -> {
                val pending = peers.values.map { it.flush() }.toTypedArray()
                java.util.concurrent.CompletableFuture.allOf(*pending).whenComplete { _, error ->
                    mainHandler.post {
                        if (error == null) result.success(true)
                        else result.error("FLUSH_FAILED", "蓝牙发送队列未完成", null)
                    }
                }
            }

            "stop" -> {
                stopEverything()
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    /** 返回 null 表示可用，否则是给用户看的原因。 */
    private fun supportError(scanning: Boolean = false): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return "蓝牙房需要 Android 10 及以上（L2CAP 通道）"
        }
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            return "本机不支持低功耗蓝牙"
        }
        val a = adapter ?: return "本机没有蓝牙适配器"
        if (!hasBlePermissions()) return "缺少附近设备权限，请在系统设置 → 应用 → DawnMesh → 权限中允许后重试"
        if (!a.isEnabled) return "蓝牙未开启，请开启后重新扫描"
        if (scanning && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                return "Android 10/11 蓝牙扫描需要精确位置权限"
            }
            val location = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            if (location?.isLocationEnabled != true) return "Android 10/11 蓝牙扫描需要打开系统位置开关"
        }
        return null
    }

    private fun hasBlePermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return listOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_ADVERTISE,
        ).all {
            context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    // ------------------------------------------------------------ 房主：广播

    private fun startAdvertising(
        roomName: String,
        memberCount: Int,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "蓝牙对讲需要 Android 10 或更新版本", null)
            return
        }
        stopEverything()
        isHost = true
        advertisedRoomName = roomName
        advertisedMemberCount = memberCount

        val a = adapter ?: run {
            result.error("UNSUPPORTED", "没有蓝牙适配器", null)
            return
        }

        val server = try {
            @Suppress("MissingPermission")
            a.listenUsingInsecureL2capChannel()
        } catch (e: Exception) {
            Log.e(TAG, "打开 L2CAP 监听失败", e)
            result.error("L2CAP_LISTEN_FAILED", "无法开启蓝牙通道：${e.message}", null)
            return
        }

        serverSocket = server
        advertisedPsm = server.psm
        Log.i(TAG, "L2CAP 监听已开启，系统分配的 PSM = $advertisedPsm")

        accepting.set(true)
        acceptThread = Thread({ acceptLoop(server) }, "dawn-ble-accept").apply { start() }

        val advertiser = a.bluetoothLeAdvertiser
        if (advertiser == null) {
            stopEverything()
            result.error("UNSUPPORTED", "本机不支持 BLE 广播，无法作为蓝牙房主", null)
            return
        }

        pendingAdvertisingResult = result
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                mainHandler.post {
                    if (advertiseCallback !== this) return@post
                    Log.i(TAG, "BLE 广播已开启 (PSM=$advertisedPsm)")
                    pendingAdvertisingResult?.success(true)
                    pendingAdvertisingResult = null
                }
            }

            override fun onStartFailure(errorCode: Int) {
                mainHandler.post {
                    if (advertiseCallback !== this) return@post
                    val message = "蓝牙广播失败（错误码 $errorCode；1=广播过长，2=实例耗尽，4=内部错误，5=硬件不支持）"
                    pendingAdvertisingResult?.error("ADVERTISE_FAILED", message, null)
                    pendingAdvertisingResult = null
                    dataSink?.error("ADVERTISE_FAILED", message, null)
                    stopEverything()
                }
            }
        }
        advertiseCallback = callback
        mainHandler.postDelayed({
            if (advertiseCallback === callback && pendingAdvertisingResult != null) {
                pendingAdvertisingResult?.error("ADVERTISE_TIMEOUT", "蓝牙广播启动超时，请关闭再开启蓝牙后重试", null)
                pendingAdvertisingResult = null
                stopEverything()
            }
        }, 8_000)

        try {
            @Suppress("MissingPermission")
            advertiser.startAdvertising(
                buildAdvertiseSettings(),
                buildAdvertiseData(),
                buildScanResponse(),
                callback,
            )
        } catch (e: Exception) {
            Log.e(TAG, "startAdvertising 抛异常", e)
            pendingAdvertisingResult?.error("ADVERTISE_FAILED", "蓝牙广播开启失败：${e.message}", null)
            pendingAdvertisingResult = null
            stopEverything()
        }
    }

    private fun restartAdvertisingData() {
        val advertiser = adapter?.bluetoothLeAdvertiser ?: return
        val callback = advertiseCallback ?: return
        try {
            @Suppress("MissingPermission")
            advertiser.stopAdvertising(callback)
            @Suppress("MissingPermission")
            advertiser.startAdvertising(
                buildAdvertiseSettings(),
                buildAdvertiseData(),
                buildScanResponse(),
                callback,
            )
        } catch (e: Exception) {
            Log.w(TAG, "更新广播内容失败（人数显示可能不准）", e)
        }
    }

    private fun buildAdvertiseSettings(): AdvertiseSettings =
        AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true) // L2CAP 需要先建立 ACL 连接
            .setTimeout(0)
            .build()

    private fun buildAdvertiseData(): AdvertiseData =
        AdvertiseData.Builder()
            .setIncludeDeviceName(false) // 设备名会挤爆 31 字节预算
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            // 3 flags + 18 UUID + 7 manufacturer AD = 28 bytes <= 31.
            // PSM is available even when a vendor drops/delays the scan response.
            .addManufacturerData(MANUFACTURER_ID, byteArrayOf(
                (advertisedPsm ushr 8).toByte(), advertisedPsm.toByte(),
                advertisedMemberCount.toByte(),
            ))
            .build()

    private fun buildScanResponse(): AdvertiseData {
        val nameBytes = BleRoomAdvertisement.truncateUtf8(advertisedRoomName, ROOM_NAME_BUDGET)
        val payload = ByteArray(3 + nameBytes.size)
        payload[0] = (advertisedPsm ushr 8).toByte()
        payload[1] = advertisedPsm.toByte()
        payload[2] = advertisedMemberCount.toByte()
        nameBytes.copyInto(payload, 3)

        return AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addManufacturerData(MANUFACTURER_ID, payload)
            .build()
    }

    private fun acceptLoop(server: BluetoothServerSocket) {
        while (accepting.get()) {
            val socket = try {
                server.accept()
            } catch (e: IOException) {
                if (accepting.get()) Log.w(TAG, "accept 中断", e)
                break
            }

            if (peers.size >= MAX_PEERS) {
                Log.w(TAG, "蓝牙房已满，拒绝 ${socket.remoteDevice?.address}")
                try {
                    socket.close()
                } catch (_: IOException) {
                }
                continue
            }

            registerPeer(socket)
        }
    }

    /**
     * 关闭蓝牙会让系统销毁 BLE 广播和动态 PSM 对应的 L2CAP server socket。
     * 保留房主身份、房名和人数，等适配器回到 STATE_ON 后原地重建整套资源。
     */
    private fun suspendHostRadioForAdapterRestart() {
        if (!isHost || hostRadioRecoveryPending) return
        if (pendingAdvertisingResult != null) {
            pendingAdvertisingResult?.error("ADAPTER_DISABLED", "创建房间时蓝牙被关闭，请开启后重试", null)
            pendingAdvertisingResult = null
            stopEverything()
            return
        }
        hostRadioRecoveryPending = true
        hostRadioRecoveryGeneration++
        closeHostRadioResources("adapter_disabled")
        Log.w(TAG, "房主蓝牙已关闭；保留房间状态，蓝牙开启后将自动重建广播和 L2CAP 监听")
    }

    private fun scheduleHostRadioRecovery(delayMillis: Long, attempt: Int = 1) {
        val generation = hostRadioRecoveryGeneration
        mainHandler.postDelayed({
            if (generation != hostRadioRecoveryGeneration || !isHost || !hostRadioRecoveryPending) {
                return@postDelayed
            }
            recoverHostRadio(generation, attempt)
        }, delayMillis)
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun recoverHostRadio(generation: Int, attempt: Int) {
        if (generation != hostRadioRecoveryGeneration || !isHost || !hostRadioRecoveryPending) return
        val a = adapter
        if (a == null || a.state != BluetoothAdapter.STATE_ON) {
            scheduleHostRadioRecovery(delayMillis = 2_000, attempt = attempt)
            return
        }

        Log.i(TAG, "房主蓝牙恢复：第 $attempt 次重建 L2CAP 监听与 BLE 广播")
        closeHostRadioResources("host_radio_rebuild")
        val server = try {
            @Suppress("MissingPermission")
            a.listenUsingInsecureL2capChannel()
        } catch (e: Exception) {
            Log.w(TAG, "房主恢复时打开 L2CAP 监听失败", e)
            scheduleHostRadioRecovery(recoveryDelay(attempt), attempt + 1)
            return
        }

        serverSocket = server
        advertisedPsm = server.psm
        accepting.set(true)
        acceptThread = Thread({ acceptLoop(server) }, "dawn-ble-accept").apply { start() }

        val advertiser = a.bluetoothLeAdvertiser
        if (advertiser == null) {
            Log.w(TAG, "房主恢复时暂时拿不到 BLE advertiser")
            closeHostRadioResources("advertiser_unavailable")
            scheduleHostRadioRecovery(recoveryDelay(attempt), attempt + 1)
            return
        }

        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                mainHandler.post {
                    if (generation != hostRadioRecoveryGeneration || advertiseCallback !== this) return@post
                    hostRadioRecoveryPending = false
                    Log.i(TAG, "房主蓝牙房已恢复广播和监听（PSM=$advertisedPsm，第 $attempt 次成功）")
                }
            }

            override fun onStartFailure(errorCode: Int) {
                mainHandler.post {
                    if (generation != hostRadioRecoveryGeneration || advertiseCallback !== this) return@post
                    Log.w(TAG, "房主恢复广播失败：errorCode=$errorCode")
                    closeHostRadioResources("advertise_restart_failed")
                    scheduleHostRadioRecovery(recoveryDelay(attempt), attempt + 1)
                }
            }
        }
        advertiseCallback = callback
        try {
            @Suppress("MissingPermission")
            advertiser.startAdvertising(
                buildAdvertiseSettings(),
                buildAdvertiseData(),
                buildScanResponse(),
                callback,
            )
        } catch (e: Exception) {
            Log.w(TAG, "房主恢复时 startAdvertising 抛异常", e)
            closeHostRadioResources("advertise_restart_exception")
            scheduleHostRadioRecovery(recoveryDelay(attempt), attempt + 1)
            return
        }

        mainHandler.postDelayed({
            if (generation == hostRadioRecoveryGeneration &&
                hostRadioRecoveryPending && advertiseCallback === callback) {
                Log.w(TAG, "房主恢复广播等待 8 秒仍无回调，重新尝试")
                closeHostRadioResources("advertise_restart_timeout")
                scheduleHostRadioRecovery(recoveryDelay(attempt), attempt + 1)
            }
        }, 8_000)
    }

    private fun recoveryDelay(attempt: Int): Long = when {
        attempt <= 1 -> 1_000
        attempt == 2 -> 2_000
        attempt == 3 -> 4_000
        attempt == 4 -> 8_000
        else -> 15_000
    }

    /** 仅释放房主的射频资源，不清除房间身份与用于恢复的广播内容。 */
    private fun closeHostRadioResources(reason: String) {
        accepting.set(false)
        advertiseCallback?.let { callback ->
            try {
                @Suppress("MissingPermission")
                adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
            } catch (e: Exception) {
                Log.d(TAG, "停止房主广播时被忽略的异常：$e")
            }
        }
        advertiseCallback = null
        try {
            serverSocket?.close()
        } catch (e: IOException) {
            Log.d(TAG, "关闭房主 L2CAP 监听时被忽略的异常：$e")
        }
        serverSocket = null
        acceptThread = null
        for (link in peers.values) link.close(reason)
        peers.clear()
        hostLink = null
        advertisedPsm = 0
    }

    // ---------------------------------------------------------- 客户端：扫描

    private fun startScan(): Boolean {
        val scanner = adapter?.bluetoothLeScanner ?: run {
            Log.e(TAG, "拿不到 BLE 扫描器")
            return false
        }
        if (scanning) return true

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setReportDelay(0)
            .build()

        return try {
            @Suppress("MissingPermission")
            scanner.startScan(listOf(filter), settings, scanCallback)
            scanning = true
            Log.i(TAG, "开始扫描蓝牙房")
            true
        } catch (e: Exception) {
            Log.e(TAG, "启动扫描失败", e)
            false
        }
    }

    private fun stopScan() {
        if (!scanning) return
        scanning = false
        try {
            @Suppress("MissingPermission")
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: Exception) {
            Log.w(TAG, "停止扫描失败", e)
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            val record = result?.scanRecord ?: return
            val room = BleRoomAdvertisement.parse(record.bytes, MANUFACTURER_ID) ?: return

            val device = result.device ?: return
            val info = mapOf(
                "address" to device.address,
                "roomName" to room.name,
                "psm" to room.psm,
                "memberCount" to room.members,
                "rssi" to result.rssi,
            )
            mainHandler.post { scanSink?.success(info) }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE 扫描失败，errorCode=$errorCode")
            mainHandler.post {
                scanSink?.error("SCAN_FAILED", "蓝牙扫描失败（错误码 $errorCode；2=注册失败，5=硬件资源不足，6=扫描过频）。请稍等 30 秒再试", null)
            }
            mainHandler.post { stopScan() }
        }
    }

    private fun connectL2cap(address: String, psm: Int, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "蓝牙对讲需要 Android 10 或更新版本", null)
            return
        }
        val a = adapter ?: run {
            result.error("UNSUPPORTED", "没有蓝牙适配器", null)
            return
        }
        isHost = false
        stopScan()
        Log.i(TAG, "开始连接蓝牙房：$address，psm=$psm")

        val generation = ++connectionGeneration
        val completed = AtomicBoolean(false)
        val socket = try {
            a.getRemoteDevice(address).createInsecureL2capChannel(psm)
        } catch (e: Exception) {
            Log.w(TAG, "创建蓝牙通道失败：$address, psm=$psm", e)
            result.error("CONNECT_FAILED", "无法创建蓝牙通道：${e.message}", null)
            return
        }
        pendingConnectSocket = socket
        mainHandler.postDelayed({
            if (completed.compareAndSet(false, true)) {
                Log.w(TAG, "连接蓝牙房超时：$address, psm=$psm")
                try { socket.close() } catch (_: IOException) {}
                if (pendingConnectSocket === socket) pendingConnectSocket = null
                result.error("CONNECT_TIMEOUT", "连接蓝牙房超时，请重新扫描后重试", null)
            }
        }, 12_000)
        Thread({
            try {
                socket.connect()
                mainHandler.post {
                    if (generation != connectionGeneration) {
                        try { socket.close() } catch (_: IOException) {}
                        if (completed.compareAndSet(false, true)) result.error("CANCELLED", "连接已取消", null)
                    } else if (completed.compareAndSet(false, true)) {
                        pendingConnectSocket = null
                        hostLink = registerPeer(socket)
                        result.success(true)
                    } else {
                        try { socket.close() } catch (_: IOException) {}
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "连接蓝牙房主失败：$address, psm=$psm", e)
                try { socket.close() } catch (_: IOException) {}
                mainHandler.post {
                    if (pendingConnectSocket === socket) pendingConnectSocket = null
                    if (completed.compareAndSet(false, true)) {
                        result.error("CONNECT_FAILED", "连接蓝牙房主失败，请重新扫描后重试", null)
                    }
                }
            }
        }, "dawnmesh-ble-connect").start()
    }

    // ------------------------------------------------------------ 链路与收发

    private inner class PeerLink(val socket: BluetoothSocket, val address: String) {
        val alive = AtomicBoolean(true)
        val disconnectReported = AtomicBoolean(false)
        val openedAt = SystemClock.elapsedRealtime()
        val rxFrames = AtomicLong(0)
        val rxBytes = AtomicLong(0)
        val txFrames = AtomicLong(0)
        val txBytes = AtomicLong(0)
        val txWrites = AtomicLong(0)
        @Volatile var lastRxAt = openedAt
        @Volatile var lastTxAt = openedAt
        @Volatile var requestedCloseReason: String? = null
        private val diagnosticsRunnable = object : Runnable {
            override fun run() {
                if (!alive.get()) return
                Log.d(TAG, "蓝牙链路状态：$address；${diagnostics()}")
                mainHandler.postDelayed(this, 10_000)
            }
        }
        private val writer = BoundedFrameWriter(
            coalesceMillis = 25,
            coalesceMillisProvider = { BluetoothAudioCoexistence.l2capCoalesceMillis() },
            dropStaleRealtimeProvider = { BluetoothAudioCoexistence.dropStaleRealtime() },
            maxRealtimeAgeMillisProvider = { BluetoothAudioCoexistence.maxRealtimeAgeMillis() },
            maxBatchBytes = 4_096,
            write = { data ->
                socket.outputStream.write(data)
                socket.outputStream.flush()
                txWrites.incrementAndGet()
                txFrames.addAndGet(countProtocolFrames(data).toLong())
                txBytes.addAndGet(data.size.toLong())
                lastTxAt = SystemClock.elapsedRealtime()
            },
            closeTransport = {
                alive.set(false)
                try { socket.close() } catch (_: IOException) {}
            },
            onFailure = { error ->
                removePeer(this@PeerLink, "write_failure", error)
            },
        )

        fun write(data: ByteArray, realtime: Boolean = false): Boolean = writer.send(data, realtime)
        fun flush() = writer.flush()
        fun startDiagnostics() {
            mainHandler.postDelayed(diagnosticsRunnable, 10_000)
        }
        fun recordRx(bytes: Int) {
            rxFrames.incrementAndGet()
            rxBytes.addAndGet(bytes.toLong())
            lastRxAt = SystemClock.elapsedRealtime()
        }
        fun diagnostics(now: Long = SystemClock.elapsedRealtime()): String =
            "ageMs=${now - openedAt},rxFrames=${rxFrames.get()},rxBytes=${rxBytes.get()}," +
                "txFrames=${txFrames.get()},txWrites=${txWrites.get()},txBytes=${txBytes.get()}," +
                "coexistence=${BluetoothAudioCoexistence.isActive()}," +
                "txDroppedRealtime=${writer.droppedRealtimeFrames()}," +
                "rxIdleMs=${now - lastRxAt},txIdleMs=${now - lastTxAt}"
        fun close(reason: String = "local_stop") {
            requestedCloseReason = reason
            mainHandler.removeCallbacks(diagnosticsRunnable)
            writer.close()
        }
    }

    /** 返回合并写入中完整协议帧的数量，仅用于诊断计数。 */
    private fun countProtocolFrames(data: ByteArray): Int {
        var offset = 0
        var count = 0
        while (offset + FRAME_HEADER_SIZE <= data.size) {
            val payloadLength =
                ((data[offset + 4].toInt() and 0xFF) shl 8) or
                    (data[offset + 5].toInt() and 0xFF)
            val frameLength = FRAME_HEADER_SIZE + payloadLength
            if (payloadLength > MAX_PAYLOAD || offset + frameLength > data.size) break
            count++
            offset += frameLength
        }
        return count.coerceAtLeast(1)
    }

    private fun registerPeer(socket: BluetoothSocket): PeerLink {
        val address = socket.remoteDevice?.address ?: "unknown"
        val link = PeerLink(socket, address)
        peers[address] = link
        Log.i(TAG, "蓝牙链路建立：$address，maxTx=${socket.maxTransmitPacketSize}，maxRx=${socket.maxReceivePacketSize}")
        link.startDiagnostics()

        Thread({ readLoop(link) }, "dawn-ble-read-$address").start()
        return link
    }

    /**
     * L2CAP CoC 是流式的，一次 read 可能只拿到半个帧。
     * 这里按 6 字节帧头里的长度字段补齐成整帧再上抛，Dart 侧就只需 Frame.decode。
     */
    private fun readLoop(link: PeerLink) {
        val input = try {
            link.socket.inputStream
        } catch (e: IOException) {
            Log.e(TAG, "拿不到 ${link.address} 的输入流", e)
            removePeer(link, "input_stream_error", e)
            return
        }

        val header = ByteArray(FRAME_HEADER_SIZE)
        var reason = "remote_eof"
        var failure: Throwable? = null
        try {
            while (link.alive.get()) {
                readFully(input, header, FRAME_HEADER_SIZE)

                val payloadLength =
                    ((header[4].toInt() and 0xFF) shl 8) or (header[5].toInt() and 0xFF)
                if (payloadLength > MAX_PAYLOAD) {
                    reason = "frame_desync"
                    Log.e(TAG, "${link.address} 帧长度 $payloadLength 越界，判定为流错位并断开")
                    break
                }

                val full = ByteArray(FRAME_HEADER_SIZE + payloadLength)
                header.copyInto(full, 0)
                if (payloadLength > 0) {
                    val payload = ByteArray(payloadLength)
                    readFully(input, payload, payloadLength)
                    payload.copyInto(full, FRAME_HEADER_SIZE)
                }
                link.recordRx(full.size)

                // Host-only roster, handover, snapshot and chat-history commands
                // must never be injected by an incoming client link.
                val type = header[0].toInt() and 0xFF
                if (isHost && type in listOf(0x03, 0x07, 0x08, 0x0d)) continue

                // 房主负责把一个成员的帧转给其他成员（星型拓扑，与 WiFi 房一致）。
                if (isHost) sendData(full, excludeAddress = link.address)

                val event = mapOf<String, Any>(
                    "type" to "frame",
                    "data" to full,
                    "peerAddress" to link.address,
                )
                mainHandler.post { dataSink?.success(event) }
            }
        } catch (e: EOFException) {
            // InputStream EOF 只表示 L2CAP 流已结束，不能单凭它断定是远端主动
            // 关闭。本机关闭蓝牙时 Android 也会以 EOF 唤醒阻塞的 read。
            reason = if (adapter?.state == BluetoothAdapter.STATE_ON) "stream_eof" else "adapter_disabled"
            failure = e
        } catch (e: IOException) {
            reason = "read_error"
            failure = e
        } catch (e: Exception) {
            reason = "read_failure"
            failure = e
        } finally {
            link.requestedCloseReason?.let { reason = it }
            removePeer(link, reason, failure)
        }
    }

    @Throws(IOException::class)
    private fun readFully(input: java.io.InputStream, dst: ByteArray, length: Int) {
        var offset = 0
        while (offset < length) {
            val read = input.read(dst, offset, length - offset)
            if (read < 0) throw EOFException("stream ended at $offset/$length bytes")
            offset += read
        }
    }

    private fun sendData(
        data: ByteArray,
        excludeAddress: String?,
        realtime: Boolean = false,
    ): Boolean {
        if (peers.isEmpty()) return false
        var anySent = false

        for ((address, link) in peers) {
            if (address == excludeAddress) continue
            if (!link.alive.get()) continue
            try {
                if (link.write(data, realtime)) anySent = true
            } catch (e: IOException) {
                Log.w(TAG, "向 $address 发送失败，断开该链路", e)
                removePeer(link, "write_error", e)
            }
        }
        return anySent
    }

    private fun removePeer(link: PeerLink, reason: String, error: Throwable? = null) {
        if (!link.disconnectReported.compareAndSet(false, true)) return
        val wasHostLink = hostLink === link
        peers.remove(link.address, link)
        link.close(reason)
        if (hostLink === link) hostLink = null
        val detail = error?.let { "${it.javaClass.simpleName}: ${it.message.orEmpty()}" }
        val adapterState = adapter?.state ?: BluetoothAdapter.ERROR
        val message = "蓝牙链路断开：${link.address}；reason=$reason；adapterState=$adapterState；${link.diagnostics()}"
        if (error == null || reason == "local_stop") Log.i(TAG, message)
        else Log.w(TAG, message, error)
        if (wasHostLink && reason != "local_stop") {
            val event = mapOf(
                "type" to "disconnected",
                "reason" to reason,
                "detail" to detail,
                "peerAddress" to link.address,
                "adapterState" to adapterState,
                "diagnostics" to link.diagnostics(),
            )
            mainHandler.post { dataSink?.success(event) }
        }
    }

    // ---------------------------------------------------------------- 收尾

    private fun stopEverything() {
        hostRadioRecoveryGeneration++
        hostRadioRecoveryPending = false
        connectionGeneration++
        try { pendingConnectSocket?.close() } catch (_: IOException) {}
        pendingConnectSocket = null
        pendingAdvertisingResult?.error("CANCELLED", "蓝牙房创建已取消", null)
        pendingAdvertisingResult = null
        stopScan()

        accepting.set(false)
        advertiseCallback?.let { callback ->
            try {
                @Suppress("MissingPermission")
                adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
            } catch (e: Exception) {
                Log.d(TAG, "停止广播时被忽略的异常：$e")
            }
        }
        advertiseCallback = null

        try {
            serverSocket?.close()
        } catch (e: IOException) {
            Log.d(TAG, "关闭 L2CAP 监听时被忽略的异常：$e")
        }
        serverSocket = null
        acceptThread = null

        for (link in peers.values) link.close("local_stop")
        peers.clear()
        hostLink = null

        isHost = false
        advertisedPsm = 0
    }
}
