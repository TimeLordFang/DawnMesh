package host.msknet.sunsetripple

import org.junit.Assert.*
import org.junit.Test

class BleRoomAdvertisementTest {
    private fun ad(psm: Int = 129, members: Int = 2, name: String = "") : ByteArray {
        val data = byteArrayOf(0xff.toByte(), 0xff.toByte(), 0xff.toByte(), 0, psm.toByte(), members.toByte()) + name.toByteArray(Charsets.UTF_8)
        return byteArrayOf(data.size.toByte()) + data
    }
    @Test fun parsesDuplicateManufacturerStructuresWithoutMetadataInName() {
        val raw = byteArrayOf(2, 1, 6) + ad() + ad(name = "曙光的聊天室")
        val room = BleRoomAdvertisement.parse(raw)!!
        assertEquals(129, room.psm); assertEquals(2, room.members)
        assertEquals("曙光的聊天室", room.name)
    }
    @Test fun keepsFullNameIfMetadataRecordArrivesLast() {
        assertEquals("红米", BleRoomAdvertisement.parse(ad(name = "红米") + ad())!!.name)
    }
    @Test fun supportsAdvertisementOnlyAndOldSingleResponse() {
        assertEquals("蓝牙房", BleRoomAdvertisement.parse(ad())!!.name)
        assertEquals("oneplus", BleRoomAdvertisement.parse(ad(name = "oneplus"))!!.name)
    }
    @Test fun rejectsMalformedUtf8ControlBytesAndInvalidMetadata() {
        assertNull(BleRoomAdvertisement.parse(ad(psm = 0)))
        assertNull(BleRoomAdvertisement.parse(ad(members = 7)))
        assertEquals("蓝牙房", BleRoomAdvertisement.parse(ad(name = "\u0000坏数据"))!!.name)
        val invalid = ad(name = "x"); invalid[invalid.lastIndex] = 0xff.toByte()
        assertEquals("蓝牙房", BleRoomAdvertisement.parse(invalid)!!.name)
        assertNull(BleRoomAdvertisement.parse(byteArrayOf(31, -1, -1)))
    }
    @Test fun truncatesAtUnicodeCodePointWithoutSplittingEmojiOrChinese() {
        val text = "房😀间"
        assertEquals("房", String(BleRoomAdvertisement.truncateUtf8(text, 6), Charsets.UTF_8))
        assertEquals("房😀", String(BleRoomAdvertisement.truncateUtf8(text, 7), Charsets.UTF_8))
        assertEquals(text, String(BleRoomAdvertisement.truncateUtf8(text, 10), Charsets.UTF_8))
    }
}
