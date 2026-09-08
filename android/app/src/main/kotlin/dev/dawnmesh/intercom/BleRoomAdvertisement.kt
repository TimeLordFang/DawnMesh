package dev.dawnmesh.intercom

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/** Parse individual AD structures, before Android merges equal company IDs. */
internal object BleRoomAdvertisement {
    data class Room(val psm: Int, val members: Int, val name: String)

    fun parse(record: ByteArray, manufacturerId: Int = 0xffff): Room? {
        var offset = 0
        var selected: Room? = null
        while (offset < record.size) {
            val length = record[offset].toInt() and 0xff
            if (length == 0) break
            val end = offset + 1 + length
            if (end > record.size) break
            val type = record[offset + 1].toInt() and 0xff
            if (type == 0xff && length >= 6) {
                val company = (record[offset + 2].toInt() and 0xff) or
                    ((record[offset + 3].toInt() and 0xff) shl 8)
                if (company == manufacturerId) {
                    val start = offset + 4
                    val psm = ((record[start].toInt() and 0xff) shl 8) or
                        (record[start + 1].toInt() and 0xff)
                    val members = record[start + 2].toInt() and 0xff
                    if (psm in 1..255 && members in 1..6) {
                        val name = decodeName(record, start + 3, end)
                        if (selected == null || !name.isNullOrEmpty()) {
                            selected = Room(psm, members, name ?: "蓝牙房")
                        }
                    }
                }
            }
            offset = end
        }
        return selected
    }

    private fun decodeName(bytes: ByteArray, start: Int, end: Int): String? {
        if (start == end) return null
        return try {
            val value = Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes, start, end - start)).toString()
            // Metadata/control bytes must never be rendered as a room name.
            value.takeIf { it.isNotBlank() && it.none { c -> c.isISOControl() } }
        } catch (_: java.nio.charset.CharacterCodingException) { null }
    }

    fun truncateUtf8(text: String, budget: Int): ByteArray {
        var end = 0
        var bytes = 0
        while (end < text.length) {
            val codePoint = text.codePointAt(end)
            val chars = Character.charCount(codePoint)
            val count = String(Character.toChars(codePoint)).toByteArray(Charsets.UTF_8).size
            if (bytes + count > budget) break
            bytes += count
            end += chars
        }
        return text.substring(0, end).toByteArray(Charsets.UTF_8)
    }
}
