package dev.dawnmesh.intercom

import org.junit.Assert.assertEquals
import org.junit.Test

class WifiConnectionStateTest {
    @Test fun healthyOwnerIsReportedAsFormed() {
        val state = wifiConnectionState(true, true, "192.168.49.1")
        assertEquals(true, state["groupFormed"])
        assertEquals(true, state["isConnected"])
        assertEquals(true, state["isGroupOwner"])
    }
    @Test fun disconnectedAndClientStatesRemainDistinct() {
        assertEquals(false, wifiConnectionState(false, false, "")["groupFormed"])
        val client = wifiConnectionState(true, false, "192.168.49.1")
        assertEquals(true, client["groupFormed"])
        assertEquals(false, client["isGroupOwner"])
    }
}
