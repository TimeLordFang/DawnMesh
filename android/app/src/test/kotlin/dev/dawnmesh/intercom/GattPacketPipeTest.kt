package dev.dawnmesh.intercom

import org.junit.Assert.*
import org.junit.Test

class GattPacketPipeTest {
    private fun frame(size: Int = 512): ByteArray = byteArrayOf(11, 2, 0, 1,
        (size shr 8).toByte(), size.toByte()) + ByteArray(size) { it.toByte() }

    @Test fun mtu23And517PreserveEncryptedFrameBoundaries() {
        for (mtu in listOf(23, 247, 517)) {
            val sender = GattPacketPipe(); val receiver = GattPacketPipe()
            val expected = listOf(frame(1), frame(), frame(140))
            expected.forEach { assertTrue(sender.enqueue(it)) }
            val flushed = sender.flush(); val actual = mutableListOf<ByteArray>()
            while (!sender.isEmpty) {
                val fragment = sender.peek(mtu - 3)!!
                actual.addAll(receiver.receive(fragment)); sender.consume(fragment.size)
            }
            assertTrue(flushed.isDone); assertEquals(expected.size, actual.size)
            expected.indices.forEach { assertArrayEquals(expected[it], actual[it]) }
        }
    }
    @Test fun boundedQueueAndInvalidWireRejectWithoutAllocating() {
        val pipe = GattPacketPipe()
        repeat(64) { assertTrue(pipe.enqueue(frame())) }
        assertFalse(pipe.enqueue(frame()))
        val flushed = pipe.flush(); pipe.close(); assertTrue(flushed.isCompletedExceptionally)
        assertFalse(pipe.enqueue(byteArrayOf(1, 2, 0, 1, 0, 1, 5)))
        try { pipe.receive(byteArrayOf(11, 2, 0, 1, 127, 127)); fail() }
        catch (_: IllegalArgumentException) { }
    }
}
