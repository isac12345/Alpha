package com.alphabubble

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView

object C {
    val BG = Color.parseColor("#161719")
    val CARD = Color.parseColor("#0E0F10")
    val FIELD = Color.parseColor("#08090A")
    val LINE = Color.parseColor("#17FFFFFF")
    val BTN_LINE = Color.parseColor("#26FFFFFF")
    val TX = Color.parseColor("#E9E8E3")
    val MU = Color.parseColor("#7D8186")
    val DARK = Color.parseColor("#0A0A0A")
    val OFF = Color.parseColor("#2A2C2F")
}

fun Context.dp(v: Int): Int = (v * resources.displayMetrics.density + 0.5f).toInt()

fun Context.shape(color: Int, radiusDp: Int, strokeColor: Int = 0, strokeDp: Int = 0): GradientDrawable {
    val g = GradientDrawable()
    g.setColor(color)
    g.cornerRadius = dp(radiusDp).toFloat()
    if (strokeDp > 0) g.setStroke(dp(strokeDp), strokeColor)
    return g
}

fun lp(w: Int, h: Int, weight: Float = 0f): LinearLayout.LayoutParams =
    LinearLayout.LayoutParams(w, h, weight)

const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT

fun Context.tv(text: String, sp: Float = 12f, color: Int = C.TX, bold: Boolean = false): TextView {
    val t = TextView(this)
    t.text = text
    t.textSize = sp
    t.setTextColor(color)
    t.typeface = if (bold) Typeface.create(Typeface.MONOSPACE, Typeface.BOLD) else Typeface.MONOSPACE
    return t
}

fun Context.label(text: String): TextView {
    val t = tv(text.uppercase(), 10f, C.MU)
    t.letterSpacing = 0.2f
    t.setPadding(0, 0, 0, dp(10))
    return t
}

fun Context.pillButton(text: String, filled: Boolean = false, onClick: () -> Unit): TextView {
    val t = tv(text.uppercase(), 11f, if (filled) C.DARK else C.TX, filled)
    t.letterSpacing = 0.14f
    t.gravity = Gravity.CENTER
    t.setPadding(dp(14), dp(13), dp(14), dp(13))
    t.background = if (filled) shape(C.TX, 30) else shape(0, 30, C.BTN_LINE, 1)
    t.setOnClickListener { onClick() }
    return t
}

fun Context.kv(k: String, v: String): Pair<LinearLayout, TextView> {
    val r = LinearLayout(this)
    r.orientation = LinearLayout.HORIZONTAL
    r.gravity = Gravity.CENTER_VERTICAL
    r.setPadding(0, dp(9), 0, dp(9))
    val a = tv(k, 12f, C.MU)
    val b = tv(v, 12f, C.TX)
    b.gravity = Gravity.END
    r.addView(a, lp(0, WRAP, 1f))
    r.addView(b, lp(WRAP, WRAP))
    return Pair(r, b)
}

fun Context.hairline(): View {
    val v = View(this)
    v.setBackgroundColor(C.LINE)
    v.layoutParams = lp(MATCH, 1)
    return v
}

fun Context.fieldBg() = shape(C.FIELD, 14, C.LINE, 1)

fun Context.styleSeek(s: SeekBar) {
    s.progressTintList = android.content.res.ColorStateList.valueOf(C.TX)
    s.thumbTintList = android.content.res.ColorStateList.valueOf(C.TX)
}

class Toggle(c: Context) : View(c) {
    var on: Boolean = false
        set(v) { field = v; invalidate() }
    var onChange: ((Boolean) -> Unit)? = null
    private val p = Paint(Paint.ANTI_ALIAS_FLAG)

    init {
        setOnClickListener {
            on = !on
            onChange?.invoke(on)
        }
    }

    override fun onMeasure(w: Int, h: Int) {
        setMeasuredDimension(context.dp(44), context.dp(24))
    }

    override fun onDraw(cv: Canvas) {
        val hh = height.toFloat()
        p.color = if (on) C.TX else C.OFF
        cv.drawRoundRect(0f, 0f, width.toFloat(), hh, hh / 2f, hh / 2f, p)
        p.color = if (on) C.DARK else C.MU
        val r = hh / 2f - context.dp(3)
        val cx = if (on) width - hh / 2f else hh / 2f
        cv.drawCircle(cx, hh / 2f, r, p)
    }
}

class Seg(c: Context, private val labels: List<String>, sel: Int, private val onPick: (Int) -> Unit) : LinearLayout(c) {
    private val items = ArrayList<TextView>()
    var selected: Int = sel
        private set

    init {
        orientation = HORIZONTAL
        background = c.shape(C.FIELD, 30)
        setPadding(c.dp(4), c.dp(4), c.dp(4), c.dp(4))
        for ((i, l) in labels.withIndex()) {
            val t = c.tv(l, 11f, C.MU)
            t.letterSpacing = 0.1f
            t.gravity = Gravity.CENTER
            t.setPadding(0, c.dp(11), 0, c.dp(11))
            t.setOnClickListener { select(i); onPick(i) }
            addView(t, lp(0, WRAP, 1f))
            items.add(t)
        }
        paint()
    }

    fun select(i: Int) {
        selected = i
        paint()
    }

    private fun paint() {
        for ((i, t) in items.withIndex()) {
            if (i == selected) {
                t.setTextColor(C.DARK)
                t.background = context.shape(C.TX, 26)
            } else {
                t.setTextColor(C.MU)
                t.background = null
            }
        }
    }
}
