package dev.dawnmesh.intercom

import org.junit.Assert.*
import org.junit.Test

class BonjourRoomMetadataTest {
    private val apple = mapOf("roomId" to "ios", "roomName" to "中文 🌅", "hostNickname" to "iPhone", "port" to "8988", "members" to "3")
    @Test fun appleProxyUsesResolvedSrvPortInsteadOfTxtPort() {
        val room = BonjourRoomMetadata.room(apple, BonjourRoomMetadata.WIFI, "192.168.1.4", 51234)!!
        assertEquals(51234, room["port"])
        assertEquals("中文 🌅", room["roomName"])
        assertEquals("iPhone", room["hostNickname"])
        assertEquals(3, room["members"])
    }
    @Test fun supportsBothServiceTypesAndRejectsForeignMetadata() {
        assertEquals("_dawnmesh._tcp.", BonjourRoomMetadata.serviceType(BonjourRoomMetadata.WIFI))
        assertEquals("_dawnfusion._tcp.", BonjourRoomMetadata.serviceType(BonjourRoomMetadata.FUSION))
        assertNull(BonjourRoomMetadata.serviceType("unrelated"))
        assertNull(BonjourRoomMetadata.room(apple + ("magic" to BonjourRoomMetadata.FUSION), BonjourRoomMetadata.WIFI, "192.168.1.4", 8988))
        assertNotNull(BonjourRoomMetadata.room(apple + ("magic" to BonjourRoomMetadata.FUSION), BonjourRoomMetadata.FUSION, "192.168.1.4", 8991))
    }
    @Test fun validatesUntrustedRoomMetadata() {
        for (port in listOf(0, -1, 65536)) assertNull(BonjourRoomMetadata.room(apple, BonjourRoomMetadata.WIFI, "192.168.1.4", port))
        assertNull(BonjourRoomMetadata.room(apple - "roomId", BonjourRoomMetadata.WIFI, "192.168.1.4", 8988))
        assertEquals(99, BonjourRoomMetadata.room(apple + ("members" to "100000"), BonjourRoomMetadata.WIFI, "192.168.1.4", 8988)!!["members"])
    }
    @Test fun unicodeTxtFieldsRespectByteLimitWithoutSplittingCharacters() {
        val result = BonjourRoomMetadata.text("🌅".repeat(100))
        assertTrue(result.toByteArray(Charsets.UTF_8).size <= 180)
        assertEquals("🌅".repeat(45), result)
        assertFalse(result.contains('\uFFFD'))
    }
}
