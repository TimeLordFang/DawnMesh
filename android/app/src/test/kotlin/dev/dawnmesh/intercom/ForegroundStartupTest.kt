package dev.dawnmesh.intercom
import org.junit.Assert.*
import org.junit.Test
class ForegroundStartupTest {
    @Test fun waitsForActualStartupAndCompletesAllCallersOnce() {
        val state = ForegroundStartup()
        val outcomes = mutableListOf<String?>()
        val ticket = state.request { outcomes.add(it) }!!
        assertNull(state.request { outcomes.add(it) })
        assertTrue(outcomes.isEmpty())
        assertFalse(state.running)
        assertTrue(state.complete(ticket, null))
        assertTrue(state.running)
        assertEquals(listOf(null, null), outcomes)
        assertFalse(state.complete(ticket, "late error"))
    }
    @Test fun failureCanRetryAndCancelledCompletionCannotStartNewSession() {
        val state = ForegroundStartup()
        val outcomes = mutableListOf<String?>()
        val first = state.request { outcomes.add(it) }!!
        state.complete(first, "permission")
        assertFalse(state.running)
        val second = state.request { outcomes.add(it) }!!
        state.stop("left")
        val third = state.request { outcomes.add(it) }!!
        assertFalse(state.stopIfCurrent(second, "old service destroyed"))
        assertFalse(state.complete(second, null))
        assertTrue(state.isPending(third))
        state.complete(third, null)
        assertEquals(listOf("permission", "left", null), outcomes)
        assertTrue(state.stopIfCurrent(third, "service destroyed"))
        assertFalse(state.running)
    }
}
