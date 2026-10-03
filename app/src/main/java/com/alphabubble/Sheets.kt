package com.alphabubble

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.text.Editable
import android.text.TextWatcher
import android.text.method.DigitsKeyListener
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView

class AppRow(val label: String, val pkg: String, val icon: Drawable?)

object AppCache {
    @Volatile var list: List<AppRow>? = null

    fun load(a: Activity): List<AppRow> {
        list?.let { return it }
        val pm = a.packageManager
        val rows = pm.getInstalledApplications(0)
            .filter { pm.getLaunchIntentForPackage(it.packageName) != null }
            .map {
                AppRow(
                    it.loadLabel(pm).toString(), it.packageName,
                    try { it.loadIcon(pm) } catch (_: Exception) { null }
                )
            }
            .sortedBy { it.label.lowercase() }
        list = rows
        return rows
    }

    fun iconFor(a: Activity, pkg: String): Drawable? =
        list?.firstOrNull { it.pkg == pkg }?.icon
            ?: try { a.packageManager.getApplicationIcon(pkg) } catch (_: Exception) { null }

    fun labelFor(a: Activity, pkg: String): String =
        list?.firstOrNull { it.pkg == pkg }?.label
            ?: try {
                a.packageManager.getApplicationLabel(a.packageManager.getApplicationInfo(pkg, 0)).toString()
            } catch (_: Exception) { pkg }
}

fun Activity.editField(hint: String): EditText {
    val e = EditText(this)
    e.hint = hint
    e.setHintTextColor(C.MU)
    e.setTextColor(C.TX)
    e.textSize = 12f
    e.typeface = android.graphics.Typeface.MONOSPACE
    e.isSingleLine = true
    e.background = fieldBg()
    e.setPadding(dp(14), dp(13), dp(14), dp(13))
    return e
}

/**
 * Sheet pilih aplikasi. games=true -> tampil pilihan profile + FPS + tombol ADD.
 * games=false -> tap aplikasi langsung memanggil onPick (dipakai Dexopt).
 */
fun Activity.showAppSheet(title: String, games: Boolean, onPick: (pkg: String, profile: String, fps: String) -> Unit) {
    val d = Dialog(this, android.R.style.Theme_DeviceDefault_Dialog_NoActionBar)
    val root = LinearLayout(this)
    root.orientation = LinearLayout.VERTICAL
    val bg = GradientDrawable()
    bg.setColor(C.BG)
    val r = dp(26).toFloat()
    bg.cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
    root.background = bg
    root.setPadding(dp(18), dp(18), dp(18), dp(18))

    val head = LinearLayout(this)
    head.gravity = Gravity.CENTER_VERTICAL
    val ht = tv(title.uppercase(), 13f, C.TX, true)
    ht.letterSpacing = 0.2f
    head.addView(ht, lp(0, WRAP, 1f))
    head.addView(pillButton("Close") { d.dismiss() }, lp(WRAP, WRAP))
    root.addView(head, lp(MATCH, WRAP))

    val search = editField("Cari aplikasi...")
    val sl = lp(MATCH, WRAP)
    sl.topMargin = dp(12)
    root.addView(search, sl)

    val lv = ListView(this)
    lv.divider = ColorDrawable(C.LINE)
    lv.dividerHeight = 1
    lv.setBackgroundColor(Color.TRANSPARENT)
    root.addView(lv, lp(MATCH, 0, 1f))

    var shown: List<AppRow> = emptyList()
    var all: List<AppRow> = emptyList()
    var selected = ""

    val selTv = tv("Pilih aplikasi di atas", 11f, C.MU)
    val seg = Seg(this, listOf("BATTERY", "BALANCED", "PERF"), 2) { }
    val fps = editField("FPS target (opsional, mis. 30,60,90)")
    fps.keyListener = DigitsKeyListener.getInstance("0123456789,")

    val adapter = object : BaseAdapter() {
        override fun getCount(): Int = shown.size
        override fun getItem(p: Int): Any = shown[p]
        override fun getItemId(p: Int): Long = p.toLong()
        override fun getView(p: Int, cv: View?, parent: ViewGroup): View {
            val a = shown[p]
            val row = LinearLayout(this@showAppSheet)
            row.gravity = Gravity.CENTER_VERTICAL
            row.setPadding(0, dp(10), 0, dp(10))
            val iv = ImageView(this@showAppSheet)
            iv.setImageDrawable(a.icon)
            row.addView(iv, lp(dp(38), dp(38)))
            val col = LinearLayout(this@showAppSheet)
            col.orientation = LinearLayout.VERTICAL
            col.setPadding(dp(12), 0, 0, 0)
            val n = tv(a.label, 12f, if (a.pkg == selected) C.TX else C.TX, true)
            val k = tv(a.pkg, 10f, C.MU)
            k.maxLines = 1
            k.ellipsize = android.text.TextUtils.TruncateAt.END
            col.addView(n)
            col.addView(k)
            row.addView(col, lp(0, WRAP, 1f))
            if (a.pkg == selected) row.background = shape(0x14FFFFFF, 12)
            return row
        }
    }
    lv.adapter = adapter

    fun filter(q: String) {
        val s = q.trim().lowercase()
        shown = if (s.isEmpty()) all else all.filter { it.label.lowercase().contains(s) || it.pkg.contains(s) }
        adapter.notifyDataSetChanged()
    }

    search.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) { }
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) { filter(s?.toString() ?: "") }
        override fun afterTextChanged(s: Editable?) { }
    })

    lv.setOnItemClickListener { _, _, p, _ ->
        val a = shown[p]
        if (games) {
            selected = a.pkg
            selTv.text = "Dipilih: " + a.pkg
            selTv.setTextColor(C.TX)
            adapter.notifyDataSetChanged()
        } else {
            d.dismiss()
            onPick(a.pkg, "", "")
        }
    }

    if (games) {
        val m = lp(MATCH, WRAP); m.topMargin = dp(12)
        root.addView(selTv, m)
        val m2 = lp(MATCH, WRAP); m2.topMargin = dp(10)
        root.addView(seg, m2)
        val m3 = lp(MATCH, WRAP); m3.topMargin = dp(10)
        root.addView(fps, m3)
        val m4 = lp(MATCH, WRAP); m4.topMargin = dp(10)
        root.addView(pillButton("Add", true) {
            val f = fps.text.toString().trim()
            if (selected.isEmpty()) {
                android.widget.Toast.makeText(this, "Pilih aplikasi dulu", android.widget.Toast.LENGTH_SHORT).show()
            } else if (f.isNotEmpty() && !Regex("^[0-9]+(,[0-9]+)*$").matches(f)) {
                android.widget.Toast.makeText(this, "Format FPS salah (contoh 30,60,90)", android.widget.Toast.LENGTH_SHORT).show()
            } else {
                val prof = listOf("battery", "balanced", "performance")[seg.selected]
                d.dismiss()
                onPick(selected, prof, f)
            }
        }, m4)
    }

    d.setContentView(root)
    d.window?.let { w ->
        w.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        w.setGravity(Gravity.BOTTOM)
        w.setLayout(WindowManager.LayoutParams.MATCH_PARENT, (resources.displayMetrics.heightPixels * 0.85f).toInt())
        w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    }
    d.show()

    Sh.bg {
        val rows = AppCache.load(this)
        Sh.ui.post {
            all = rows
            shown = rows
            adapter.notifyDataSetChanged()
        }
    }
}
