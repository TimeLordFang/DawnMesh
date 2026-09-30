package dev.dawnmesh.intercom

import android.net.wifi.p2p.WifiP2pGroup
import org.webrtc.NetworkChangeDetector
import org.webrtc.NetworkChangeDetector.NetworkInformation
import org.webrtc.NetworkChangeDetector.IPAddress
import org.webrtc.NetworkChangeDetector.ConnectionType
import org.webrtc.NetworkMonitor
import org.webrtc.NetworkMonitorAutoDetect
import java.net.NetworkInterface
import java.util.concurrent.CopyOnWriteArraySet

/** Add the permission-checked P2P interface to WebRTC without binding the process.
 * The SDK's built-in P2P delegate queries protected group info during creation;
 * our existing plugin supplies it only after permission checks, including grants
 * made after the public call started. Handle 0 matches the SDK's P2P delegate.
 */
object WifiDirectNetworkMonitor {
    private val detectors = CopyOnWriteArraySet<WifiDirectNetworkDetector>()
    @Volatile private var latest: NetworkInformation? = null
    private var installed = false

    @Synchronized fun install() {
        if (installed) return
        NetworkMonitorAutoDetect.setIncludeWifiDirect(false)
        NetworkMonitor.getInstance().setNetworkChangeDetectorFactory { observer, context ->
            val delegate = NetworkMonitorAutoDetect(observer, context)
            val detector = WifiDirectNetworkDetector(delegate, observer) { detectors.remove(it) }
            detectors.add(detector)
            detector.update(latest)
            detector
        }
        installed = true
    }

    fun updateGroup(group: WifiP2pGroup?) {
        val info = try {
            val name = group?.`interface`
            val addresses = name?.let { NetworkInterface.getByName(it)?.inetAddresses?.toList() }
            if (name.isNullOrBlank() || addresses.isNullOrEmpty()) null else NetworkInformation(
                name, ConnectionType.CONNECTION_WIFI, ConnectionType.CONNECTION_NONE, 0L,
                addresses.map { IPAddress(it.address) }.toTypedArray(),
            )
        } catch (error: Exception) {
            Log.w("DawnWifiP2p", "读取直连网卡失败", error)
            null
        }
        latest = info
        for (detector in detectors) detector.update(info)
    }
}

internal class WifiDirectNetworkDetector(
    private val delegate: NetworkChangeDetector,
    private val observer: NetworkChangeDetector.Observer,
    private val removed: (WifiDirectNetworkDetector) -> Unit = {},
) : NetworkChangeDetector by delegate {
    @Volatile private var current: NetworkInformation? = null
    private var fingerprint: String? = null
    private var destroyed = false

    @Synchronized fun update(next: NetworkInformation?) {
        if (destroyed) return
        val key = next?.let { it.name + ":" + it.ipAddresses.joinToString { ip -> ip.address.joinToString(",") } }
        if (key == fingerprint) return
        val previous = current
        current = next
        fingerprint = key
        if (previous != null) observer.onNetworkDisconnect(previous.handle)
        if (next != null) observer.onNetworkConnect(next)
    }

    override fun getActiveNetworkList(): List<NetworkInformation>? {
        val base = delegate.activeNetworkList ?: return null
        val extra = current ?: return base
        return base.filter { it.handle != extra.handle } + extra
    }

    @Synchronized override fun destroy() {
        if (destroyed) return
        destroyed = true
        current = null
        removed(this)
        delegate.destroy()
    }
}
