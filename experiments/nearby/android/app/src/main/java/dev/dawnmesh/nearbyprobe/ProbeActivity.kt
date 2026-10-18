package dev.dawnmesh.nearbyprobe

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
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

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 32, 24, 16) }
        status = TextView(this).apply { text = getString(R.string.intro) }
        diagnostics = TextView(this).apply { setTextIsSelectable(true); textSize = 12f }
        disruptive = CheckBox(this).apply { text = getString(R.string.disruptive) }
        bleAdvertising = CheckBox(this).apply { text = getString(R.string.ble_advertising); isChecked = true }
        endpoints = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        layout.addView(TextView(this).apply { text = getString(R.string.app_title, "0.1.1"); textSize = 22f })
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
        layout.addView(endpoints); layout.addView(diagnostics)
        setContentView(ScrollView(this).apply { addView(layout) })
        note("${Build.MANUFACTURER} ${Build.MODEL}; Android ${Build.VERSION.RELEASE}")
    }
    private var currentEpoch = 0L
    private fun live(epoch: Long) = active && epochs.accepts(epoch)
    private fun button(label: String, action: () -> Unit) { layout.addView(Button(this).apply { text = label; setOnClickListener { action() } }) }
    private fun note(message: String) {
        if (notes.size >= 12) notes.removeFirst()
        notes.addLast(message.take(220)); diagnostics.text = notes.joinToString("\n")
    }
    private fun failure(operation: String, error: Exception) {
        val detail = if (error is ApiException) "${error.statusCode} ${ConnectionsStatusCodes.getStatusCodeString(error.statusCode)}" else error.javaClass.simpleName
        status.text = getString(R.string.operation_error, operation, detail)
        note("$operation: $detail") // No pairing codes, credentials or endpoint IDs.
    }
    private fun connectionType() = if (disruptive.isChecked) ConnectionType.DISRUPTIVE else ConnectionType.BALANCED
    private fun restart(advertise: Boolean) {
        stop()
        currentEpoch = epochs.advance(); val epoch = currentEpoch
        active = true; status.text = getString(R.string.resetting)
        // The public Android stop APIs are asynchronous void calls. Serialize
        // starts, allow teardown to settle, and reject all prior callbacks.
        main.postDelayed({
            if (!live(epoch)) return@postDelayed
            if (advertise) {
                val options = AdvertisingOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT)
                    .setLowPower(bleAdvertising.isChecked).setConnectionType(connectionType()).build()
                client.startAdvertising("Android Probe", SERVICE, lifecycle(epoch), options)
                    .addOnSuccessListener { if (live(epoch)) { status.text = getString(R.string.advertising); note("Advertising; BLE-only=${bleAdvertising.isChecked}") } }
                    .addOnFailureListener { if (live(epoch)) failure("发布", it) }
            } else {
                client.startDiscovery(SERVICE, discovery(epoch), DiscoveryOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).build())
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
                        ConnectionOptions.Builder().setLowPower(false).setConnectionType(connectionType()).build())
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
                remote = id; client.stopDiscovery(); client.stopAdvertising()
                status.text = getString(R.string.connected); note("Connected; scan/advertise stopped")
            } else {
                status.text = getString(R.string.connection_status, resolution.status.statusCode)
                note("Connection: ${resolution.status.statusCode} ${ConnectionsStatusCodes.getStatusCodeString(resolution.status.statusCode)}")
            }
        }
        override fun onBandwidthChanged(id: String, info: BandwidthInfo) {
            if (live(epoch) && remote == id) note("SDK bandwidth quality=${info.quality}; quality is not a medium identifier")
        }
        override fun onDisconnected(id: String) {
            if (!live(epoch)) return
            pending.remove(id); clearPairDialog(id)
            if (remote == id) { remote = null; cancelProbe(); status.text = getString(R.string.disconnected); note("Disconnected") }
        }
    }
    private fun payloads(epoch: Long) = object : PayloadCallback() {
        override fun onPayloadReceived(id: String, payload: Payload) {
            if (!live(epoch) || id != remote) return
            val bytes = payload.asBytes()?.copyOf() ?: run { client.cancelPayload(payload.id); payload.close(); return }
            if (bytes.size != 1035 || !bytes.copyOfRange(0, 4).contentEquals(byteArrayOf(68, 77, 80, 49))) return
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
                    note("Payload status=${update.status}; active request=$relevant")
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
        active = false; currentEpoch = epochs.advance(); permissionAction = null
        pairDialog?.dismiss(); pairDialog = null; pairEndpoint = null
        cancelProbe(); pending.clear(); remote = null; found.clear(); endpoints.removeAllViews()
        client.stopDiscovery(); client.stopAdvertising(); client.stopAllEndpoints()
    }
    override fun onDestroy() { stop(); super.onDestroy() }
}
