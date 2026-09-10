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

    @Test fun advancedParametersAreBoundedAndPublishedAtomically() {
        val base = AudioTuningParameters.defaults(AudioTuningProfile.BALANCED)
        val custom = AudioTuningParameters.fromMap(
            mapOf(
                "profile" to "balanced",
                "prebufferFrames" to 4,
                "maxAdaptiveFrames" to 1,
                "maxPlayoutQueueFrames" to 99,
                "l2capCoalesceMillis" to 35,
                "headsetBitrate" to 6_000,
                "dropStaleRealtime" to true,
                "maxRealtimeAgeMillis" to 40,
                "flushEveryWrite" to false,
            ),
            base,
        )

        assertEquals(4, custom.bluetoothPrebufferFrames)
        assertEquals(4, custom.bluetoothMaxAdaptiveFrames)
        assertEquals(32, custom.maxPlayoutQueueFrames)
        assertEquals(32, custom.bluetoothMaxBufferFrames)

        BluetoothAudioCoexistence.setActive(true)
        BluetoothAudioCoexistence.setParameters(custom)
        assertEquals(35, BluetoothAudioCoexistence.l2capCoalesceMillis())
        assertEquals(40, BluetoothAudioCoexistence.maxRealtimeAgeMillis())
        assertTrue(BluetoothAudioCoexistence.dropStaleRealtime())
        assertTrue(!BluetoothAudioCoexistence.flushEveryWrite())
    }
}
