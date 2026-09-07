package host.msknet.sunsetripple

import android.content.Context
import java.lang.ref.WeakReference
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** App-owned controls only. No exported receiver or room secrets on lock screen. */
internal object CallControlBridge {
    private var channel: MethodChannel? = null
    private var context: WeakReference<Context>? = null
    var active = false; private set
    var bluetooth = false; private set
    var automatic = false; private set
    var pressed = false; private set
    var muted = false; private set
    var observer: (() -> Unit)? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        this.context = WeakReference(context.applicationContext)
        channel = MethodChannel(messenger, "dev.dawnmesh.intercom/call_controls").apply {
            setMethodCallHandler { call, result ->
                if (call.method != "update") { result.notImplemented(); return@setMethodCallHandler }
                active = call.argument<Boolean>("active") == true
                bluetooth = call.argument<Boolean>("bluetooth") == true
                automatic = call.argument<Boolean>("automatic") == true
                muted = call.argument<Boolean>("muted") == true
                pressed = active && !automatic && !muted && call.argument<Boolean>("pressed") == true
                notifyState()
                result.success(null)
            }
        }
    }

    fun command(method: String, value: Boolean) {
        if (!active || channel == null) return
        if (method == "ptt") {
            if (value && (automatic || muted)) return
            pressed = value
        }
        channel?.invokeMethod(method, value)
        notifyState()
    }

    private fun notifyState() {
        observer?.invoke()
        context?.get()?.let { IntercomForegroundService.refreshNotification(it) }
    }

    fun detach() {
        active = false
        pressed = false
        observer?.invoke()
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }
}
