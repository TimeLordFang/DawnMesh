package dev.dawnmesh.intercom

import java.io.IOException
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** One bounded writer per physical peer. Socket I/O never runs on the UI thread. */
internal class BoundedFrameWriter(
    capacity: Int = 64,
    private val timeoutMillis: Long = 5_000,
    private val coalesceMillis: Long = 0,
    private val maxBatchBytes: Int = 4_096,
    private val write: (ByteArray) -> Unit,
    private val closeTransport: () -> Unit,
    private val onFailure: (Throwable) -> Unit,
) : AutoCloseable {
    init {
        require(coalesceMillis >= 0)
        require(maxBatchBytes > 0)
    }

    private sealed class Job {
        class Frame(val bytes: ByteArray) : Job()
        class Barrier(val completion: CompletableFuture<Unit>) : Job()
    }

    companion object {
        private val timer = Executors.newSingleThreadScheduledExecutor { task ->
            Thread(task, "dawnmesh-write-timeout").apply { isDaemon = true }
        }
    }

    private val open = AtomicBoolean(true)
    private val jobs = ArrayBlockingQueue<Job>(capacity)
    private val worker = Thread({ run() }, "dawnmesh-peer-writer").apply {
        isDaemon = true
        priority = Thread.MAX_PRIORITY
        start()
    }

    @Synchronized
    fun send(bytes: ByteArray): Boolean {
        if (!open.get()) return false
        if (jobs.offer(Job.Frame(bytes.copyOf()))) return true
        fail(IOException("Peer send queue full"))
        return false
    }

    @Synchronized
    fun flush(): CompletableFuture<Unit> {
        val done = CompletableFuture<Unit>()
        if (!open.get() || !jobs.offer(Job.Barrier(done))) {
            done.completeExceptionally(IOException("Peer writer is closed or full"))
        }
        return done
    }

    private fun run() {
        try {
            while (open.get()) {
                when (val job = jobs.take()) {
                    is Job.Barrier -> job.completion.complete(Unit)
                    is Job.Frame -> writeCoalesced(job)
                }
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        } catch (e: Exception) {
            fail(e)
        } finally {
            rejectBarriers()
        }
    }

    /**
     * L2CAP 是有帧头的有序字节流，多个协议帧可以安全地放进同一次 socket
     * write。短暂等待下一帧可显著减少与耳机实时音频争用控制器的发送次数。
     * Barrier 会立即结束等待，因此 leave/flush 不会被额外拖延。
     */
    private fun writeCoalesced(first: Job.Frame) {
        val chunks = ArrayList<ByteArray>()
        chunks.add(first.bytes)
        var total = first.bytes.size
        var barrier: Job.Barrier? = null
        val endAt = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(coalesceMillis)

        while (coalesceMillis > 0 && total < maxBatchBytes) {
            val remaining = endAt - System.nanoTime()
            if (remaining <= 0) break
            when (val next = jobs.poll(remaining, TimeUnit.NANOSECONDS) ?: break) {
                is Job.Barrier -> {
                    barrier = next
                    break
                }
                is Job.Frame -> {
                    if (total + next.bytes.size > maxBatchBytes) {
                        writeWithTimeout(join(chunks, total))
                        chunks.clear()
                        total = 0
                    }
                    chunks.add(next.bytes)
                    total += next.bytes.size
                }
            }
        }

        if (total > 0) writeWithTimeout(join(chunks, total))
        barrier?.completion?.complete(Unit)
    }

    private fun join(chunks: List<ByteArray>, size: Int): ByteArray {
        if (chunks.size == 1) return chunks[0]
        val output = ByteArray(size)
        var offset = 0
        for (chunk in chunks) {
            chunk.copyInto(output, offset)
            offset += chunk.size
        }
        return output
    }

    private fun writeWithTimeout(bytes: ByteArray) {
        val deadline = timer.schedule(
            { fail(IOException("Peer write timed out")) },
            timeoutMillis, TimeUnit.MILLISECONDS,
        )
        try { write(bytes) } finally { deadline.cancel(false) }
    }

    private fun rejectBarriers() {
        while (true) {
            val job = jobs.poll() ?: break
            if (job is Job.Barrier) job.completion.completeExceptionally(IOException("Peer closed"))
        }
    }

    @Synchronized
    private fun fail(error: Throwable) {
        if (!open.compareAndSet(true, false)) return
        try { closeTransport() } finally {
            worker.interrupt()
            rejectBarriers()
            onFailure(error)
        }
    }

    @Synchronized
    override fun close() {
        if (!open.compareAndSet(true, false)) return
        try { closeTransport() } finally {
            worker.interrupt()
            rejectBarriers()
        }
    }
}
