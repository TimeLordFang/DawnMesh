package dev.dawnmesh.nearbyprobe

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.widget.*
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import java.nio.ByteBuffer
import java.security.SecureRandom

/** Isolated transport experiment: never handles DawnMesh room keys or media. */
class ProbeActivity : Activity() {
    companion object { const val SERVICE = "dev.dawnmesh.nearby.probe.v1" }
    private val client by lazy { Nearby.getConnectionsClient(this) }
    private val main = Handler(Looper.getMainLooper())
    private val epochs = ProbeEpoch()
    private val ledger = ProbeLedger()
    private lateinit var layout: LinearLayout
    private lateinit var status: TextView
    private lateinit var diagnostics: TextView
    private lateinit var endpoints: LinearLayout
    private lateinit var disruptive: CheckBox
    private lateinit var bleAdvertising: CheckBox
    private var remote: String? = null
    private var permissionAction: (() -> Unit)? = null
    private var pairDialog: AlertDialog? = null
    private var pairEndpoint: String? = null
    private var active = false
    private val pending = mutableSetOf<String>()
    private val found = mutableSetOf<String>()
    private val notes = ArrayDeque<String>()
    private var chunk = -1
    private var runToken = 0
    private var started = 0L
    private var sentAt = 0L
    private var maximumRtt = 0L
    private var watchdog: Runnable? = null
    private val appStarted = SystemClock.elapsedRealtime()
    private var connectedAt = 0L
    private var lastDataAt = 0L
    private var lastQuality: Int? = null
    private var sessionLowPower = true
    private var sessionConnectionType = ConnectionType.NON_DISRUPTIVE

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 32, 24, 16) }
        status = TextView(this).apply { text = getString(R.string.intro) }
        diagnostics = TextView(this).apply { setTextIsSelectable(true); textSize = 12f }
        disruptive = CheckBox(this).apply { text = getString(R.string.disruptive) }
        bleAdvertising = CheckBox(this).apply { text = getString(R.string.ble_advertising); isChecked = true }
        disruptive.isEnabled = false
        bleAdvertising.setOnCheckedChangeListener { _, checked ->
            if (checked) disruptive.isChecked = false
            disruptive.isEnabled = !active && !checked
        }
        endpoints = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        layout.addView(TextView(this).apply { text = getString(R.string.app_title, "0.1.2"); textSize = 22f })
        layout.addView(status); layout.addView(disruptive); layout.addView(bleAdvertising)
        button(getString(R.string.advertise)) { permitted { restart(true) } }
        button(getString(R.string.discover)) { permitted { restart(false) } }
        button(getString(R.string.probe)) {
            if (remote == null || chunk >= 0) return@button
            ledger.clear(); chunk = 0; runToken = SecureRandom().nextInt()
            started = SystemClock.elapsedRealtime(); maximumRtt = 0
            next(currentEpoch)
        }
        button(getString(R.string.stop)) { stop(); status.text = getString(R.string.stopped) }
        button(getString(R.string.copy_diagnostics)) {
            getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Nearby Probe", "Nearby Probe 0.1.2\n" + notes.joinToString("\n")))
        }
        layout.addView(endpoints); layout.addView(diagnostics)
        setContentView(ScrollView(this).apply { addView(layout) })
        note("${Build.MANUFACTURER} ${Build.MODEL}; Android ${Build.VERSION.RELEASE}")
    }
    private var currentEpoch = 0L
    private fun live(epoch: Long) = active && epochs.accepts(epoch)
    private fun button(label: String, action: () -> Unit) { layout.addView(Button(this).apply { text = label; setOnClickListener { action() } }) }
    private fun note(message: String, severity: String = "信息") {
        if (notes.size >= 60) notes.removeFirst()
        notes.addLast("[$severity] +${(SystemClock.elapsedRealtime() - appStarted) / 1000}s ${message.take(220)}")
        diagnostics.text = notes.joinToString("\n")
    }
    private fun failure(operation: String, error: Exception) {
        val detail = if (error is ApiException) "${error.statusCode} ${ConnectionsStatusCodes.getStatusCodeString(error.statusCode)}" else error.javaClass.simpleName
        status.text = getString(R.string.operation_error, operation, detail)
        note("$operation: $detail", "错误") // No pairing codes, credentials or endpoint IDs.
    }
    private fun connectionType() = if (!bleAdvertising.isChecked && disruptive.isChecked) ConnectionType.DISRUPTIVE else ConnectionType.NON_DISRUPTIVE
    private fun restart(advertise: Boolean) {
        stop()
        currentEpoch = epochs.advance(); val epoch = currentEpoch
        sessionLowPower = bleAdvertising.isChecked; sessionConnectionType = connectionType()
        bleAdvertising.isEnabled = false; disruptive.isEnabled = false
        active = true; status.text = getString(R.string.resetting)
        note("开始${if (advertise) "发布" else "发现"}；lowPower=$sessionLowPower；connectionType=$sessionConnectionType")
        // The public Android stop APIs are asynchronous void calls. Serialize
        // starts, allow teardown to settle, and reject all prior callbacks.
        main.postDelayed({
            if (!live(epoch)) return@postDelayed
            if (advertise) {
                val options = AdvertisingOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT)
                    .setLowPower(sessionLowPower).setConnectionType(sessionConnectionType).build()
                client.startAdvertising("Android Probe", SERVICE, lifecycle(epoch), options)
                    .addOnSuccessListener { if (live(epoch)) { status.text = getString(R.string.advertising); note("发布已启动") } }
                    .addOnFailureListener { if (live(epoch)) failure("发布", it) }
            } else {
                client.startDiscovery(SERVICE, discovery(epoch), DiscoveryOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).setLowPower(sessionLowPower).build())
                    .addOnSuccessListener { if (live(epoch)) status.text = getString(R.string.discovering) }
                    .addOnFailureListener { if (live(epoch)) failure("发现", it) }
            }
        }, 500)
    }
    private fun permitted(action: () -> Unit) {
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this) != 0) { status.text = getString(R.string.no_gms); return }
        val wanted = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) wanted += listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
        if (Build.VERSION.SDK_INT >= 33) wanted += Manifest.permission.NEARBY_WIFI_DEVICES
        else wanted += listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
        if (Build.VERSION.SDK_INT >= 37) wanted += Manifest.permission.ACCESS_LOCAL_NETWORK
        val missing = wanted.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) action() else { permissionAction = action; requestPermissions(missing.toTypedArray(), 901) }
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (code != 901) return
        val action = permissionAction; permissionAction = null
        if (results.isNotEmpty() && results.all { it == PackageManager.PERMISSION_GRANTED }) action?.invoke() else status.text = getString(R.string.denied)
    }
    private fun discovery(epoch: Long) = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(id: String, info: DiscoveredEndpointInfo) {
            if (!live(epoch) || info.serviceId != SERVICE || found.size >= 32 || !found.add(id)) return
            endpoints.addView(Button(this@ProbeActivity).apply {
                tag = id; text = info.endpointName.take(48)
                setOnClickListener {
                    if (!live(epoch) || remote != null || pending.isNotEmpty()) return@setOnClickListener
                    pending.add(id)
                    client.requestConnection("Android Probe", id, lifecycle(epoch),
                        ConnectionOptions.Builder().setLowPower(sessionLowPower).setConnectionType(sessionConnectionType).build())
                        .addOnFailureListener { if (live(epoch) && pending.remove(id)) failure("请求连接", it) }
                }
            })
        }
        override fun onEndpointLost(id: String) {
            if (live(epoch)) { found.remove(id); endpoints.findViewWithTag<Button>(id)?.let(endpoints::removeView) }
        }
    }
    private fun lifecycle(epoch: Long) = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(id: String, info: ConnectionInfo) {
            if (!live(epoch)) return
            if (remote != null || pairDialog != null || (pending.isNotEmpty() && id !in pending)) { client.rejectConnection(id); return }
            pending.add(id); pairEndpoint = id
            pairDialog = AlertDialog.Builder(this@ProbeActivity).setTitle(getString(R.string.pair_title))
                .setMessage(getString(R.string.pair_message, info.endpointName.take(48), info.authenticationToken))
                .setPositiveButton(getString(R.string.accept)) { _, _ ->
                    pairDialog = null; pairEndpoint = null
                    if (live(epoch)) client.acceptConnection(id, payloads(epoch)).addOnFailureListener {
                        if (live(epoch)) { pending.remove(id); client.disconnectFromEndpoint(id); failure("确认配对", it) }
                    }
                }
                .setNegativeButton(getString(R.string.reject)) { _, _ -> if (live(epoch)) client.rejectConnection(id); pending.remove(id); pairDialog = null; pairEndpoint = null }
                .setOnCancelListener { if (live(epoch)) client.rejectConnection(id); pending.remove(id); pairDialog = null; pairEndpoint = null }.create()
            pairDialog?.show()
        }
        override fun onConnectionResult(id: String, resolution: ConnectionResolution) {
            if (!live(epoch)) return
            if (!pending.remove(id)) { if (resolution.status.isSuccess && remote != id) client.disconnectFromEndpoint(id); return }
            clearPairDialog(id)
            if (resolution.status.isSuccess) {
                remote = id; connectedAt = SystemClock.elapsedRealtime(); lastDataAt = connectedAt; lastQuality = null
                client.stopDiscovery()
                // Keep the publisher/listening service alive until explicit
                // teardown. The Swift SDK removes BLE services when stopped.
                status.text = getString(R.string.connected); note("已连接；停止发现，保留发布服务")
            } else {
                status.text = getString(R.string.connection_status, resolution.status.statusCode)
                note("Connection: ${resolution.status.statusCode} ${ConnectionsStatusCodes.getStatusCodeString(resolution.status.statusCode)}")
            }
        }
        override fun onBandwidthChanged(id: String, info: BandwidthInfo) {
            if (live(epoch) && remote == id) { lastQuality = info.quality; note("SDK 带宽质量等级=${info.quality}（不是错误，也不表示 Wi-Fi）") }
        }
        override fun onDisconnected(id: String) {
            if (!live(epoch)) return
            pending.remove(id); clearPairDialog(id)
            if (remote == id) {
                val now = SystemClock.elapsedRealtime()
                note("SDK连接断开；连接${now - connectedAt}ms；数据空闲${now - lastDataAt}ms；quality=$lastQuality；原因未由SDK提供", "事件")
                stop(); status.text = getString(R.string.disconnected)
            }
        }
    }
    private fun payloads(epoch: Long) = object : PayloadCallback() {
        override fun onPayloadReceived(id: String, payload: Payload) {
            if (!live(epoch) || id != remote) return
            val bytes = payload.asBytes()?.copyOf() ?: run { client.cancelPayload(payload.id); payload.close(); return }
            if (bytes.size != 1035 || !bytes.copyOfRange(0, 4).contentEquals(byteArrayOf(68, 77, 80, 49))) return
            lastDataAt = SystemClock.elapsedRealtime()
            val index = ((bytes[5].toInt() and 255) shl 8) or (bytes[6].toInt() and 255)
            if (index !in 0..31) return
            if (bytes[4] == 1.toByte()) {
                bytes[4] = 2
                client.sendPayload(id, Payload.fromBytes(bytes)).addOnFailureListener { if (live(epoch)) note("Echo send: ${errorCode(it)}") }
                return
            }
            if (chunk < 0 || bytes[4] != 2.toByte() || index != chunk || ByteBuffer.wrap(bytes, 7, 4).int != runToken) return
            if ((11 until bytes.size).any { (bytes[it].toInt() and 255) != ((it - 11 + chunk) % 251) }) { cancelProbe(); status.text = getString(R.string.integrity_error); return }
            ledger.acknowledged(runToken, chunk)
            maximumRtt = maxOf(maximumRtt, SystemClock.elapsedRealtime() - sentAt)
            watchdog?.let(main::removeCallbacks); watchdog = null; chunk++
            if (chunk == 32) {
                val elapsed = maxOf(1L, SystemClock.elapsedRealtime() - started)
                status.text = getString(R.string.probe_result, elapsed, maximumRtt, 64.0 * 1000 / elapsed)
                note("Probe passed: ${elapsed}ms maxRTT=${maximumRtt}ms")
                cancelProbe()
            } else next(epoch)
        }
        override fun onPayloadTransferUpdate(id: String, update: PayloadTransferUpdate) {
            if (!live(epoch) || id != remote) return
            when (update.status) {
                PayloadTransferUpdate.Status.SUCCESS -> ledger.settled(update.payloadId)
                PayloadTransferUpdate.Status.FAILURE, PayloadTransferUpdate.Status.CANCELED -> {
                    val relevant = chunk >= 0 && ledger.failed(update.payloadId, runToken, chunk)
                    note("Payload status=${update.status}; active request=$relevant; seq=$chunk", if (relevant) "错误" else "信息")
                    if (relevant) { cancelProbe(); status.text = getString(R.string.transfer_error) }
                }
            }
        }
    }
    private fun errorCode(error: Exception) = if (error is ApiException) "${error.statusCode} ${ConnectionsStatusCodes.getStatusCodeString(error.statusCode)}" else error.javaClass.simpleName
    private fun next(epoch: Long) {
        val id = remote ?: return
        if (!live(epoch) || chunk < 0) return
        val bytes = ByteArray(1035)
        bytes[0] = 68; bytes[1] = 77; bytes[2] = 80; bytes[3] = 49; bytes[4] = 1
        bytes[5] = (chunk shr 8).toByte(); bytes[6] = chunk.toByte()
        ByteBuffer.wrap(bytes, 7, 4).putInt(runToken)
        for (i in 11 until bytes.size) bytes[i] = ((i - 11 + chunk) % 251).toByte()
        sentAt = SystemClock.elapsedRealtime()
        val run = runToken; val sequence = chunk
        watchdog = Runnable {
            if (live(epoch) && runToken == run && chunk == sequence) { cancelProbe(); status.text = getString(R.string.timeout) }
        }.also { main.postDelayed(it, 10000) }
        val payload = Payload.fromBytes(bytes); ledger.sent(payload.id, run, sequence)
        client.sendPayload(id, payload).addOnFailureListener {
            if (live(epoch) && chunk >= 0 && ledger.failed(payload.id, runToken, chunk)) { cancelProbe(); failure("发送", it) }
        }
    }
    private fun cancelProbe() { watchdog?.let(main::removeCallbacks); watchdog = null; chunk = -1; ledger.clear() }
    private fun clearPairDialog(id: String) {
        if (pairEndpoint == id) { pairDialog?.dismiss(); pairDialog = null; pairEndpoint = null }
    }
    private fun stop() {
        if (active) note("本机清理会话与缓存端点")
        active = false; currentEpoch = epochs.advance(); permissionAction = null
        bleAdvertising.isEnabled = true; disruptive.isEnabled = !bleAdvertising.isChecked
        pairDialog?.dismiss(); pairDialog = null; pairEndpoint = null
        cancelProbe(); pending.clear(); remote = null; found.clear(); endpoints.removeAllViews()
        client.stopDiscovery(); client.stopAdvertising(); client.stopAllEndpoints()
    }
    override fun onDestroy() { stop(); super.onDestroy() }
}
