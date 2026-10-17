package dev.dawnmesh.intercom

import org.junit.Assert.*
import org.junit.Test

class BleRoomMetadataTest {
    @Test fun hostMetadataMatchesIosAndSurvivesLongReads() {
        val name = "房主小明的蓝牙房😀中文名称较长仍保持完整"
        val value = BleRoomMetadata.encode(129, 3, name)
        assertArrayEquals(byteArrayOf(1, 0, 129.toByte(), 3) + name.toByteArray(), value)
        assertEquals(name, BleRoomMetadata.parse(value)!!.name)
        var rebuilt = byteArrayOf()
        while (rebuilt.size < value.size) {
            rebuilt += BleRoomMetadata.read(value, rebuilt.size, 23)!!
        }
        assertArrayEquals(value, rebuilt)
        assertArrayEquals(byteArrayOf(), BleRoomMetadata.read(value, value.size, 23))
        assertNull(BleRoomMetadata.read(value, -1, 23))
        assertNull(BleRoomMetadata.read(value, value.size + 1, 23))
        assertArrayEquals(value, BleRoomMetadata.read(value, 0, 185))
    }

    @Test fun hostMetadataBoundsAndSanitizesUnicodeNames() {
        val value = BleRoomMetadata.encode(255, 99, "😀".repeat(30) + "\u0000")
        assertEquals(68, value.size)
        assertEquals(6, BleRoomMetadata.parse(value)!!.members)
        assertEquals("😀".repeat(16), BleRoomMetadata.parse(value)!!.name)
        assertEquals("房间", BleRoomMetadata.parse(BleRoomMetadata.encode(1, 1, "房\n间"))!!.name)
    }

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
