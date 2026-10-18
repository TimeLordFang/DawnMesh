package dev.dawnmesh.nearbyprobe

import org.junit.Assert.*
import org.junit.Test

class ProbeLedgerTest {
    @Test fun previousRunFailureDoesNotAbortNewRun() {
        val ledger = ProbeLedger()
        ledger.sent(10, 1, 0)
        ledger.clear()
        ledger.sent(20, 2, 0)
        assertFalse(ledger.failed(10, 2, 0))
        assertTrue(ledger.failed(20, 2, 0))
    }
    @Test fun echoWinsOverLateFailureOfAcknowledgedSend() {
        val ledger = ProbeLedger()
        ledger.sent(10, 1, 0)
        ledger.acknowledged(1, 0)
        ledger.sent(20, 1, 1)
        assertFalse(ledger.failed(10, 1, 1))
        assertTrue(ledger.failed(20, 1, 1))
    }
    @Test fun incomingAndEchoFailuresCannotAbortOwnRequest() {
        val ledger = ProbeLedger()
        ledger.sent(10, 1, 0)
        assertFalse(ledger.failed(99, 1, 0))
        assertTrue(ledger.failed(10, 1, 0))
        assertFalse(ledger.failed(10, 1, 0))
    }
    @Test fun settledSendCannotFailAgain() {
        val ledger = ProbeLedger()
        ledger.sent(10, 1, 0); ledger.settled(10)
        assertFalse(ledger.failed(10, 1, 0))
    }
    @Test fun stoppedOrRestartedSessionRejectsAllOldCallbacks() {
        val epochs = ProbeEpoch()
        val publishing = epochs.advance()
        assertTrue(epochs.accepts(publishing))
        val stopped = epochs.advance()
        assertFalse(epochs.accepts(publishing))
        val discovering = epochs.advance()
        assertFalse(epochs.accepts(stopped))
        assertTrue(epochs.accepts(discovering))
    }
}
