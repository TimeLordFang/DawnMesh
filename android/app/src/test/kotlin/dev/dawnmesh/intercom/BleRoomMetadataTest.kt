package dev.dawnmesh.intercom

import org.junit.Assert.*
import org.junit.Test

class BleRoomMetadataTest {
    @Test fun acceptsSharedIosFixtureAndEmptyName() {
        val room = BleRoomMetadata.parse(byteArrayOf(1, 0, 129.toByte(), 3) + "房😀间".toByteArray())!!
        assertEquals(129, room.psm)
        assertEquals(3, room.members)
        assertEquals("房😀间", room.name)
        assertEquals("蓝牙房", BleRoomMetadata.parse(byteArrayOf(1, 0, 129.toByte(), 1))!!.name)
    }
    @Test fun rejectsUnknownVersionBadChannelsCapacityAndCorruptNames() {
        val cases = listOf(byteArrayOf(), byteArrayOf(2, 0, 129.toByte(), 1),
            byteArrayOf(1, 1, 0, 1), byteArrayOf(1, 0, 0, 1),
            byteArrayOf(1, 0, 129.toByte(), 7), byteArrayOf(1, 0, 129.toByte(), 0),
            byteArrayOf(1, 0, 129.toByte(), 1, -1), byteArrayOf(1, 0, 129.toByte(), 1, 0),
            byteArrayOf(1, 0, 129.toByte(), 1) + ByteArray(65) { 65 })
        for (value in cases) assertNull(BleRoomMetadata.parse(value))
    }
}
