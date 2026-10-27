package dev.dawnmesh.intercom

import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.SystemClock
import java.util.UUID
import java.util.concurrent.CompletableFuture

/** Existing discovery service plus an acknowledged, encrypted small-message pipe.
 * L2CAP remains the primary voice link. All state is confined to the main handler.
 */
@SuppressLint("MissingPermission")
internal class BleGattRoomHost(
    private val context: Context,
    private val handler: Handler,
    private val onFrame: (String, ByteArray) -> Unit,
) {
    companion object {
        val serviceId: UUID = UUID.fromString("7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004")
        val metadataId: UUID = UUID.fromString("7f75d4e1-7a46-4d74-9f8d-1e4bc5e4b004")
        val dataId: UUID = UUID.fromString("7f75d4e2-7a46-4d74-9f8d-1e4bc5e4b004")
        val cccdId: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
    private var server: BluetoothGattServer? = null
    private var value = byteArrayOf()
    private var characteristic: BluetoothGattCharacteristic? = null
    private data class Peer(val device: BluetoothDevice, val pipe: GattPacketPipe = GattPacketPipe(),
                            var mtu: Int = 23, var progress: Long = SystemClock.elapsedRealtime())
    private val peers = linkedMapOf<String, Peer>()
    private val mtus = mutableMapOf<String, Int>()
    private var inFlight: Pair<String, Int>? = null
    private var cursor = 0
    private val watchdog = object : Runnable {
        override fun run() {
            if (server == null) return
            val now = SystemClock.elapsedRealtime()
            for ((address, peer) in peers.toMap()) {
                if (!peer.pipe.isEmpty && now - peer.progress > 8_000) drop(address)
            }
            drain(); handler.postDelayed(this, 1_000)
        }
    }

    fun update(psm: Int, members: Int, name: String) { value = BleRoomMetadata.encode(psm, members, name) }
    fun start(psm: Int, members: Int, name: String): Boolean {
        stop(); update(psm, members, name)
        var opened: BluetoothGattServer? = null
        fun active(action: (BluetoothGattServer) -> Unit) = handler.post {
            val current = opened
            if (current != null && server === current) {
                try { action(current) } catch (_: SecurityException) {
                    Log.w("DawnBle", "Bluetooth permission revoked during GATT callback")
                    stop()
                }
            }
        }
        val callback = object : BluetoothGattServerCallback() {
            override fun onServiceAdded(status: Int, service: BluetoothGattService) {
                if (status != BluetoothGatt.GATT_SUCCESS) Log.w("DawnBle", "GATT service failed: $status")
            }
            override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
                active { mtus[device.address] = mtu.coerceIn(23, 517); peers[device.address]?.mtu = mtu.coerceIn(23, 517) }
            }
            override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
                active { if (newState == BluetoothProfile.STATE_DISCONNECTED) drop(device.address, disconnect = false) }
            }
            override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, c: BluetoothGattCharacteristic) {
                active { current ->
                    val bytes = if (c.uuid == metadataId) BleRoomMetadata.read(value, offset, mtus[device.address] ?: 23) else null
                    current.sendResponse(device, requestId, if (bytes == null) BluetoothGatt.GATT_INVALID_OFFSET else BluetoothGatt.GATT_SUCCESS, offset, bytes)
                }
            }
            override fun onDescriptorWriteRequest(device: BluetoothDevice, requestId: Int, d: BluetoothGattDescriptor,
                preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, bytes: ByteArray) {
                val data = bytes.copyOf()
                active { current ->
                    var status = BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
                    if (d.uuid == cccdId && !preparedWrite && offset == 0) {
                        if (data.contentEquals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE) && (peers.containsKey(device.address) || peers.size < 5)) {
                            peers.putIfAbsent(device.address, Peer(device, mtu = mtus[device.address] ?: 23))
                            status = BluetoothGatt.GATT_SUCCESS
                        } else if (data.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)) {
                            drop(device.address, disconnect = false); status = BluetoothGatt.GATT_SUCCESS
                        }
                    }
                    if (responseNeeded) current.sendResponse(device, requestId, status, 0, null)
                }
            }
            override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int, c: BluetoothGattCharacteristic,
                preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, bytes: ByteArray) {
                val data = bytes.copyOf()
                active { current ->
                    val peer = peers[device.address]
                    if (c.uuid != dataId || preparedWrite || !responseNeeded || offset != 0 || peer == null) {
                        if (responseNeeded) current.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, offset, null)
                        return@active
                    }
                    try {
                        val frames = peer.pipe.receive(data)
                        current.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
                        frames.forEach { onFrame(device.address, it) }
                    } catch (_: IllegalArgumentException) {
                        current.sendResponse(device, requestId, BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH, 0, null)
                        drop(device.address)
                    }
                }
            }
            override fun onNotificationSent(device: BluetoothDevice, status: Int) {
                active {
                    val pending = inFlight
                    if (pending?.first == device.address) {
                        inFlight = null
                        if (status == BluetoothGatt.GATT_SUCCESS) {
                            peers[device.address]?.let { peer -> peer.pipe.consume(pending.second); peer.progress = SystemClock.elapsedRealtime() }
                        } else drop(device.address)
                        drain()
                    }
                }
            }
        }
        try {
            val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val created = manager?.openGattServer(context, callback) ?: return false
            opened = created; server = created
            val service = BluetoothGattService(serviceId, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            service.addCharacteristic(BluetoothGattCharacteristic(metadataId, BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ))
            val data = BluetoothGattCharacteristic(dataId, BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_INDICATE, BluetoothGattCharacteristic.PERMISSION_WRITE)
            data.addDescriptor(BluetoothGattDescriptor(cccdId, BluetoothGattDescriptor.PERMISSION_WRITE))
            service.addCharacteristic(data); characteristic = data
            if (created.addService(service)) { handler.post(watchdog); return true }
        } catch (error: Exception) { Log.w("DawnBle", "GATT service unavailable", error) }
        stop(); return false
    }
    fun send(data: ByteArray, exclude: String?): Boolean {
        var sent = false
        for ((address, peer) in peers.toMap()) {
            if (address == exclude) continue
            if (peer.pipe.isEmpty) peer.progress = SystemClock.elapsedRealtime()
            if (peer.pipe.enqueue(data)) sent = true else drop(address)
        }
        drain(); return sent
    }
    @Suppress("DEPRECATION")
    private fun drain() {
        if (inFlight != null) return
        val current = server ?: return
        val c = characteristic ?: return
        val candidates = peers.entries.filter { !it.value.pipe.isEmpty }
        if (candidates.isEmpty()) return
        val entry = candidates[(cursor++ and Int.MAX_VALUE) % candidates.size]
        val bytes = entry.value.pipe.peek(entry.value.mtu - 3) ?: return
        inFlight = entry.key to bytes.size
        val ok = try {
            if (Build.VERSION.SDK_INT >= 33) current.notifyCharacteristicChanged(entry.value.device, c, true, bytes) == BluetoothStatusCodes.SUCCESS
            else { c.value = bytes; current.notifyCharacteristicChanged(entry.value.device, c, true) }
        } catch (_: Exception) { false }
        if (!ok) { inFlight = null; drop(entry.key) }
    }
    fun flush(): CompletableFuture<Void> = CompletableFuture.allOf(*peers.values.map { it.pipe.flush() }.toTypedArray())
    private fun drop(address: String, disconnect: Boolean = true) {
        mtus.remove(address)
        val peer = peers.remove(address) ?: return
        peer.pipe.close()
        if (inFlight?.first == address) inFlight = null
        if (disconnect) try { server?.cancelConnection(peer.device) } catch (_: Exception) { }
    }
    fun stop() {
        handler.removeCallbacks(watchdog)
        val previous = server; server = null; characteristic = null; inFlight = null
        peers.values.forEach { it.pipe.close() }; peers.clear(); mtus.clear()
        try { previous?.close() } catch (_: Exception) { }
    }
}
