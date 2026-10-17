package dev.dawnmesh.intercom

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/** Versioned GATT value shared with iOS: version, big-endian PSM, members, UTF-8 name. */
internal object BleRoomMetadata {
    fun parse(bytes: ByteArray): BleRoomAdvertisement.Room? {
        if (bytes.size !in 4..68 || bytes[0].toInt() != 1) return null
        val psm = ((bytes[1].toInt() and 255) shl 8) or (bytes[2].toInt() and 255)
        val members = bytes[3].toInt() and 255
        if (psm !in 1..255 || members !in 1..6) return null
        val text = try {
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes, 4, bytes.size - 4)).toString()
        } catch (_: java.nio.charset.CharacterCodingException) { return null }
        if (text.any { it.isISOControl() }) return null
        return BleRoomAdvertisement.Room(psm, members, text.ifEmpty { "蓝牙房" })
    }
}
