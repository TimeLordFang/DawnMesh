package dev.dawnmesh.intercom

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import io.github.jaredmdobson.concentus.OpusDecoder
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Bounded, explicit playback with a separate decoder; never opens AudioRecord. */
internal class VoiceNotePlayback(private val handler: Handler) {
    private var track: AudioTrack? = null
    private var result: MethodChannel.Result? = null
    private val generation = AtomicInteger()
    private var timeout: Runnable? = null
    // One decoder and at most one waiting request; a new play replaces the old.
    private val decoderWorker = ThreadPoolExecutor(1, 1, 10, TimeUnit.SECONDS,
        ArrayBlockingQueue(1), { job -> Thread(job, "dawn-voice-note") },
        ThreadPoolExecutor.DiscardOldestPolicy()).apply { allowCoreThreadTimeOut(true) }

    fun play(data: ByteArray, inCall: Boolean, completion: MethodChannel.Result) {
        stop(); result = completion
        val token = generation.get()
        decoderWorker.execute {
            try {
                val pcm = decode(data) { generation.get() == token }
                if (generation.get() != token) return@execute
                val player = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(if (inCall) AudioAttributes.USAGE_VOICE_COMMUNICATION else AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    .setAudioFormat(AudioFormat.Builder().setSampleRate(16000)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setTransferMode(AudioTrack.MODE_STATIC).setBufferSizeInBytes(pcm.size * 2).build()
                if (player.state != AudioTrack.STATE_INITIALIZED || player.write(pcm, 0, pcm.size) != pcm.size) {
                    player.release(); throw IllegalStateException("Voice note output unavailable")
                }
                handler.post {
                    if (generation.get() != token) { player.release(); return@post }
                    try {
                    track = player
                    player.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
                        override fun onMarkerReached(source: AudioTrack) { if (track === source) finish(true) }
                        override fun onPeriodicNotification(source: AudioTrack) { }
                    }, handler)
                    player.notificationMarkerPosition = pcm.size
                    timeout = Runnable { if (track === player) finish(true) }.also {
                        handler.postDelayed(it, pcm.size * 1000L / 16000 + 1_000)
                    }
                    player.play()
                    } catch (_: Exception) { fail(token) }
                }
            } catch (_: Exception) {
                handler.post { fail(token) }
            }
        }
    }
    private fun fail(token: Int) {
        if (generation.get() != token) return
        val done = result; result = null
        stop()
        done?.error("NOTE_PLAYBACK_FAILED", "语音留言无法播放", null)
    }
    fun stop() = finish(false)
    private fun finish(completed: Boolean) {
        generation.incrementAndGet()
        decoderWorker.queue.clear()
        timeout?.let(handler::removeCallbacks); timeout = null
        val previous = track; track = null
        try { previous?.stop() } catch (_: IllegalStateException) { }
        previous?.release()
        val done = result; result = null; done?.success(completed)
    }
    companion object {
        fun decode(data: ByteArray, active: () -> Boolean = { true }): ShortArray {
            require(data.size in 3..(96 * 1024) && data[0].toInt() == 1)
            val count = ((data[1].toInt() and 255) shl 8) or (data[2].toInt() and 255)
            require(count in 1..750)
            val decoder = OpusDecoder(16000, 1)
            val pcm = ShortArray(count * 320)
            var offset = 3
            repeat(count) { index ->
                check(active()) { "Playback cancelled" }
                require(offset + 2 <= data.size)
                val length = ((data[offset].toInt() and 255) shl 8) or (data[offset + 1].toInt() and 255)
                offset += 2
                require(length in 1..512 && offset + length <= data.size)
                require(decoder.decode(data, offset, length, pcm, index * 320, 320, false) == 320)
                offset += length
            }
            require(offset == data.size)
            return pcm
        }
    }
}
