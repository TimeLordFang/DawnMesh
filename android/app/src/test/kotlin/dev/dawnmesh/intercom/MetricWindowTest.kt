package dev.dawnmesh.intercom

import org.junit.Assert.assertTrue
import org.junit.Test

class MetricWindowTest {
    @Test fun summaryUsesTheCurrentRollingWindow() {
        val metric = MetricWindow(capacity = 3)
        metric.add(1)
        metric.add(2)
        metric.add(100)
        metric.add(3)

        val summary = metric.summary()
        assertTrue(summary.contains("n=3/4"))
        assertTrue(summary.contains("avg=35us"))
        assertTrue(summary.contains("p50=3us"))
        assertTrue(summary.contains("max=100us"))
    }
}
