package dev.dawnmesh.intercom

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Read-only discovery metadata, using the same GATT service as iOS hosts. */
@SuppressLint("MissingPermission") // The room host already checks Bluetooth permissions.
internal class BleGattRoomHost(private val context: Context) {
    private val serviceId = UUID.fromString("7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004")
    private val metadataId = UUID.fromString("7f75d4e1-7a46-4d74-9f8d-1e4bc5e4b004")
    @Volatile private var server: BluetoothGattServer? = null
    @Volatile private var value = byteArrayOf()
    private val mtus = ConcurrentHashMap<String, Int>()

    fun update(psm: Int, members: Int, name: String) {
        value = BleRoomMetadata.encode(psm, members, name)
    }

    fun start(psm: Int, members: Int, name: String): Boolean {
        stop()
        update(psm, members, name)
        var opened: BluetoothGattServer? = null
        val callback = object : BluetoothGattServerCallback() {
            override fun onServiceAdded(status: Int, service: BluetoothGattService) {
                if (status != BluetoothGatt.GATT_SUCCESS && server === opened) {
                    Log.w("DawnBle", "蓝牙房完整名称服务发布失败：$status")
                }
            }

            override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
                if (server === opened) mtus[device.address] = mtu.coerceIn(23, 517)
            }

            override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
                if (server === opened && newState == BluetoothProfile.STATE_DISCONNECTED) {
                    mtus.remove(device.address)
                }
            }

            override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int,
                                                     offset: Int, characteristic: BluetoothGattCharacteristic) {
                val active = opened ?: return
                if (server !== active) return
                val bytes = if (characteristic.uuid == metadataId)
                    BleRoomMetadata.read(value, offset, mtus[device.address] ?: 23) else null
                val status = when {
                    characteristic.uuid != metadataId -> BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
                    bytes == null -> BluetoothGatt.GATT_INVALID_OFFSET
                    else -> BluetoothGatt.GATT_SUCCESS
                }
                try {
                    active.sendResponse(device, requestId, status, offset, bytes)
                } catch (error: SecurityException) {
                    Log.w("DawnBle", "蓝牙房名称读取权限已撤销", error)
                }
            }
        }
        try {
            val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val created = manager?.openGattServer(context, callback) ?: return false
            opened = created
            server = created
            val service = BluetoothGattService(serviceId, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            service.addCharacteristic(BluetoothGattCharacteristic(metadataId,
                BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ))
            if (created.addService(service)) return true
        } catch (error: Exception) {
            Log.w("DawnBle", "蓝牙房完整名称服务不可用，保留广播发现", error)
        }
        stop()
        return false
    }

    fun stop() {
        val previous = server
        server = null
        mtus.clear()
        try { previous?.close() } catch (error: Exception) {
            Log.d("DawnBle", "关闭蓝牙房名称服务：$error")
        }
    }
}
