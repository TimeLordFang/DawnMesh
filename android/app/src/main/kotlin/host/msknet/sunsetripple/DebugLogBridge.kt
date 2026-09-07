package host.msknet.sunsetripple

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log as AndroidLog
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/** Routes native diagnostics to the in-app log page only when the user enables it. */
internal object DebugLogBridge : EventChannel.StreamHandler {
    private const val CHANNEL = "dev.dawnmesh.intercom/debug_logs"
    private const val PREFERENCES = "dawnmesh_profile"
    private const val ENABLED_KEY = "debug_logging_enabled"

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var enabled = false
    @Volatile private var sink: EventChannel.EventSink? = null
    private var channel: EventChannel? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        enabled = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(ENABLED_KEY, false)
        channel?.setStreamHandler(null)
        channel = EventChannel(messenger, CHANNEL).also { it.setStreamHandler(this) }
    }

    fun detach() {
        channel?.setStreamHandler(null)
        channel = null
        sink = null
    }

    fun setEnabled(value: Boolean) {
        enabled = value
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun d(tag: String, message: String) = write("debug", tag, message)
    fun i(tag: String, message: String) = write("info", tag, message)
    fun w(tag: String, message: String, error: Throwable? = null) =
        write("warn", tag, message, error)
    fun e(tag: String, message: String, error: Throwable? = null) =
        write("error", tag, message, error)

    private fun write(level: String, tag: String, message: String, error: Throwable? = null) {
        if (!enabled) return
        when (level) {
            "debug" -> AndroidLog.d(tag, message)
            "info" -> AndroidLog.i(tag, message)
            "warn" -> AndroidLog.w(tag, message, error)
            else -> AndroidLog.e(tag, message, error)
        }
        val payload = mapOf(
            "level" to level,
            "tag" to tag,
            "message" to message,
            "error" to error?.let { "${it.javaClass.simpleName}: ${it.message.orEmpty()}" },
        )
        main.post {
            if (enabled) sink?.success(payload)
        }
    }
}

/** Drop-in facade for existing native diagnostics. */
internal object Log {
    fun d(tag: String, message: String) = DebugLogBridge.d(tag, message)
    fun i(tag: String, message: String) = DebugLogBridge.i(tag, message)
    fun w(tag: String, message: String, error: Throwable? = null) =
        DebugLogBridge.w(tag, message, error)
    fun e(tag: String, message: String, error: Throwable? = null) =
        DebugLogBridge.e(tag, message, error)
}
