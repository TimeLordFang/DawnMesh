package dev.dawnmesh.intercom

/** Main-thread state machine: completion means startForeground actually ran. */
internal class ForegroundStartup {
    private var generation = 0
    private var pending = false
    var running = false; private set
    private val callbacks = mutableListOf<(String?) -> Unit>()
    fun request(callback: (String?) -> Unit): Int? {
        if (running) { callback(null); return null }
        callbacks.add(callback)
        if (pending) return null
        pending = true
        return ++generation
    }
    fun isPending(ticket: Int) = pending && ticket == generation
    fun complete(ticket: Int, error: String?): Boolean {
        if (!isPending(ticket)) return false
        pending = false
        running = error == null
        val ready = callbacks.toList()
        callbacks.clear()
        ready.forEach { it(error) }
        return true
    }
    fun stopIfCurrent(ticket: Int, reason: String): Boolean {
        if (ticket != generation) return false
        stop(reason)
        return true
    }
    fun stop(reason: String) {
        ++generation
        pending = false
        running = false
        val ready = callbacks.toList()
        callbacks.clear()
        ready.forEach { it(reason) }
    }
}
