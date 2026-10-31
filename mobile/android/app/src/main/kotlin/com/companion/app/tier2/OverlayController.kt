package com.companion.app.tier2

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.companion.app.R

/**
 * Overlay drawn over other apps by the Accessibility Service (TYPE_ACCESSIBILITY_OVERLAY, no extra permission):
 *  - a non-touchable layer with a pulsing yellow highlight + arrow around the next button (Guide)
 *  - a touchable bar with "Companion is helping" and an always-visible STOP button
 */
class OverlayController(private val service: AccessibilityService) {
    private val wm = service.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var highlightView: HighlightView? = null
    private var bar: LinearLayout? = null
    private var hintView: TextView? = null

    fun showRunning(assist: Boolean, hint: String, onStop: () -> Unit) {
        hide()
        val hv = HighlightView(service)
        wm.addView(hv, WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ))
        highlightView = hv

        val layout = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#EE263238"))
            setPadding(32, 24, 32, 24)
        }
        val title = TextView(service).apply {
            text = service.getString(if (assist) R.string.tier2_assisting else R.string.tier2_guiding)
            setTextColor(Color.WHITE); textSize = 20f; typeface = Typeface.DEFAULT_BOLD
        }
        val hintTv = TextView(service).apply { text = hint; setTextColor(Color.parseColor("#FFC107")); textSize = 22f }
        val stop = Button(service).apply {
            text = service.getString(R.string.tier2_stop)
            textSize = 22f
            setBackgroundColor(Color.parseColor("#B71C1C")); setTextColor(Color.WHITE)
            minHeight = 160
            setOnClickListener { onStop() } // takes effect immediately (< 1 s)
        }
        layout.addView(title); layout.addView(hintTv); layout.addView(stop)
        wm.addView(layout, WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP })
        bar = layout
        hintView = hintTv
    }

    fun highlight(bounds: Rect, hint: String) {
        highlightView?.setTarget(bounds)
        updateHint(hint)
    }

    fun clearHighlight() = highlightView?.setTarget(null)

    fun updateHint(hint: String) {
        hintView?.text = hint
    }

    fun hide() {
        highlightView?.let { runCatching { wm.removeView(it) } }
        bar?.let { runCatching { wm.removeView(it) } }
        highlightView = null; bar = null; hintView = null
    }

    private class HighlightView(context: Context) : View(context) {
        private var target: Rect? = null
        private var phase = 0f
        private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = 14f; color = Color.parseColor("#FFC107")
        }
        private val arrow = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; color = Color.parseColor("#FFC107") }

        fun setTarget(r: Rect?) {
            target = r
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val r = target ?: return
            phase = (phase + 0.08f) % (2f * Math.PI.toFloat())
            val grow = 10f + 10f * kotlin.math.sin(phase)
            // The overlay window starts at the top of the screen; convert screen coordinates to view coordinates.
            val loc = IntArray(2).also { getLocationOnScreen(it) }
            val rf = RectF(r.left - grow - loc[0], r.top - grow - loc[1], r.right + grow - loc[0], r.bottom + grow - loc[1])
            canvas.drawRoundRect(rf, 32f, 32f, stroke)
            val cx = rf.centerX()
            val tipY = rf.top - 10f - grow
            val path = android.graphics.Path().apply {
                moveTo(cx, tipY); lineTo(cx - 40f, tipY - 70f); lineTo(cx + 40f, tipY - 70f); close()
            }
            canvas.drawPath(path, arrow)
            postInvalidateDelayed(40)
        }
    }
}
