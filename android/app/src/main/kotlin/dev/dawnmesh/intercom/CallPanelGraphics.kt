package dev.dawnmesh.intercom

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import kotlin.math.min

internal object CallPanelColors {
    val ink = Color.rgb(9, 24, 33)
    val card = Color.rgb(24, 45, 56)
    val white = Color.rgb(239, 250, 248)
    val secondary = Color.rgb(157, 181, 187)
    val mint = Color.rgb(130, 227, 200)
    val blue = Color.rgb(153, 206, 251)
    val muted = Color.rgb(211, 164, 152)
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
internal class CallPanelBackdrop(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var base: Shader? = null
    private var wash: Shader? = null
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w <= 0 || h <= 0) return
        base = LinearGradient(0f, 0f, w.toFloat(), h.toFloat(),
            intArrayOf(Color.rgb(13, 37, 46), CallPanelColors.ink), null, Shader.TileMode.CLAMP)
        wash = RadialGradient(w * .9f, h * .3f, w * .9f,
            Color.argb(40, 113, 225, 195), Color.TRANSPARENT, Shader.TileMode.CLAMP)
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
internal class CallTalkPad(context: Context) : View(context) {
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
    private val micIcon = CallPanelIcon("mic", CallPanelColors.mint)
    private val autoIcon = CallPanelIcon("wave", CallPanelColors.blue)
    private val mutedIcon = CallPanelIcon("mic_off", CallPanelColors.muted)
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
        val fill = when { muted -> Color.rgb(47, 47, 52); pressed -> Color.rgb(33, 100, 91); automatic -> Color.rgb(36, 63, 83); else -> Color.rgb(27, 66, 66) }
        fillShader = RadialGradient(cx, cy - radius / 2, radius * 1.6f,
            fill, CallPanelColors.card, Shader.TileMode.CLAMP)
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
        val accent = when { muted -> CallPanelColors.muted; automatic -> CallPanelColors.blue; else -> CallPanelColors.mint }
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
        paint.color = CallPanelColors.white
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
