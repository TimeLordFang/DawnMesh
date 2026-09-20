package dev.dawnmesh.intercom

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.Configuration
import android.graphics.*
import android.graphics.drawable.Drawable
import android.view.View
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
    val mint: Int,
    val blue: Int,
    val muted: Int,
    val padMuted: Int,
    val padPressed: Int,
    val padAutomatic: Int,
    val padHold: Int,
)

internal object CallPanelColors {
    val night = CallPanelPalette(
        isNight = true,
        backgroundStart = Color.rgb(13, 37, 46),
        backgroundEnd = Color.rgb(9, 24, 33),
        glow = Color.argb(40, 113, 225, 195),
        ink = Color.rgb(9, 24, 33),
        card = Color.rgb(24, 45, 56),
        white = Color.rgb(239, 250, 248),
        secondary = Color.rgb(157, 181, 187),
        mint = Color.rgb(130, 227, 200),
        blue = Color.rgb(153, 206, 251),
        muted = Color.rgb(211, 164, 152),
        padMuted = Color.rgb(47, 47, 52),
        padPressed = Color.rgb(33, 100, 91),
        padAutomatic = Color.rgb(36, 63, 83),
        padHold = Color.rgb(27, 66, 66),
    )
    val day = CallPanelPalette(
        isNight = false,
        backgroundStart = Color.rgb(255, 249, 241),
        backgroundEnd = Color.rgb(244, 241, 236),
        glow = Color.argb(66, 243, 220, 170),
        ink = Color.rgb(57, 40, 50),
        card = Color.rgb(252, 250, 247),
        white = Color.rgb(42, 34, 37),
        secondary = Color.rgb(110, 98, 94),
        mint = Color.rgb(191, 225, 207),
        blue = Color.rgb(198, 216, 240),
        muted = Color.rgb(239, 186, 174),
        padMuted = Color.rgb(247, 229, 224),
        padPressed = Color.rgb(176, 91, 93),
        padAutomatic = Color.rgb(222, 232, 246),
        padHold = Color.rgb(244, 221, 213),
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
        canvas.save()
        canvas.translate(bounds.left.toFloat(), bounds.top.toFloat())
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
        canvas.restore()
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
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var automatic = false
    private var muted = false
    private var pressed = false
    private var pulse = 0f
    private var pulseAnimator: ValueAnimator? = null
    private val density = resources.displayMetrics.density
    private val scaledDensity = resources.displayMetrics.scaledDensity
    private val titleTypeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    private val subtitleTypeface = Typeface.create("sans-serif", Typeface.NORMAL)
    private val micIcon = CallPanelIcon("mic", palette.mint)
    private val autoIcon = CallPanelIcon("wave", palette.blue)
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
        val accent = when { muted -> palette.muted; automatic -> palette.blue; else -> palette.mint }
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
