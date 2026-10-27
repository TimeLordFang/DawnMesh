package dev.dawnmesh.intercom

import java.util.ArrayDeque
import java.util.concurrent.CompletableFuture

/** Ordered ATT fragments carry existing complete encrypted/PAKE wire frames.
 * Both endpoints use acknowledged writes/indications; reconnect clears partials.
 * One peer owns at most 64 x 518 outbound bytes and one partial inbound frame.
 */
internal class GattPacketPipe {
    private val outbound = ArrayDeque<ByteArray>()
    private var offset = 0
    private var inbound = byteArrayOf()
    private val flushers = mutableListOf<CompletableFuture<Void>>()
    val isEmpty: Boolean get() = outbound.isEmpty()

    fun enqueue(frame: ByteArray): Boolean {
        if (!valid(frame) || outbound.size >= 64) return false
        outbound.add(frame.copyOf())
        return true
    }
    fun peek(limit: Int): ByteArray? {
        val first = outbound.peek() ?: return null
        return first.copyOfRange(offset, minOf(first.size, offset + limit.coerceIn(20, 512)))
    }
    fun consume(count: Int) {
        val first = outbound.peek() ?: return
        require(count > 0 && offset + count <= first.size)
        offset += count
        if (offset == first.size) { outbound.remove(); offset = 0 }
        if (outbound.isEmpty()) { flushers.forEach { it.complete(null) }; flushers.clear() }
    }
    fun flush(): CompletableFuture<Void> {
        if (isEmpty) return CompletableFuture.completedFuture(null)
        return CompletableFuture<Void>().also { flushers.add(it) }
    }
    fun receive(fragment: ByteArray): List<ByteArray> {
        require(fragment.isNotEmpty() && fragment.size <= 512)
        inbound += fragment
        val frames = mutableListOf<ByteArray>()
        while (inbound.size >= 6) {
            require((inbound[0].toInt() and 255) in 9..11)
            val length = ((inbound[4].toInt() and 255) shl 8) or (inbound[5].toInt() and 255)
            require(length <= 512)
            if (inbound.size < 6 + length) break
            frames.add(inbound.copyOfRange(0, 6 + length))
            inbound = inbound.copyOfRange(6 + length, inbound.size)
        }
        require(inbound.size < 518)
        return frames
    }
    fun close() {
        outbound.clear(); inbound = byteArrayOf(); offset = 0
        flushers.forEach { it.completeExceptionally(IllegalStateException("GATT link closed")) }
        flushers.clear()
    }
    companion object {
        fun valid(frame: ByteArray): Boolean = frame.size in 6..518 &&
            (frame[0].toInt() and 255) in 9..11 &&
            6 + (((frame[4].toInt() and 255) shl 8) or (frame[5].toInt() and 255)) == frame.size
    }
}
