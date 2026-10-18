package dev.dawnmesh.nearbyprobe

/** Scope asynchronous send failures to the still-unacknowledged request. */
internal class ProbeLedger {
    private data class Request(val run: Int, val sequence: Int)
    private val requests = mutableMapOf<Long, Request>()
    fun sent(id: Long, run: Int, sequence: Int) { requests[id] = Request(run, sequence) }
    fun settled(id: Long) { requests.remove(id) }
    fun acknowledged(run: Int, sequence: Int) {
        requests.entries.removeAll { it.value == Request(run, sequence) }
    }
    fun failed(id: Long, run: Int, sequence: Int): Boolean =
        requests.remove(id) == Request(run, sequence)
    fun clear() { requests.clear() }
}

/** Every publish/discovery/stop invalidates all previous SDK callback closures. */
internal class ProbeEpoch {
    private var current = 0L
    fun advance(): Long { current++; return current }
    fun accepts(epoch: Long): Boolean = current == epoch
}
