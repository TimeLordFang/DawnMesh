package dev.dawnmesh.intercom

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Handler
import android.os.SystemClock
import java.util.UUID

/** Reads iOS room metadata; bounded parallelism, timeouts and retry rate. Main-thread confined. */
@SuppressLint("MissingPermission") // Caller checks the existing nearby-device permissions.
internal class BleGattRoomDiscovery(
    private val context: Context,
    private val handler: Handler,
    private val onRoom: (String, BleRoomAdvertisement.Room, Int) -> Unit,
) {
    private val service = UUID.fromString("7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004")
    private val metadata = UUID.fromString("7f75d4e1-7a46-4d74-9f8d-1e4bc5e4b004")
    private data class Seen(var lastSeen: Long, var attempted: Long = Long.MIN_VALUE / 2,
                            var reported: Long = Long.MIN_VALUE / 2,
                            var rssi: Int = 0, var room: BleRoomAdvertisement.Room? = null)
    private val seen = linkedMapOf<String, Seen>()
    private val pending = mutableMapOf<String, BluetoothGatt>()
    private val timers = mutableMapOf<String, Runnable>()
    private var generation = 0

    fun observe(device: BluetoothDevice, rssi: Int) {
        val address = device.address
        val now = SystemClock.elapsedRealtime()
        seen.entries.removeAll { now - it.value.lastSeen > 30_000 && !pending.containsKey(it.key) }
        if (!seen.containsKey(address) && seen.size >= 64) return
        val state = seen.getOrPut(address) { Seen(now) }
        state.lastSeen = now; state.rssi = rssi
        state.room?.let { room ->
            if (now - state.reported >= 2_000) { state.reported = now; onRoom(address, room, rssi) }
        }
        if (pending.containsKey(address) || pending.size >= 4 || now - state.attempted < 3_000) return
        state.attempted = now
        val token = generation
        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                handler.post {
                    if (!current(address, gatt, token)) return@post
                    if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                        if (!gatt.discoverServices()) finish(address, gatt)
                    } else finish(address, gatt)
                }
            }
            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                handler.post {
                    if (!current(address, gatt, token)) return@post
                    val characteristic = gatt.getService(service)?.getCharacteristic(metadata)
                    if (status != BluetoothGatt.GATT_SUCCESS || characteristic == null ||
                        !gatt.readCharacteristic(characteristic)) finish(address, gatt)
                }
            }
            override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic,
                                              value: ByteArray, status: Int) {
                complete(gatt, characteristic, value.copyOf(), status)
            }
            @Deprecated("Compatibility callback for Android 12 and earlier")
            @Suppress("DEPRECATION")
            override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
                complete(gatt, characteristic, characteristic.value?.copyOf() ?: byteArrayOf(), status)
            }
            private fun complete(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
                handler.post {
                    if (!current(address, gatt, token)) return@post
                    if (status == BluetoothGatt.GATT_SUCCESS && characteristic.uuid == metadata) {
                        BleRoomMetadata.parse(value)?.let { room ->
                            state.room = room; state.reported = SystemClock.elapsedRealtime()
                            onRoom(address, room, state.rssi)
                        }
                    }
                    finish(address, gatt)
                }
            }
        }
        try {
            val gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE) ?: return
            pending[address] = gatt
            val timeout = Runnable { if (pending[address] === gatt) finish(address, gatt) }
            timers[address] = timeout; handler.postDelayed(timeout, 5_000)
        } catch (error: SecurityException) {
            Log.w("DawnBle", "蓝牙房信息读取权限不足", error)
        } catch (error: IllegalArgumentException) {
            Log.w("DawnBle", "蓝牙房信息读取失败", error)
        }
    }
    private fun current(address: String, gatt: BluetoothGatt, token: Int): Boolean {
        if (generation == token && pending[address] === gatt) return true
        gatt.close(); return false
    }
    private fun finish(address: String, gatt: BluetoothGatt) {
        if (pending[address] === gatt) {
            pending.remove(address)
            timers.remove(address)?.let(handler::removeCallbacks)
        }
        gatt.disconnect(); gatt.close()
    }
    fun stop() {
        generation++
        for ((address, gatt) in pending.toMap()) finish(address, gatt)
        seen.clear()
    }
}
