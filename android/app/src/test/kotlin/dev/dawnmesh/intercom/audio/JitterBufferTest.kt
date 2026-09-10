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
    @Test fun bluetoothCoexistenceCanGrowToFourteenFrameTarget() {
        val b = JitterBuffer(
            prebufferFrames = 6,
            maxBuffer = 24,
            maxAdaptiveTarget = 14,
            ordered = true,
        )
        repeat(6) {
            repeat(40) { n -> b.put(n, packet(n)) }
            while (b.poll() is PollResult.Packet) Unit
        }
        assertTrue(b.diagnostics().contains("target=14"))
    }

    @Test fun shortOrderedGapUsesPlcThenDropsLateAudio() {
        val b = JitterBuffer(
            prebufferFrames = 2,
            maxBuffer = 8,
            maxConcealmentFrames = 2,
            ordered = true,
        )
        b.put(0, packet(0)); b.put(1, packet(1))
        assertEquals(0, take(b)); assertEquals(1, take(b))

        assertSame(PollResult.Lost, b.poll())
        assertSame(PollResult.Lost, b.poll())
        b.put(2, packet(2)); b.put(3, packet(3)); b.put(4, packet(4))

        assertEquals(4, take(b))
        assertTrue(b.diagnostics().contains("concealed=2"))
        assertTrue(b.diagnostics().contains("dropped=2"))
    }

    @Test fun stablePlaybackTrimsPreviouslyAccumulatedLatency() {
        val b = JitterBuffer(
            prebufferFrames = 2,
            maxBuffer = 8,
            maxAdaptiveTarget = 6,
            stableFramesBeforeDecay = 3,
            ordered = true,
        )
        repeat(2) { b.put(it, packet(it)) }
        repeat(2) { take(b) }
        assertSame(PollResult.NotReady, b.poll()) // target grows from 2 to 4

        repeat(8) { b.put(10 + it, packet(10 + it)) }
        assertEquals(10, take(b))
        assertEquals(11, take(b))
        val trimmed = b.poll() as PollResult.Packet
        assertArrayEquals(packet(12), trimmed.discardedBefore.single())
        assertArrayEquals(packet(13), trimmed.data)
        assertTrue(b.diagnostics().contains("target=3"))
        assertTrue(b.diagnostics().contains("trimmed=1"))
    }

    @Test fun lowLatencyDropsBacklogAndPlaysNewestWindow() {
        val b = JitterBuffer(
            prebufferFrames = 2,
            maxBuffer = 8,
            maxAdaptiveTarget = 4,
            maxPlayoutQueueFrames = 3,
            ordered = true,
        )
        repeat(8) { b.put(it, packet(it)) }

        val result = b.poll() as PollResult.Packet
        assertEquals(listOf(0, 1, 2, 3, 4), result.discardedBefore.map { it[0].toInt() })
        assertEquals(5, result.data[0].toInt())
        assertEquals(2, b.pendingCount())
        assertTrue(b.diagnostics().contains("trimmed=5"))
    }
}
