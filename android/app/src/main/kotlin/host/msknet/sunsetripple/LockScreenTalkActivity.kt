package host.msknet.sunsetripple

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.graphics.Color
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** A restricted call control surface above keyguard; it never dismisses it. */
class LockScreenTalkActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var talk: Button
    private lateinit var mode: Button
    private lateinit var mute: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) setShowWhenLocked(true)
        else @Suppress("DEPRECATION") window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        // Do not requestDismissKeyguard, turnScreenOn, or expose the normal app.
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(32, 32, 32, 32)
            setBackgroundColor(Color.rgb(25, 35, 50))
        }
        layout.addView(TextView(this).apply {
            text = getString(R.string.app_name) + " · 房间通话"
            textSize = 24f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        })
        status = TextView(this).apply {
            textSize = 18f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 32)
        }
        layout.addView(status)
        talk = Button(this).apply {
            textSize = 24f
            minHeight = (180 * resources.displayMetrics.density).toInt()
            setOnTouchListener { view, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> CallControlBridge.command("ptt", true)
                    MotionEvent.ACTION_UP -> {
                        CallControlBridge.command("ptt", false)
                        view.performClick()
                    }
                    MotionEvent.ACTION_CANCEL -> CallControlBridge.command("ptt", false)
                }
                true
            }
            setOnClickListener { /* Touch release performs the accessibility click. */ }
        }
        layout.addView(talk, LinearLayout.LayoutParams(-1, -2))
        mode = Button(this).apply {
            setOnClickListener { CallControlBridge.command("automatic", !CallControlBridge.automatic) }
        }
        layout.addView(mode, LinearLayout.LayoutParams(-1, -2))
        mute = Button(this).apply {
            setOnClickListener { CallControlBridge.command("mute", !CallControlBridge.muted) }
        }
        layout.addView(mute, LinearLayout.LayoutParams(-1, -2))
        layout.addView(Button(this).apply {
            text = "返回锁屏"
            setOnClickListener { finish() }
        }, LinearLayout.LayoutParams(-1, -2))
        setContentView(layout)
    }

    override fun onResume() {
        super.onResume()
        CallControlBridge.observer = ::render
        render()
    }

    private fun render() {
        if (!CallControlBridge.active) { finish(); return }
        val auto = CallControlBridge.automatic
        status.text = when {
            CallControlBridge.muted -> "已静音 · 仍可收听"
            auto -> "自动通话 · 有声音时发送"
            CallControlBridge.pressed -> "正在发送 · 松手停止"
            else -> "按住下方按钮说话，松开收听"
        }
        talk.text = if (CallControlBridge.pressed) "松手停止" else "按住对讲"
        talk.isEnabled = !auto && !CallControlBridge.muted
        mode.visibility = if (CallControlBridge.bluetooth) android.view.View.VISIBLE else android.view.View.GONE
        mode.text = if (auto) "切换为按住对讲" else "切换为自动通话"
        mute.text = if (CallControlBridge.muted) "取消静音" else "静音"
    }

    override fun onPause() {
        // A lost pointer, another activity or the power button must never latch PTT.
        CallControlBridge.observer = null
        CallControlBridge.command("ptt", false)
        super.onPause()
    }
}
