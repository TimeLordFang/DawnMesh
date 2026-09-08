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
    private val write: (ByteArray) -> Unit,
    private val closeTransport: () -> Unit,
    private val onFailure: (Throwable) -> Unit,
) : AutoCloseable {
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
                    is Job.Frame -> {
                        val deadline = timer.schedule(
                            { fail(IOException("Peer write timed out")) },
                            timeoutMillis, TimeUnit.MILLISECONDS,
                        )
                        try { write(job.bytes) } finally { deadline.cancel(false) }
                    }
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
