package dev.dawnmesh.intercom

import org.junit.Assert.assertEquals
import org.junit.Test
import org.webrtc.NetworkChangeDetector
import org.webrtc.NetworkChangeDetector.ConnectionType
import org.webrtc.NetworkChangeDetector.NetworkInformation
import org.webrtc.NetworkChangeDetector.IPAddress

class WifiDirectNetworkDetectorTest {
    @Test fun lateP2pInterfaceKeepsInternetAndEmitsOnlyChanges() {
        val internet = NetworkInformation("rmnet0", ConnectionType.CONNECTION_4G,
            ConnectionType.CONNECTION_NONE, 100L, arrayOf(IPAddress(byteArrayOf(10, 0, 0, 1))))
        var disposed = 0
        val base = object : NetworkChangeDetector {
            override fun getCurrentConnectionType() = ConnectionType.CONNECTION_4G
            override fun supportNetworkCallback() = true
            override fun getActiveNetworkList() = listOf(internet)
            override fun destroy() { disposed++ }
        }
        val events = mutableListOf<String>()
        val observer = object : NetworkChangeDetector.Observer() {
            override fun onConnectionTypeChanged(type: ConnectionType) {}
            override fun onNetworkConnect(info: NetworkInformation) { events.add("connect:${info.name}") }
            override fun onNetworkDisconnect(handle: Long) { events.add("disconnect:$handle") }
            override fun onNetworkPreference(types: List<ConnectionType>, preference: Int) {}
        }
        val detector = WifiDirectNetworkDetector(base, observer)
        assertEquals(listOf(internet), detector.activeNetworkList)
        fun p2p() = NetworkInformation("p2p0", ConnectionType.CONNECTION_WIFI,
            ConnectionType.CONNECTION_NONE, 0L, arrayOf(IPAddress(byteArrayOf(192.toByte(), 168.toByte(), 49, 1))))
        detector.update(p2p()) // Permission/group arrives after the public call started.
        detector.update(p2p()) // Identical polling result must not restart ICE.
        assertEquals(listOf("connect:p2p0"), events)
        assertEquals(listOf("rmnet0", "p2p0"), detector.activeNetworkList!!.map { it.name })
        detector.update(null)
        assertEquals(listOf("connect:p2p0", "disconnect:0"), events)
        assertEquals(listOf(internet), detector.activeNetworkList)
        detector.destroy()
        detector.update(p2p())
        assertEquals(2, events.size)
        assertEquals(1, disposed)
    }
}
