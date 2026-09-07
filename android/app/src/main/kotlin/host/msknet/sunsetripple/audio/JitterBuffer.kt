package host.msknet.sunsetripple.audio

sealed class PollResult {
    object NotReady : PollResult()
    object Lost : PollResult()
    class Packet(val data: ByteArray) : PollResult()
}

/** Bounded playout with re-priming after starvation and a short-utterance deadline. */
class JitterBuffer(
    private val prebufferFrames: Int = 3,
    private val maxBuffer: Int = 24,
    private val ordered: Boolean = false,
    private val clockMs: () -> Long = { System.nanoTime() / 1_000_000 },
) {
    init { require(prebufferFrames in 1..maxBuffer) }
    private val buf = sortedMapOf<Long, ByteArray>()
    private var highestSeen = -1L
    private var next = -1L
    private var arrivalSeq = 0L
    private var started = false
    private var target = prebufferFrames
    private var firstBufferedAt = 0L
    private var lastArrivalAt = Long.MIN_VALUE
    private var underruns = 0
    private var dropped = 0

    @Synchronized
    fun put(seq16: Int, payload: ByteArray) {
        val now = clockMs()
        // Silence is intentional in both PTT and voice-activated modes.
        if (lastArrivalAt != Long.MIN_VALUE && now - lastArrivalAt > 500) target = prebufferFrames
        lastArrivalAt = now
        // TCP and BLE L2CAP deliver ordered, reliable audio. The wire sequence is
        // shared with chat/heartbeat/control frames; its gaps are NOT lost audio.
        val seq = if (ordered) arrivalSeq++ else unwrap(seq16)
        if (next >= 0 && seq < next) { dropped++; return }
        if (buf.isEmpty()) firstBufferedAt = now
        buf[seq] = payload
        while (buf.size > maxBuffer) { buf.remove(buf.firstKey()); dropped++ }
        if (started && next < buf.firstKey() && buf.size == maxBuffer) next = buf.firstKey()
    }

    @Synchronized
    fun poll(): PollResult {
        if (buf.isEmpty()) {
            if (started) {
                started = false
                underruns++
                target = (target + 2).coerceAtMost(minOf(maxBuffer, 12))
            }
            return PollResult.NotReady
        }
        if (!started) {
            // Do not strand a very short utterance that never fills the target.
            if (buf.size < target && clockMs() - firstBufferedAt < target * 20L) {
                return PollResult.NotReady
            }
            started = true
            next = buf.firstKey()
        }
        if (buf.firstKey() - next > maxBuffer) next = buf.firstKey()
        val head = buf.remove(next)
        next++
        return if (head == null) PollResult.Lost else PollResult.Packet(head)
    }

    @Synchronized
    fun reset() {
        buf.clear(); highestSeen = -1L; next = -1L; arrivalSeq = 0L
        started = false; target = prebufferFrames; lastArrivalAt = Long.MIN_VALUE
        underruns = 0; dropped = 0
    }
    @Synchronized fun hasStarted(): Boolean = started
    @Synchronized fun pendingCount(): Int = buf.size
    @Synchronized fun diagnostics(): String = "queued=${buf.size}, target=$target, rebuffer=$underruns, dropped=$dropped"

    private fun unwrap(seq16: Int): Long {
        if (highestSeen < 0) { highestSeen = seq16.toLong(); return highestSeen }
        val delta = ((seq16 - (highestSeen and 0xffff).toInt() + 0x8000) and 0xffff) - 0x8000
        val value = highestSeen + delta
        if (value > highestSeen) highestSeen = value
        return value
    }
}
