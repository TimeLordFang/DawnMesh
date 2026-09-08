package dev.dawnmesh.intercom.audio

import org.junit.Assert.*
import org.junit.Test

class JitterBufferTest {
    private fun packet(value: Int) = byteArrayOf(value.toByte())
    private fun take(buffer: JitterBuffer) = (buffer.poll() as PollResult.Packet).data[0].toInt()

    @Test fun reliableTransportDoesNotInventLossForControlSequenceGaps() {
        val b = JitterBuffer(ordered = true)
        b.put(2, packet(1)); b.put(7, packet(2)); b.put(10, packet(3))
        assertEquals(1, take(b)); assertEquals(2, take(b)); assertEquals(3, take(b))
    }
    @Test fun starvationReprimesInsteadOfPlayingEachIsolatedArrival() {
        var now = 0L
        val b = JitterBuffer(prebufferFrames = 3, ordered = true, clockMs = { now })
        repeat(3) { b.put(it, packet(it)) }
        repeat(3) { take(b) }
        assertSame(PollResult.NotReady, b.poll())
        assertFalse(b.hasStarted())
        now = 80; b.put(3, packet(3))
        assertSame(PollResult.NotReady, b.poll())
        repeat(4) { b.put(4 + it, packet(4 + it)) }
        assertEquals(3, take(b))
    }
    @Test fun shortUtterancePlaysAtDeadlineAndNeverWaitsForever() {
        var now = 0L
        val b = JitterBuffer(prebufferFrames = 6, ordered = true, clockMs = { now })
        b.put(8, packet(1))
        now = 119; assertSame(PollResult.NotReady, b.poll())
        now = 120; assertEquals(1, take(b))
    }
    @Test fun orderedBurstsStayContinuousWithBluetoothPrebuffer() {
        var now = 0L
        val b = JitterBuffer(prebufferFrames = 6, ordered = true, clockMs = { now })
        repeat(8) { b.put(it, packet(it)) }
        repeat(40) { i ->
            if (i > 0 && i % 4 == 0) repeat(4) { b.put(8 + i + it, packet(8 + i - 4 + it)) }
            assertEquals(i, take(b))
            now += 20
        }
    }
    @Test fun overflowDropsOldestWithoutConcealingAlreadyDiscardedFrames() {
        val b = JitterBuffer(prebufferFrames = 2, maxBuffer = 4)
        b.put(0, packet(0)); b.put(1, packet(1)); assertEquals(0, take(b))
        for (i in 2..10) b.put(i, packet(i))
        assertEquals(4, b.pendingCount()); assertEquals(7, take(b))
    }
    @Test fun unorderedPathReordersWraparoundAndReportsActualMissingPacket() {
        val b = JitterBuffer()
        b.put(65534, packet(1)); b.put(1, packet(4)); b.put(65535, packet(2))
        assertEquals(1, take(b)); assertEquals(2, take(b))
        assertSame(PollResult.Lost, b.poll()); assertEquals(4, take(b))
        b.put(65535, packet(9)); assertEquals(0, b.pendingCount())
    }
}
