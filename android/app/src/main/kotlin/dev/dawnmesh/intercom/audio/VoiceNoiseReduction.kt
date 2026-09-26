package dev.dawnmesh.intercom.audio

import android.content.Context
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import java.nio.ByteBuffer

/** Shared setting for Wi-Fi, Bluetooth and LiveKit microphone uplinks. */
class VoiceNoiseReduction(context: Context) : AutoCloseable {
    private val preferences = context.getSharedPreferences("dawnmesh_profile", Context.MODE_PRIVATE)
    @Volatile var level: Int = preferences.getInt("noise_reduction_level", 1).coerceIn(0, 2)
        private set
    private var adapter: AudioProcessingAdapter? = null
    private val processor = InternetProcessor { level }

    fun setLevel(value: Int) {
        require(value in 0..2)
        preferences.edit().putInt("noise_reduction_level", value).apply()
        level = value
    }

    fun startInternet(): Boolean {
        val next = FlutterWebRTCPlugin.sharedSingleton?.audioProcessingController?.capturePostProcessing
            ?: return false
        if (adapter === next) return true
        stopInternet()
        next.addProcessor(processor)
        adapter = next
        return true
    }

    fun stopInternet() {
        // removeProcessor waits for any in-flight processing under the SDK lock.
        adapter?.removeProcessor(processor)
        adapter = null
        processor.close()
    }
    override fun close() = stopInternet()

    private class InternetProcessor(val level: () -> Int) : AudioProcessingAdapter.ExternalAudioFrameProcessing {
        private var rate = 0
        private var channels = 1
        private var denoiser: VoiceDenoiser? = null
        override fun initialize(sampleRateHz: Int, numChannels: Int) {
            channels = numChannels
            reset(sampleRateHz)
        }
        override fun reset(newRate: Int) {
            close()
            rate = newRate
            if (channels == 1 && (newRate == 16000 || newRate == 32000 || newRate == 48000)) {
                denoiser = VoiceDenoiser(newRate)
            }
        }
        override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
            // The pinned WebRTC SDK exposes a full-band mono FloatS16 buffer,
            // 10 ms per callback. Attaching after initialize is supported too.
            if (channels != 1 || !buffer.isDirect || (numFrames != 160 && numFrames != 320 && numFrames != 480)) return
            if (rate != numFrames * 100 || denoiser == null) reset(numFrames * 100)
            denoiser?.process(buffer, numFrames, level())
        }
        fun close() { denoiser?.close(); denoiser = null; rate = 0 }
    }
}
