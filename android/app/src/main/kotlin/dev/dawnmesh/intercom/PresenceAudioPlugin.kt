package dev.dawnmesh.intercom

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Local-only room notices on the existing communication route. No audio focus takeover. */
class PresenceAudioPlugin(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "dev.dawnmesh.intercom/presence_audio")
    private val handler = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ready = false
    private var disposed = false
    private var pending: Notice? = null
    private var tone: ToneGenerator? = null
    private var lastSpoken = 0L
    private data class Notice(val kind: String, val name: String, val created: Long)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "announce" -> {
                    val kind = call.argument<String>("kind")
                    if (kind != "offline" && kind != "left") {
                        result.error("INVALID_NOTICE", "未知语音提示", null)
                    } else {
                        val name = call.argument<String>("name").orEmpty().substringBefore('#')
                            .filterNot { it.isISOControl() }.trim().take(24)
                        pending = Notice(kind, name, SystemClock.elapsedRealtime())
                        if (tts == null) initialize() else if (ready) playPending()
                        result.success(null)
                    }
                }
                "stop" -> { stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun initialize() {
        tts = TextToSpeech(context) { status ->
            handler.post {
                if (disposed) return@post
                ready = true
                if (status == TextToSpeech.SUCCESS) {
                    tts?.setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    tts?.setSpeechRate(1.05f)
                }
                playPending()
            }
        }
    }

    private fun playPending() {
        val notice = pending ?: return
        pending = null
        val now = SystemClock.elapsedRealtime()
        if (now - notice.created > 5000 || now - lastSpoken < 1500) return
        lastSpoken = now
        try {
            val engine = tts
            val offline = engine?.voices.orEmpty().filter {
                !it.isNetworkConnectionRequired && !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
            }
            val voice = offline.firstOrNull { it.locale.language == "zh" }
                ?: offline.firstOrNull { it.locale.language == "en" }
            if (engine == null || voice == null) { beep(); return }
            engine.voice = voice
            val chinese = voice.locale.language == "zh"
            val name = notice.name.ifEmpty { if (chinese) "一位成员" else "A member" }
            val text = if (chinese) "$name${if (notice.kind == "left") "已退出房间" else "已掉线"}"
                else "$name ${if (notice.kind == "left") "left the room" else "disconnected"}"
            val options = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 0.7f) }
            if (engine.speak(text, TextToSpeech.QUEUE_FLUSH, options, "presence-$now") == TextToSpeech.ERROR) beep()
        } catch (_: Exception) { beep() }
    }

    private fun beep() {
        try {
            tone?.release()
            val next = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 45)
            tone = next
            next.startTone(ToneGenerator.TONE_PROP_BEEP2, 250)
            handler.postDelayed({ if (tone === next) { tone = null; next.release() } }, 400)
        } catch (_: Exception) { /* Devices without a usable output still show the offline badge. */ }
    }

    private fun stop() {
        pending = null
        tts?.stop()
        tone?.release(); tone = null
        lastSpoken = 0
    }
    fun dispose() {
        disposed = true
        stop()
        tts?.shutdown(); tts = null
        handler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
    }
}
