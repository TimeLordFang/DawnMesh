package dev.dawnmesh.intercom

import android.annotation.SuppressLint
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.SystemClock

/** Public room identity only; never publish invite codes or relay credentials. */
@SuppressLint("MissingPermission")
internal class FusionWifiDiscovery(
    private val manager: () -> WifiP2pManager?,
    private val channel: () -> WifiP2pManager.Channel?,
    private val changed: () -> Unit,
) {
    private data class Room(val device: WifiP2pDevice, val id: String, val name: String, val seen: Long)
    private val rooms = linkedMapOf<String, Room>()
    private var request: WifiP2pDnsSdServiceRequest? = null
    private var service: WifiP2pDnsSdServiceInfo? = null
    private var scanning = false
    private var generation = 0
    private var advertisementGeneration = 0
    private val type = "_dawnmesh-fusion._tcp"

    fun peers(): List<Map<String, Any>> = rooms.values.map { room ->
        mapOf(
            "name" to (room.device.deviceName ?: "附近设备"),
            "address" to room.device.deviceAddress,
            "status" to room.device.status,
            "isGroupOwner" to room.device.isGroupOwner,
            "fusionRoomId" to room.id,
            "fusionRoomName" to room.name,
        )
    }

    fun discover(done: (Boolean) -> Unit) {
        val m = manager(); val c = channel()
        if (m == null || c == null || scanning) { done(false); return }
        val now = SystemClock.elapsedRealtime()
        if (rooms.entries.removeAll { now - it.value.seen > 15000 }) changed()
        val scanGeneration = generation
        m.setDnsSdResponseListeners(c, { _, _, _ -> }, { domain, record, device ->
            if (scanGeneration == generation && domain.equals("DawnMesh.$type.local.", ignoreCase = true)) {
                val id = record["id"] ?: ""
                if (id.matches(Regex("^[A-Za-z0-9_-]{43}$")) &&
                    (rooms.size < 64 || rooms.containsKey(device.deviceAddress))) {
                    rooms[device.deviceAddress] = Room(device, id,
                        (record["name"] ?: "融合房").take(64), SystemClock.elapsedRealtime())
                    changed()
                }
            }
        })
        scanning = true
        fun scan() {
            m.discoverServices(c, listener { ok -> scanning = false; done(ok) })
        }
        if (request != null) { scan(); return }
        val pending = WifiP2pDnsSdServiceRequest.newInstance(type)
        request = pending
        m.addServiceRequest(c, pending, listener { ok ->
            if (scanGeneration != generation) {
                m.removeServiceRequest(c, pending, null)
                scanning = false
                done(false)
            } else if (ok) scan() else {
                request = null
                scanning = false
                done(false)
            }
        })
    }

    fun advertise(id: String, name: String, done: (Boolean) -> Unit) {
        val m = manager(); val c = channel()
        if (m == null || c == null || !id.matches(Regex("^[A-Za-z0-9_-]{43}$"))) {
            done(false); return
        }
        if (service != null) { done(true); return }
        val currentGeneration = advertisementGeneration
        // A lone group owner is a ready entrance, not a connected teammate.
        m.requestConnectionInfo(c) { info ->
            if (currentGeneration != advertisementGeneration || info?.groupFormed != true || !info.isGroupOwner) {
                done(false)
            } else {
                val pending = WifiP2pDnsSdServiceInfo.newInstance("DawnMesh", type,
                    mapOf("id" to id, "name" to name.take(64)))
                service = pending
                m.addLocalService(c, pending, listener { ok ->
                    if (currentGeneration != advertisementGeneration) {
                        m.removeLocalService(c, pending, null)
                        done(false)
                        return@listener
                    }
                    if (!ok && service === pending) service = null
                    done(ok)
                })
            }
        }
    }

    fun stopDiscovery() {
        generation++
        request?.let { manager()?.removeServiceRequest(channel(), it, null) }
        request = null
        rooms.clear()
        changed()
    }

    fun stopAdvertising() {
        advertisementGeneration++
        service?.let { manager()?.removeLocalService(channel(), it, null) }
        service = null
    }

    private fun listener(done: (Boolean) -> Unit) = object : WifiP2pManager.ActionListener {
        override fun onSuccess() = done(true)
        override fun onFailure(reason: Int) = done(false)
    }
}
