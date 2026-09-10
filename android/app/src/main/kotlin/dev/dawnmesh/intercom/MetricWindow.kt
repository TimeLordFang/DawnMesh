package dev.dawnmesh.intercom

/** Fixed-size rolling sample window used by the in-app diagnostics page. */
internal class MetricWindow(private val capacity: Int = 512) {
    private val values = LongArray(capacity)
    private var next = 0
    private var size = 0
    private var totalCount = 0L

    init { require(capacity > 0) }

    @Synchronized
    fun add(value: Long) {
        val safe = value.coerceAtLeast(0)
        values[next] = safe
        next = (next + 1) % capacity
        if (size < capacity) size++
        totalCount++
    }

    @Synchronized
    fun summary(unit: String = "us"): String {
        if (size == 0) return "n=0"
        val sorted = values.copyOf(size).sortedArray()
        fun percentile(percent: Double): Long {
            val index = ((sorted.size - 1) * percent).toInt().coerceIn(0, sorted.lastIndex)
            return sorted[index]
        }
        return "n=${sorted.size}/$totalCount,avg=${sorted.sum() / sorted.size}$unit," +
            "p50=${percentile(0.50)}$unit,p95=${percentile(0.95)}$unit," +
            "p99=${percentile(0.99)}$unit,max=${sorted.last()}$unit"
    }
}
