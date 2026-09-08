package dev.dawnmesh.intercom

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import kotlin.math.min

/** Restricted controls above keyguard. Room secrets and the normal app stay hidden. */
class LockScreenTalkActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var roomType: TextView
    private lateinit var talk: CallTalkPad
    private lateinit var modes: LinearLayout
    private lateinit var holdMode: LinearLayout
    private lateinit var autoMode: LinearLayout
    private lateinit var mute: LinearLayout
    private lateinit var muteTitle: TextView
    private lateinit var muteHint: TextView
    private lateinit var muteBadge: TextView
    private val gesture = HoldToTalkGesture { held ->
        CallControlBridge.command("ptt", held)
        if (::talk.isInitialized) {
            talk.performHapticFeedback(if (!held && Build.VERSION.SDK_INT >= 27)
                HapticFeedbackConstants.VIRTUAL_KEY_RELEASE else HapticFeedbackConstants.VIRTUAL_KEY)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) setShowWhenLocked(true)
        else @Suppress("DEPRECATION") window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        @Suppress("DEPRECATION")
        window.statusBarColor = CallPanelColors.ink
        @Suppress("DEPRECATION")
        window.navigationBarColor = CallPanelColors.ink
        // Never dismiss the keyguard or turn the screen on automatically.
        val root = FrameLayout(this)
        root.addView(CallPanelBackdrop(this), FrameLayout.LayoutParams(-1, -1))
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            clipToPadding = false
        }
        root.addView(scroll, FrameLayout.LayoutParams(-1, -1))
        root.setOnApplyWindowInsetsListener { _, insets ->
            @Suppress("DEPRECATION")
            scroll.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
                insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            insets
        }
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(20), dp(24), dp(24))
        }
        val frame = FrameLayout(this)
        scroll.addView(frame, FrameLayout.LayoutParams(-1, -2))
        // Constrain cards on wide displays; the scroll view handles short screens.
        val availableWidth = resources.displayMetrics.widthPixels
        frame.addView(column, FrameLayout.LayoutParams(min(availableWidth, dp(480)), -2, Gravity.CENTER))
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        val heading = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        heading.addView(label("锁屏通话", 12f, CallPanelColors.secondary))
        heading.addView(label(getString(R.string.app_name), 28f, CallPanelColors.white, true).apply {
            setPadding(0, dp(5), 0, 0)
        })
        header.addView(heading, LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(ImageButton(this).apply {
            setImageDrawable(CallPanelIcon("close", CallPanelColors.white))
            setPadding(dp(12), dp(12), dp(12), dp(12))
            contentDescription = "收起通话面板"
            background = ripple(CallPanelColors.card, 24f)
            setOnClickListener { gesture.cancel(); finish() }
        }, LinearLayout.LayoutParams(dp(48), dp(48)))
        column.addView(header, LinearLayout.LayoutParams(-1, -2))
        roomType = label("", 12f, CallPanelColors.secondary).apply {
            setPadding(dp(12), dp(7), dp(12), dp(7))
            background = shape(CallPanelColors.card, 16f)
        }
        column.addView(roomType, LinearLayout.LayoutParams(-2, -2).apply {
            gravity = Gravity.START; topMargin = dp(16); bottomMargin = dp(26)
        })
        modes = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), dp(4), dp(4), dp(4))
            background = shape(CallPanelColors.card, 24f)
            elevation = dp(3).toFloat()
        }
        holdMode = modeButton("按住对讲", false)
        autoMode = modeButton("自动通话", true)
        modes.addView(holdMode, LinearLayout.LayoutParams(0, -2, 1f).apply {
            rightMargin = dp(3)
        })
        modes.addView(autoMode, LinearLayout.LayoutParams(0, -2, 1f))
        column.addView(modes, LinearLayout.LayoutParams(-1, -2))
        talk = CallTalkPad(this).apply {
            isFocusable = true
            isClickable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            setOnClickListener {
                // Accessibility clicks never latch a microphone without a release.
                announceForAccessibility("请按住圆环说话，也可以选择自动通话")
            }
            setOnTouchListener { view, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        view.parent.requestDisallowInterceptTouchEvent(true)
                        gesture.down(event.getPointerId(0), insidePad(event.x, event.y) &&
                            !CallControlBridge.automatic && !CallControlBridge.muted)
                    }
                    MotionEvent.ACTION_MOVE -> {
                        for (i in 0 until event.pointerCount) {
                            gesture.move(event.getPointerId(i), insidePad(event.getX(i), event.getY(i)))
                        }
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                        gesture.up(event.getPointerId(event.actionIndex))
                        if (event.actionMasked == MotionEvent.ACTION_UP) {
                            view.parent.requestDisallowInterceptTouchEvent(false)
                            view.performClick()
                        }
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        gesture.cancel()
                        view.parent.requestDisallowInterceptTouchEvent(false)
                    }
                }
                true
            }
        }
        val padSize = min(dp(272), availableWidth - dp(64)).coerceAtLeast(dp(180))
        column.addView(talk, LinearLayout.LayoutParams(padSize, padSize).apply { topMargin = dp(18) })
        status = label("", 14f, CallPanelColors.secondary).apply {
            gravity = Gravity.CENTER
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        column.addView(status, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(28) })
        mute = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(80)
            setPadding(dp(18), dp(16), dp(18), dp(16))
            background = ripple(CallPanelColors.card, 24f)
            isFocusable = true
            setOnClickListener {
                gesture.cancel()
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                CallControlBridge.command("mute", !CallControlBridge.muted)
            }
        }
        val micLabels = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        muteTitle = label("", 16f, CallPanelColors.white, true)
        muteHint = label("", 12f, CallPanelColors.secondary).apply { setPadding(0, dp(5), 0, 0) }
        micLabels.addView(muteTitle)
        micLabels.addView(muteHint)
        mute.addView(micLabels, LinearLayout.LayoutParams(0, -2, 1f))
        muteBadge = label("", 12f, CallPanelColors.ink, true).apply {
            setPadding(dp(12), dp(8), dp(12), dp(8))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        mute.addView(muteBadge, LinearLayout.LayoutParams(-2, -2).apply { leftMargin = dp(8) })
        column.addView(mute, LinearLayout.LayoutParams(-1, -2))
        column.addView(label("收起面板，通话继续", 12f, CallPanelColors.secondary).apply {
            gravity = Gravity.CENTER
            compoundDrawablePadding = dp(7)
            setCompoundDrawables(CallPanelIcon("lock", CallPanelColors.secondary).apply {
                setBounds(0, 0, dp(14), dp(14))
            }, null, null, null)
        }, LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(24) })
        setContentView(root)
        root.requestApplyInsets()
    }

    private fun insidePad(x: Float, y: Float): Boolean {
        val dx = x - talk.width / 2f
        val dy = y - talk.height / 2f
        val radius = min(talk.width, talk.height) / 2f - dp(12)
        return dx * dx + dy * dy <= radius * radius
    }

    private fun modeButton(title: String, automatic: Boolean) = LinearLayout(this).apply {
        gravity = Gravity.CENTER
        minimumHeight = dp(64)
        setPadding(dp(8), dp(9), dp(8), dp(9))
        isFocusable = true
        isClickable = true
        val icon = ImageView(this@LockScreenTalkActivity).apply {
            setImageDrawable(CallPanelIcon(if (automatic) "wave" else "mic", CallPanelColors.secondary))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        addView(icon, LinearLayout.LayoutParams(dp(22), dp(22)).apply { rightMargin = dp(9) })
        val copy = LinearLayout(this@LockScreenTalkActivity).apply {
            orientation = LinearLayout.VERTICAL
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        copy.addView(label(title, 14f, CallPanelColors.secondary, true))
        copy.addView(label(if (automatic) "声音触发" else "按住发送", 11f, CallPanelColors.secondary).apply {
            setPadding(0, dp(2), 0, 0)
            alpha = .78f
        })
        addView(copy, LinearLayout.LayoutParams(-2, -2))
        contentDescription = "$title，${if (automatic) "声音触发" else "按住发送"}"
        accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfo) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = "android.widget.RadioButton"
                info.isCheckable = true
                info.isChecked = host.isSelected
            }
        }
        setOnClickListener {
            gesture.cancel()
            performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
            CallControlBridge.command("automatic", automatic)
        }
    }

    private fun label(value: String, size: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        text = value; textSize = size; setTextColor(color)
        typeface = Typeface.create(if (bold) "sans-serif-medium" else "sans-serif", Typeface.NORMAL)
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun shape(color: Int, radius: Float) = GradientDrawable().apply {
        setColor(color); cornerRadius = radius * resources.displayMetrics.density
    }
    private fun ripple(color: Int, radius: Float) = RippleDrawable(
        ColorStateList.valueOf(Color.argb(38, 255, 255, 255)), shape(color, radius), shape(Color.WHITE, radius))

    override fun onResume() {
        super.onResume()
        CallControlBridge.observer = ::render
        render()
    }

    private fun render() {
        if (!CallControlBridge.active) { gesture.cancel(); finish(); return }
        val auto = CallControlBridge.automatic
        val muted = CallControlBridge.muted
        talk.update(auto, muted, CallControlBridge.pressed)
        talk.isEnabled = !auto && !muted
        talk.contentDescription = when {
            muted -> "麦克风已静音，仍可收听"
            auto -> "自动通话，有声音时发送"
            CallControlBridge.pressed -> "正在发送，松手停止"
            else -> "按住圆环说话，松开收听，滑出圆环取消发送"
        }
        status.text = when {
            muted -> "麦克风已静音 · 仍可收听房间声音"
            auto -> "开口即可发送声音，无需按住"
            CallControlBridge.pressed -> "正在发送 · 滑出圆环也可停止"
            else -> "按住圆环发言 · 松开恢复收听"
        }
        roomType.text = if (CallControlBridge.bluetooth) "蓝牙房间" else "Wi-Fi 房间"
        modes.visibility = View.VISIBLE
        for ((button, selected) in listOf(holdMode to !auto, autoMode to auto)) {
            button.isSelected = selected
            button.background = ripple(if (selected) {
                if (auto) CallPanelColors.blue else CallPanelColors.mint
            } else Color.TRANSPARENT, 20f)
            val icon = button.getChildAt(0) as ImageView
            val copy = button.getChildAt(1) as LinearLayout
            val foreground = if (selected) CallPanelColors.ink else CallPanelColors.secondary
            icon.setImageDrawable(CallPanelIcon(if (button === autoMode) "wave" else "mic", foreground))
            (copy.getChildAt(0) as TextView).setTextColor(foreground)
            (copy.getChildAt(1) as TextView).setTextColor(foreground)
            button.animate()
                .scaleX(if (selected) 1f else .98f)
                .scaleY(if (selected) 1f else .98f)
                .alpha(if (selected) 1f else .82f)
                .setDuration(180)
                .start()
        }
        muteTitle.text = if (muted) "麦克风已静音" else "麦克风已开启"
        muteHint.text = if (muted) "点按恢复发言" else "点按静音，保持收听"
        muteBadge.text = if (muted) "静音" else "开启"
        muteBadge.background = shape(if (muted) CallPanelColors.muted else CallPanelColors.mint, 12f)
        mute.contentDescription = if (muted) "麦克风已静音，点按恢复发言" else "麦克风已开启，点按静音"
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) gesture.cancel()
    }

    override fun onPause() {
        CallControlBridge.observer = null
        gesture.cancel()
        CallControlBridge.command("ptt", false)
        talk.stopAnimations()
        super.onPause()
    }
}
