package host.msknet.sunsetripple

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class BoundedFrameWriterTest {
    @Test fun preservesOrderAndFlushes() {
        val written = java.util.Collections.synchronizedList(mutableListOf<Int>())
        val writer = BoundedFrameWriter(write = { written.add(it[0].toInt()) },
            closeTransport = {}, onFailure = { throw AssertionError(it) })
        try {
            assertTrue(writer.send(byteArrayOf(1)))
            assertTrue(writer.send(byteArrayOf(2)))
            writer.flush().get(2, TimeUnit.SECONDS)
            assertEquals(listOf(1, 2), written.toList())
        } finally { writer.close() }
        assertFalse(writer.send(byteArrayOf(3)))
    }

    @Test fun fullQueueClosesSlowPeerWithoutBlockingCaller() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val failures = AtomicInteger()
        val writer = BoundedFrameWriter(capacity = 1, write = { entered.countDown(); release.await() },
            closeTransport = { release.countDown() }, onFailure = { failures.incrementAndGet() })
        try {
            assertTrue(writer.send(byteArrayOf(1)))
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            assertTrue(writer.send(byteArrayOf(2)))
            assertFalse(writer.send(byteArrayOf(3)))
            assertEquals(1, failures.get())
        } finally { writer.close() }
    }

    @Test fun blockedWriteTimesOutAndRejectsPendingFlush() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val failed = CountDownLatch(1)
        val writer = BoundedFrameWriter(timeoutMillis = 100, write = { entered.countDown(); release.await() },
            closeTransport = { release.countDown() }, onFailure = { failed.countDown() })
        try {
            writer.send(byteArrayOf(1))
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            val flush = writer.flush()
            assertTrue(failed.await(2, TimeUnit.SECONDS))
            assertTrue(flush.isCompletedExceptionally)
            assertFalse(writer.send(byteArrayOf(2)))
        } finally { writer.close() }
    }
}
