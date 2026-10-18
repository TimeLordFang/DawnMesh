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
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import java.nio.ByteBuffer
import java.security.SecureRandom

/** Isolated transport experiment: never handles DawnMesh room keys or media. */
class ProbeActivity : Activity() {
    companion object { const val SERVICE = "dev.dawnmesh.nearby.probe.v1" }
    private val client by lazy { Nearby.getConnectionsClient(this) }
    private val main = Handler(Looper.getMainLooper())
    private lateinit var layout: LinearLayout
    private lateinit var status: TextView
    private lateinit var endpoints: LinearLayout
    private lateinit var disruptive: CheckBox
    private var remote: String? = null
    private var permissionAction: (() -> Unit)? = null
    private var pairDialog: AlertDialog? = null
    private var pairEndpoint: String? = null
    private var active = false
    private val pending = mutableSetOf<String>()
    private var chunk = -1
    private var runToken = 0
    private var started = 0L
    private var sentAt = 0L
    private var maximumRtt = 0L
    private var watchdog: Runnable? = null
    private val found = mutableSetOf<String>()

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 32, 24, 16) }
        status = TextView(this).apply { text = getString(R.string.intro) }
        disruptive = CheckBox(this).apply { text = getString(R.string.disruptive) }
        endpoints = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        layout.addView(TextView(this).apply { text = getString(R.string.app_name); textSize = 22f })
        layout.addView(status); layout.addView(disruptive)
        button(getString(R.string.advertise)) { permitted {
            stop(); active = true
            client.startAdvertising("Android Probe", SERVICE, lifecycle,
                AdvertisingOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).setDisruptiveUpgrade(disruptive.isChecked).build())
                .addOnSuccessListener { if (active) status.text = getString(R.string.advertising) }.addOnFailureListener { if (active) status.text = getString(R.string.advertise_error, it.javaClass.simpleName) }
        } }
        button(getString(R.string.discover)) { permitted {
            stop(); active = true
            client.startDiscovery(SERVICE, discovery, DiscoveryOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).build())
                .addOnSuccessListener { if (active) status.text = getString(R.string.discovering) }.addOnFailureListener { if (active) status.text = getString(R.string.discovery_error, it.javaClass.simpleName) }
        } }
        button(getString(R.string.probe)) {
            if (remote == null || chunk >= 0) return@button
            chunk = 0; runToken = SecureRandom().nextInt(); started = SystemClock.elapsedRealtime(); maximumRtt = 0; next()
        }
        button(getString(R.string.stop)) { stop(); status.text = getString(R.string.stopped) }
        layout.addView(endpoints)
        setContentView(ScrollView(this).apply { addView(layout) })
    }
    private fun button(label: String, action: () -> Unit) { layout.addView(Button(this).apply { text = label; setOnClickListener { action() } }) }
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
    private val discovery = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(id: String, info: DiscoveredEndpointInfo) {
            if (!active || info.serviceId != SERVICE || found.size >= 32 || !found.add(id)) return
            endpoints.addView(Button(this@ProbeActivity).apply {
                tag = id; text = info.endpointName.take(48)
                setOnClickListener {
                    if (!active || remote != null || pending.isNotEmpty()) return@setOnClickListener
                    pending.add(id)
                    client.requestConnection("Android Probe", id, lifecycle,
                        ConnectionOptions.Builder().setDisruptiveUpgrade(disruptive.isChecked).build())
                        .addOnFailureListener { if (pending.remove(id) && active) status.text = getString(R.string.connection_error, it.javaClass.simpleName) }
                }
            })
        }
        override fun onEndpointLost(id: String) { found.remove(id); endpoints.findViewWithTag<Button>(id)?.let(endpoints::removeView) }
    }
    private val lifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(id: String, info: ConnectionInfo) {
            if (!active || remote != null || pairDialog != null || (pending.isNotEmpty() && id !in pending)) { client.rejectConnection(id); return }
            pending.add(id); pairEndpoint = id
            pairDialog = AlertDialog.Builder(this@ProbeActivity).setTitle(getString(R.string.pair_title))
                .setMessage(getString(R.string.pair_message, info.endpointName.take(48), info.authenticationToken))
                .setPositiveButton(getString(R.string.accept)) { _, _ -> client.acceptConnection(id, payloads); pairDialog = null; pairEndpoint = null }
                .setNegativeButton(getString(R.string.reject)) { _, _ -> client.rejectConnection(id); pending.remove(id); pairDialog = null; pairEndpoint = null }
                .setOnCancelListener { client.rejectConnection(id); pending.remove(id); pairDialog = null; pairEndpoint = null }.create()
            pairDialog?.show()
        }
        override fun onConnectionResult(id: String, resolution: ConnectionResolution) {
            if (!pending.remove(id) || !active) { if (resolution.status.isSuccess) client.disconnectFromEndpoint(id); return }
            clearPairDialog(id)
            if (resolution.status.isSuccess) { remote = id; client.stopDiscovery(); status.text = getString(R.string.connected) }
            else status.text = getString(R.string.connection_status, resolution.status.statusCode)
        }
        override fun onDisconnected(id: String) {
            pending.remove(id); clearPairDialog(id)
            if (remote == id) { remote = null; cancelProbe(); if (active) status.text = getString(R.string.disconnected) }
        }
    }
    private val payloads = object : PayloadCallback() {
        override fun onPayloadReceived(id: String, payload: Payload) {
            if (id != remote) return
            val bytes = payload.asBytes() ?: return
            if (bytes.size != 1035 || bytes[0] != 68.toByte() || bytes[1] != 77.toByte() || bytes[2] != 80.toByte() || bytes[3] != 49.toByte()) return
            val index = ((bytes[5].toInt() and 255) shl 8) or (bytes[6].toInt() and 255)
            if (index !in 0..31) return
            if (bytes[4] == 1.toByte()) { bytes[4] = 2; client.sendPayload(id, Payload.fromBytes(bytes)); return }
            if (bytes[4] != 2.toByte() || index != chunk || ByteBuffer.wrap(bytes, 7, 4).int != runToken) return
            if ((11 until bytes.size).any { (bytes[it].toInt() and 255) != ((it - 11 + chunk) % 251) }) { cancelProbe(); status.text = getString(R.string.integrity_error); return }
            maximumRtt = maxOf(maximumRtt, SystemClock.elapsedRealtime() - sentAt)
            watchdog?.let(main::removeCallbacks); watchdog = null
            chunk++
            if (chunk == 32) {
                val elapsed = maxOf(1L, SystemClock.elapsedRealtime() - started)
                status.text = getString(R.string.probe_result, elapsed, maximumRtt, 64.0 * 1000 / elapsed)
                chunk = -1
            } else next()
        }
        override fun onPayloadTransferUpdate(id: String, update: PayloadTransferUpdate) {
            if (id == remote && update.status == PayloadTransferUpdate.Status.FAILURE) { cancelProbe(); status.text = getString(R.string.transfer_error) }
        }
    }
    private fun next() {
        val id = remote ?: return
        val bytes = ByteArray(1035)
        bytes[0] = 68; bytes[1] = 77; bytes[2] = 80; bytes[3] = 49; bytes[4] = 1
        bytes[5] = (chunk shr 8).toByte(); bytes[6] = chunk.toByte()
        ByteBuffer.wrap(bytes, 7, 4).putInt(runToken)
        for (i in 11 until bytes.size) bytes[i] = ((i - 11 + chunk) % 251).toByte()
        sentAt = SystemClock.elapsedRealtime()
        watchdog = Runnable { cancelProbe(); status.text = getString(R.string.timeout) }.also { main.postDelayed(it, 10000) }
        client.sendPayload(id, Payload.fromBytes(bytes)).addOnFailureListener { cancelProbe(); status.text = getString(R.string.send_error) }
    }
    private fun cancelProbe() { watchdog?.let(main::removeCallbacks); watchdog = null; chunk = -1 }
    private fun clearPairDialog(id: String) {
        if (pairEndpoint == id) { pairDialog?.dismiss(); pairDialog = null; pairEndpoint = null }
    }
    private fun stop() {
        active = false; permissionAction = null
        pairDialog?.cancel(); pairDialog = null
        pairEndpoint = null
        pending.toList().forEach { client.rejectConnection(it); client.disconnectFromEndpoint(it) }
        pending.clear()
        cancelProbe(); client.stopDiscovery(); client.stopAdvertising(); client.stopAllEndpoints()
        remote = null; found.clear(); endpoints.removeAllViews()
    }
    override fun onDestroy() { stop(); super.onDestroy() }
}
