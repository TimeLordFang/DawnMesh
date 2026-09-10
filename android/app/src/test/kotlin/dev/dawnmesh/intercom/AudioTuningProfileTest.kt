package dev.dawnmesh.intercom

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioTuningProfileTest {
    @Test fun wireNamesRoundTripAndUnknownFallsBackToBalanced() {
        for (profile in AudioTuningProfile.entries) {
            assertEquals(profile, AudioTuningProfile.fromWireName(profile.wireName))
        }
        assertEquals(AudioTuningProfile.BALANCED, AudioTuningProfile.fromWireName("unknown"))
        assertEquals(AudioTuningProfile.BALANCED, AudioTuningProfile.fromWireName(null))
    }

    @Test fun profilesTradeLatencyForBurstToleranceMonotonically() {
        val profiles = listOf(
            AudioTuningProfile.LOW_LATENCY,
            AudioTuningProfile.BALANCED,
            AudioTuningProfile.STABLE,
        )
        assertTrue(profiles.zipWithNext().all { (a, b) ->
            a.bluetoothPrebufferFrames < b.bluetoothPrebufferFrames &&
                a.bluetoothMaxAdaptiveFrames < b.bluetoothMaxAdaptiveFrames &&
                a.audioTrackBufferFrames < b.audioTrackBufferFrames &&
                a.l2capCoalesceMillis < b.l2capCoalesceMillis
        })
    }
}
