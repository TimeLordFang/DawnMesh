package dev.dawnmesh.intercom

import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.SystemClock
import java.util.concurrent.CompletableFuture

/** Explicit L2CAP-failure fallback. Writes with response and indications provide
 * ATT ordering; PAKE and member-authenticated room frames retain end-to-end trust.
 */
@SuppressLint("MissingPermission")
internal class BleGattClient(
    private val context: Context,
    private val handler: Handler,
    private val onFrame: (String, ByteArray) -> Unit,
    private val onDisconnected: () -> Unit,
) {
    private var gatt: BluetoothGatt? = null
    private var data: BluetoothGattCharacteristic? = null
    private var pipe = GattPacketPipe()
    private var mtu = 23
    private var writing = 0
    private var connected = false
    private var completion: ((Boolean) -> Unit)? = null
    private var progress = 0L
    private val watchdog = object : Runnable {
        override fun run() {
            if (gatt == null) return
            if ((!connected || !pipe.isEmpty) && SystemClock.elapsedRealtime() - progress > 8_000) {
                stop(notify = true); return
            }
            handler.postDelayed(this, 1_000)
        }
    }
    fun connect(device: BluetoothDevice, done: (Boolean) -> Unit) {
        stop(); completion = done; progress = SystemClock.elapsedRealtime()
        val callback = object : BluetoothGattCallback() {
            private fun active(source: BluetoothGatt, action: () -> Unit) {
                handler.post {
                    if (gatt !== source) return@post
                    try { action() } catch (_: Exception) { stop(notify = true) }
                }
            }
            override fun onConnectionStateChange(source: BluetoothGatt, status: Int, newState: Int) {
                active(source) {
                    if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                        if (!source.discoverServices()) stop(notify = true)
                    } else stop(notify = true)
                }
            }
            override fun onServicesDiscovered(source: BluetoothGatt, status: Int) {
                active(source) {
                    val c = source.getService(BleGattRoomHost.serviceId)?.getCharacteristic(BleGattRoomHost.dataId)
                    if (status != BluetoothGatt.GATT_SUCCESS || c == null ||
                        c.properties and BluetoothGattCharacteristic.PROPERTY_WRITE == 0 ||
                        c.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE == 0) {
                        stop(notify = true); return@active
                    }
                    data = c
                    // MTU negotiation is optional; the protocol also works at 23.
                    if (!source.requestMtu(247)) subscribe(source)
                }
            }
            override fun onMtuChanged(source: BluetoothGatt, nextMtu: Int, status: Int) {
                active(source) {
                    if (status == BluetoothGatt.GATT_SUCCESS) mtu = nextMtu.coerceIn(23, 517)
                    if (!connected) subscribe(source)
                }
            }
            override fun onDescriptorWrite(source: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
                active(source) {
                    if (descriptor.uuid != BleGattRoomHost.cccdId || status != BluetoothGatt.GATT_SUCCESS) {
                        stop(notify = true); return@active
                    }
                    connected = true; progress = SystemClock.elapsedRealtime()
                    val done = completion; completion = null; done?.invoke(true)
                }
            }
            override fun onCharacteristicChanged(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
                receive(source, characteristic, value.copyOf())
            }
            @Deprecated("Android 12 and earlier")
            @Suppress("DEPRECATION")
            override fun onCharacteristicChanged(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
                receive(source, characteristic, characteristic.value?.copyOf() ?: byteArrayOf())
            }
            private fun receive(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic, bytes: ByteArray) {
                active(source) {
                    if (connected && characteristic.uuid == BleGattRoomHost.dataId) {
                        pipe.receive(bytes).forEach { onFrame(source.device.address, it) }
                    }
                }
            }
            override fun onCharacteristicWrite(source: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
                active(source) {
                    if (writing == 0 || characteristic.uuid != BleGattRoomHost.dataId) return@active
                    if (status != BluetoothGatt.GATT_SUCCESS) { stop(notify = true); return@active }
                    pipe.consume(writing); writing = 0; progress = SystemClock.elapsedRealtime(); drain()
                }
            }
        }
        try {
            gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
            if (gatt == null) stop(notify = true) else handler.post(watchdog)
        } catch (_: Exception) { stop(notify = true) }
    }
    @Suppress("DEPRECATION")
    private fun subscribe(source: BluetoothGatt) {
        val c = data ?: return
        val descriptor = c.getDescriptor(BleGattRoomHost.cccdId)
        if (descriptor == null || !source.setCharacteristicNotification(c, true)) { stop(notify = true); return }
        val ok = if (Build.VERSION.SDK_INT >= 33) source.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_INDICATION_VALUE) == BluetoothStatusCodes.SUCCESS
            else { descriptor.value = BluetoothGattDescriptor.ENABLE_INDICATION_VALUE; source.writeDescriptor(descriptor) }
        if (!ok) stop(notify = true)
    }
    fun send(bytes: ByteArray): Boolean {
        if (!connected) return false
        if (pipe.isEmpty) progress = SystemClock.elapsedRealtime()
        if (!pipe.enqueue(bytes)) { stop(notify = true); return false }
        drain(); return true
    }
    @Suppress("DEPRECATION")
    private fun drain() {
        if (!connected || writing > 0) return
        val source = gatt ?: return
        val c = data ?: return
        val bytes = pipe.peek(mtu - 3) ?: return
        writing = bytes.size
        val ok = try {
            if (Build.VERSION.SDK_INT >= 33) source.writeCharacteristic(c, bytes, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothStatusCodes.SUCCESS
            else { c.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT; c.value = bytes; source.writeCharacteristic(c) }
        } catch (_: Exception) { false }
        if (!ok) stop(notify = true)
    }
    fun flush(): CompletableFuture<Void> = pipe.flush()
    fun stop(notify: Boolean = false) {
        handler.removeCallbacks(watchdog)
        val source = gatt; gatt = null; data = null
        val wasConnected = connected; connected = false; writing = 0; mtu = 23
        pipe.close(); pipe = GattPacketPipe()
        val done = completion; completion = null; done?.invoke(false)
        try { source?.disconnect(); source?.close() } catch (_: Exception) { }
        if (notify && wasConnected) onDisconnected()
    }
}
