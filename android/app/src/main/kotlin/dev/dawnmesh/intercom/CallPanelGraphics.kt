package dev.dawnmesh.intercom

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.Configuration
import android.graphics.*
import android.graphics.drawable.Drawable
import android.view.View
import androidx.core.graphics.withTranslation
import android.view.animation.AccelerateDecelerateInterpolator
import kotlin.math.min

internal data class CallPanelPalette(
    val isNight: Boolean,
    val backgroundStart: Int,
    val backgroundEnd: Int,
    val glow: Int,
    val ink: Int,
    val card: Int,
    val white: Int,
    val secondary: Int,
    val accent: Int,
    val secondaryAccent: Int,
    val muted: Int,
    val padMuted: Int,
    val padPressed: Int,
    val padAutomatic: Int,
    val padHold: Int,
)

internal object CallPanelColors {
    val night = CallPanelPalette(
        isNight = true,
        backgroundStart = Color.rgb(20, 30, 64),
        backgroundEnd = Color.rgb(8, 15, 41),
        glow = Color.argb(40, 255, 188, 112),
        ink = Color.rgb(8, 15, 57),
        card = Color.rgb(20, 30, 64),
        white = Color.rgb(255, 243, 226),
        secondary = Color.rgb(188, 195, 220),
        accent = Color.rgb(255, 188, 112),
        secondaryAccent = Color.rgb(255, 116, 70),
        muted = Color.rgb(255, 139, 155),
        padMuted = Color.rgb(48, 31, 54),
        padPressed = Color.rgb(119, 51, 20),
        padAutomatic = Color.rgb(32, 43, 88),
        padHold = Color.rgb(39, 40, 70),
    )
    val day = CallPanelPalette(
        isNight = false,
        backgroundStart = Color.rgb(255, 248, 239),
        backgroundEnd = Color.rgb(255, 243, 220),
        glow = Color.argb(66, 255, 213, 135),
        ink = Color.rgb(23, 33, 63),
        card = Color.WHITE,
        white = Color.rgb(23, 33, 63),
        secondary = Color.rgb(88, 97, 122),
        accent = Color.rgb(166, 62, 31),
        secondaryAccent = Color.rgb(32, 43, 88),
        muted = Color.rgb(174, 49, 72),
        padMuted = Color.rgb(255, 232, 227),
        padPressed = Color.rgb(255, 188, 112),
        padAutomatic = Color.rgb(225, 230, 246),
        padHold = Color.rgb(255, 234, 207),
    )

    fun resolve(context: Context): CallPanelPalette {
        val mode = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return if (mode == Configuration.UI_MODE_NIGHT_YES) night else day
    }
}

/** Small vector icons drawn at any density, without a font or image dependency. */
internal class CallPanelIcon(private val kind: String, private var tint: Int) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.8f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    override fun draw(canvas: Canvas) {
        canvas.withTranslation(bounds.left.toFloat(), bounds.top.toFloat()) {
            canvas.scale(bounds.width() / 24f, bounds.height() / 24f)
            paint.color = tint
            when (kind) {
                "close" -> {
                    canvas.drawLine(7f, 10f, 12f, 15f, paint)
                    canvas.drawLine(12f, 15f, 17f, 10f, paint)
                }
                "lock" -> {
                    canvas.drawRoundRect(6f, 10f, 18f, 21f, 3f, 3f, paint)
                    canvas.drawArc(8f, 2f, 16f, 15f, 180f, 180f, false, paint)
                    canvas.drawLine(12f, 14f, 12f, 17f, paint)
                }
                "wave" -> {
                    for (i in 0..4) {
                        val x = 4f + i * 4f
                        val h = when (i) { 2 -> 16f; 1, 3 -> 10f; else -> 4f }
                        canvas.drawLine(x, 12 - h / 2, x, 12 + h / 2, paint)
                    }
                }
                else -> {
                    canvas.drawRoundRect(9f, 2f, 15f, 14f, 3f, 3f, paint)
                    canvas.drawArc(5f, 5f, 19f, 18f, 0f, 180f, false, paint)
                    canvas.drawLine(5f, 10f, 5f, 11.5f, paint)
                    canvas.drawLine(19f, 10f, 19f, 11.5f, paint)
                    canvas.drawLine(12f, 18f, 12f, 22f, paint)
                    canvas.drawLine(8f, 22f, 16f, 22f, paint)
                    if (kind == "mic_off") {
                        canvas.drawLine(3f, 3f, 21f, 21f, paint)
                    }
                }
            }
        }
    }
    override fun setAlpha(alpha: Int) { paint.alpha = alpha }
    override fun setColorFilter(filter: ColorFilter?) { paint.colorFilter = filter }
    @Deprecated("Drawable opacity is not used")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

