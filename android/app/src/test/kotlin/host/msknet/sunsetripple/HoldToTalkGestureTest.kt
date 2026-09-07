package host.msknet.sunsetripple

import org.junit.Assert.assertEquals
import org.junit.Test

class HoldToTalkGestureTest {
    @Test fun dragOutsideStopsAndReentryDoesNotRestart() {
        val states = mutableListOf<Boolean>()
        val gesture = HoldToTalkGesture { states.add(it) }
        gesture.down(7, true)
        gesture.move(7, true)
        gesture.move(7, false)
        gesture.move(7, true)
        gesture.up(7)
        assertEquals(listOf(true, false), states)
        gesture.down(7, true)
        gesture.up(7)
        assertEquals(listOf(true, false, true, false), states)
    }
    @Test fun otherFingersCannotReleaseOrTakeOverThePrimaryHold() {
        val states = mutableListOf<Boolean>()
        val gesture = HoldToTalkGesture { states.add(it) }
        gesture.down(1, true)
        gesture.down(2, true)
        gesture.move(2, false)
        gesture.up(2)
        assertEquals(listOf(true), states)
        gesture.up(1)
        assertEquals(listOf(true, false), states)
    }
    @Test fun cancellationReleasesOnlyOnceAndAllowsANewHold() {
        val states = mutableListOf<Boolean>()
        val gesture = HoldToTalkGesture { states.add(it) }
        gesture.down(0, true)
        gesture.cancel()
        gesture.cancel()
        gesture.up(0)
        assertEquals(listOf(true, false), states)
        gesture.down(0, true)
        gesture.cancel()
        assertEquals(listOf(true, false, true, false), states)
    }
    @Test fun disabledOrOutsidePressCannotStartByMovingInside() {
        val states = mutableListOf<Boolean>()
        val gesture = HoldToTalkGesture { states.add(it) }
        gesture.down(0, false)
        gesture.move(0, true)
        gesture.down(1, true)
        gesture.up(0)
        gesture.cancel()
        assertEquals(emptyList<Boolean>(), states)
    }
}
