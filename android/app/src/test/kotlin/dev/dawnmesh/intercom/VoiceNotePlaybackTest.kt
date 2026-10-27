package dev.dawnmesh.intercom

import io.github.jaredmdobson.concentus.OpusApplication
import io.github.jaredmdobson.concentus.OpusEncoder
import org.junit.Assert.*
import org.junit.Test

class VoiceNotePlaybackTest {
    private fun note(count: Int): ByteArray {
        val encoder = OpusEncoder(16000, 1, OpusApplication.OPUS_APPLICATION_VOIP)
        val packet = ByteArray(512)
        val pcm = ShortArray(320) { ((it % 32 - 16) * 300).toShort() }
        val out = java.io.ByteArrayOutputStream()
        out.write(1); out.write(count shr 8); out.write(count and 255)
        repeat(count) {
            val length = encoder.encode(pcm, 0, 320, packet, 0, packet.size)
            out.write(length shr 8); out.write(length and 255); out.write(packet, 0, length)
        }
        return out.toByteArray()
    }
    @Test fun decodesRealTwentyMillisecondOpusPacketsAtMaximumDuration() {
        val decoded = VoiceNotePlayback.decode(note(750))
        assertEquals(240000, decoded.size)
        assertTrue(decoded.any { it.toInt() != 0 })
    }
    @Test fun rejectsTruncationTrailingDataOversizedCountAndCancelledWork() {
        val valid = note(2)
        for (bytes in listOf(valid.copyOf(valid.size - 1), valid + byteArrayOf(0), byteArrayOf(1, 3, 0))) {
            try { VoiceNotePlayback.decode(bytes); fail("Malformed note accepted") }
            catch (_: IllegalArgumentException) { }
        }
        try { VoiceNotePlayback.decode(valid) { false }; fail("Cancelled decode ran") }
        catch (_: IllegalStateException) { }
    }
}