/** Static atmospheric background; no animation or redraw loop while idle. */
internal class CallPanelBackdrop(
    context: Context,
    private val palette: CallPanelPalette,
) : View(context) {
    constructor(context: Context) : this(context, CallPanelColors.resolve(context))

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var base: Shader? = null
    private var wash: Shader? = null
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w <= 0 || h <= 0) return
        base = LinearGradient(0f, 0f, w.toFloat(), h.toFloat(),
            intArrayOf(palette.backgroundStart, palette.backgroundEnd), null, Shader.TileMode.CLAMP)
        wash = RadialGradient(w * .9f, h * .3f, w * .9f,
            palette.glow, Color.TRANSPARENT, Shader.TileMode.CLAMP)
    }
    override fun onDraw(canvas: Canvas) {
        paint.shader = base
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        paint.shader = wash
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        paint.shader = null
    }
}

/** Circular PTT/voice status surface. Animation runs only during a visible hold. */
internal class CallTalkPad(
    context: Context,
    private val palette: CallPanelPalette,
) : View(context) {
    constructor(context: Context) : this(context, CallPanelColors.resolve(context))

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    // ACTION_UP and accessibility actions share the registered click handler.
    override fun performClick(): Boolean = super.performClick()

    private var automatic = false
    private var muted = false
    private var pressed = false
    private var pulse = 0f
    private var pulseAnimator: ValueAnimator? = null
    private val density = resources.displayMetrics.density
    private val scaledDensity = resources.displayMetrics.scaledDensity
    private val titleTypeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    private val subtitleTypeface = Typeface.create("sans-serif", Typeface.NORMAL)
    private val micIcon = CallPanelIcon("mic", palette.accent)
    private val autoIcon = CallPanelIcon("wave", palette.secondaryAccent)
    private val mutedIcon = CallPanelIcon("mic_off", palette.muted)
    private var fillShader: Shader? = null

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        refreshFill()
    }

    private fun refreshFill() {
        val cx = width / 2f
        val cy = height / 2f
        val radius = min(cx, cy) - 12 * density
        if (radius <= 0) return
        val fill = when {
            muted -> palette.padMuted
            pressed -> palette.padPressed
            automatic -> palette.padAutomatic
            else -> palette.padHold
        }
        fillShader = RadialGradient(cx, cy - radius / 2, radius * 1.6f,
            fill, palette.card, Shader.TileMode.CLAMP)
    }


    fun update(automatic: Boolean, muted: Boolean, pressed: Boolean) {
        val changed = this.automatic != automatic || this.muted != muted || this.pressed != pressed
        this.automatic = automatic
        this.muted = muted
        this.pressed = pressed
        if (changed) {
            refreshFill()
            animate().scaleX(if (pressed) .97f else 1f).scaleY(if (pressed) .97f else 1f).setDuration(140).start()
            if (pressed) startPulse() else stopPulse()
            invalidate()
        }
    }

    private fun startPulse() {
        if (pulseAnimator != null) return
        pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1100
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { pulse = it.animatedValue as Float; invalidate() }
            start()
        }
    }

    fun stopAnimations() {
        stopPulse()
        animate().cancel()
        scaleX = 1f
        scaleY = 1f
    }

    private fun stopPulse() {
        pulseAnimator?.cancel()
        pulseAnimator = null
        pulse = 0f
    }

    override fun onDetachedFromWindow() {
        stopAnimations()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val radius = min(cx, cy) - 12 * density
        val accent = when { muted -> palette.muted; automatic -> palette.secondaryAccent; else -> palette.accent }
        paint.shader = null
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = density
        paint.color = Color.argb(40, Color.red(accent), Color.green(accent), Color.blue(accent))
        canvas.drawCircle(cx, cy, radius, paint)
        canvas.drawCircle(cx, cy, radius - 9 * density, paint)
        if (pressed) {
            paint.strokeWidth = (2 + pulse * 2) * density
            paint.alpha = (90 + pulse * 80).toInt()
            canvas.drawCircle(cx, cy, radius - 3 * density, paint)
        }
        paint.alpha = 255
        paint.style = Paint.Style.FILL
        paint.shader = fillShader
        canvas.drawCircle(cx, cy, radius - 17 * density, paint)
        paint.shader = null
        val icon = if (muted) mutedIcon else if (automatic) autoIcon else micIcon
        val iconHalf = (23 * density).toInt()
        val iconY = (cy - 30 * density).toInt()
        icon.setBounds(cx.toInt() - iconHalf, iconY - iconHalf, cx.toInt() + iconHalf, iconY + iconHalf)
        icon.draw(canvas)
        paint.color = palette.white
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = titleTypeface
        paint.textSize = 22 * scaledDensity.coerceAtMost(density * 1.4f)
        canvas.drawText(when { muted -> "已静音"; pressed -> "松手结束"; automatic -> "自动通话"; else -> "按住说话" }, cx, cy + 29 * density, paint)
        paint.textSize = 12 * scaledDensity.coerceAtMost(density * 1.4f)
        paint.color = accent
        paint.typeface = subtitleTypeface
        canvas.drawText(when { muted -> "接收保持开启"; pressed -> "正在发送"; automatic -> "有声音时发送"; else -> "松开即可收听" }, cx, cy + 55 * density, paint)
    }
}
