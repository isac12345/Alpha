package com.alphabubble

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Outline
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import java.io.File
import kotlin.math.max

class MainActivity : Activity() {
    private lateinit var prefs: SharedPreferences
    private lateinit var bgImg: ImageView
    private lateinit var scrim: View
    private lateinit var scroll: ScrollView
    private lateinit var content: LinearLayout
    private val navBtns = ArrayList<TextView>()
    private val cards = ArrayList<View>()
    private var tab = 0
    private var sub = 0
    private var resumed = false

    // dash
    private var tTemp: TextView? = null
    private var tFas: TextView? = null
    private var tSess: TextView? = null
    private var renderInfo: Alpha.RenderInfo? = null
    private var renderSel = ""

    // tools
    private var disp: Alpha.Disp? = null
    private val resList = listOf(60, 70, 80, 90, 100)
    private var resIdx = 2

    private val pollR = object : Runnable {
        override fun run() {
            if (resumed && tab == 0) refreshStatus()
            Sh.ui.postDelayed(this, 5000L)
        }
    }

    // ---------------------------------------------------------------- lifecycle
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = BubbleService.prefs(this)

        val root = FrameLayout(this)
        root.setBackgroundColor(C.BG)
        bgImg = ImageView(this)
        scrim = View(this)
        scrim.setBackgroundColor(Color.parseColor("#99000000"))
        scrim.visibility = View.GONE
        scroll = ScrollView(this)
        scroll.isVerticalScrollBarEnabled = false
        content = LinearLayout(this)
        content.orientation = LinearLayout.VERTICAL
        content.setPadding(dp(14), dp(14), dp(14), dp(100))
        scroll.addView(content, FrameLayout.LayoutParams(MATCH, WRAP))

        val nav = LinearLayout(this)
        nav.background = shape(Color.parseColor("#222326"), 34)
        nav.setPadding(dp(5), dp(5), dp(5), dp(5))
        val names = listOf("DASH", "GAMES", "CUSTOM", "TOOLS")
        for ((i, n) in names.withIndex()) {
            val b = tv(n, 11f, C.MU)
            b.letterSpacing = 0.14f
            b.gravity = Gravity.CENTER
            b.setPadding(0, dp(13), 0, dp(13))
            b.setOnClickListener {
                tab = i
                sub = 0
                build()
                scroll.scrollTo(0, 0)
            }
            nav.addView(b, lp(0, WRAP, 1f))
            navBtns.add(b)
        }

        root.addView(bgImg, FrameLayout.LayoutParams(MATCH, MATCH))
        root.addView(scrim, FrameLayout.LayoutParams(MATCH, MATCH))
        root.addView(scroll, FrameLayout.LayoutParams(MATCH, MATCH))
        val nlp = FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM)
        nlp.setMargins(dp(14), 0, dp(14), dp(12))
        root.addView(nav, nlp)
        setContentView(root)

        applyBg()
        build()
        initAsync()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        Sh.ui.removeCallbacks(pollR)
        Sh.ui.post(pollR)
        if (prefs.getBoolean("bubble_on", false) && Settings.canDrawOverlays(this)) {
            try { BubbleService.start(this) } catch (_: Exception) { }
        }
    }

    override fun onPause() {
        resumed = false
        Sh.ui.removeCallbacks(pollR)
        super.onPause()
    }

    private fun initAsync() {
        Sh.bg {
            Alpha.rootOk = false
            Alpha.mod = ""
            Alpha.ensure()
            Sh.ui.post { if (!isFinishing) build() }
        }
    }

    // ---------------------------------------------------------------- helpers
    private fun toast(s: String) {
        Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
    }

    private fun firstLine(r: Sh.Res): String {
        val s = (if (r.out.isNotEmpty()) r.out else r.err).lines().lastOrNull { it.isNotBlank() } ?: ""
        return if (s.length > 90) s.take(90) else s
    }

    private fun confirm(msg: String, ok: () -> Unit) {
        AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setMessage(msg)
            .setPositiveButton("OK") { _, _ -> ok() }
            .setNegativeButton("Batal", null)
            .show()
    }

    private fun cardBg(): GradientDrawable {
        val trans = prefs.getInt("card_trans", 0)
        val a = 255 - (255 * trans / 100)
        return shape(Color.argb(a, 14, 15, 16), 22, C.LINE, 1)
    }

    private fun addCard(): LinearLayout {
        val c = LinearLayout(this)
        c.orientation = LinearLayout.VERTICAL
        c.setPadding(dp(18), dp(16), dp(18), dp(16))
        c.background = cardBg()
        val l = lp(MATCH, WRAP)
        l.topMargin = dp(10)
        content.addView(c, l)
        cards.add(c)
        return c
    }

    private fun restyleCards() {
        for (c in cards) c.background = cardBg()
    }

    private fun LinearLayout.addTop(v: View, topDp: Int, w: Int = MATCH) {
        val l = lp(w, WRAP)
        l.topMargin = dp(topDp)
        addView(v, l)
    }

    private fun rowOf(vararg v: View): LinearLayout {
        val r = LinearLayout(this)
        r.gravity = Gravity.CENTER_VERTICAL
        for ((i, x) in v.withIndex()) {
            val l = lp(0, WRAP, 1f)
            if (i > 0) l.leftMargin = dp(10)
            r.addView(x, l)
        }
        return r
    }

    private fun toggleRow(text: String, on: Boolean, change: (Boolean) -> Unit): Pair<LinearLayout, Toggle> {
        val r = LinearLayout(this)
        r.gravity = Gravity.CENTER_VERTICAL
        r.setPadding(0, dp(10), 0, dp(10))
        r.addView(tv(text), lp(0, WRAP, 1f))
        val t = Toggle(this)
        t.on = on
        t.onChange = change
        r.addView(t, lp(WRAP, WRAP))
        return Pair(r, t)
    }

    // ---------------------------------------------------------------- shell
    private fun build() {
        cards.clear()
        content.removeAllViews()
        content.addView(banner(), lp(MATCH, dp(110)))
        when (tab) {
            0 -> buildDash()
            1 -> buildGames()
            2 -> buildCustom()
            else -> buildTools()
        }
        for ((i, b) in navBtns.withIndex()) {
            if (i == tab) {
                b.setTextColor(C.DARK)
                b.background = shape(C.TX, 28)
            } else {
                b.setTextColor(C.MU)
                b.background = null
            }
        }
    }

    private fun banner(): View {
        val f = FrameLayout(this)
        f.clipToOutline = true
        f.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, dp(20).toFloat())
            }
        }
        val iv = ImageView(this)
        iv.scaleType = ImageView.ScaleType.CENTER_CROP
        iv.setImageResource(R.drawable.banner)
        f.addView(iv, FrameLayout.LayoutParams(MATCH, MATCH))
        val shade = View(this)
        shade.background = GradientDrawable(
            GradientDrawable.Orientation.BOTTOM_TOP,
            intArrayOf(Color.parseColor("#BB000000"), Color.TRANSPARENT)
        )
        f.addView(shade, FrameLayout.LayoutParams(MATCH, MATCH))
        val box = LinearLayout(this)
        box.orientation = LinearLayout.VERTICAL
        val t1 = tv("ALPHA CONTROL", 19f, C.TX, true)
        t1.letterSpacing = 0.28f
        val t2 = tv("V2 · FUSION", 10f, Color.parseColor("#AAFFFFFF"))
        t2.letterSpacing = 0.2f
        box.addView(t1)
        box.addView(t2)
        val bl = FrameLayout.LayoutParams(WRAP, WRAP, Gravity.BOTTOM or Gravity.START)
        bl.setMargins(dp(16), 0, 0, dp(11))
        f.addView(box, bl)
        return f
    }

    // ---------------------------------------------------------------- DASH
    private fun buildDash() {
        if (!Alpha.ready) {
            val c = addCard()
            c.addView(label("Modul"))
            c.addView(tv(if (!Alpha.rootOk) "Root tidak tersedia atau ditolak." else "Modul Alpha Fusion tidak ditemukan.", 12f, C.MU))
            c.addTop(pillButton("Cari ulang") { initAsync() }, 12)
        }

        // bubble
        val bc = addCard()
        val br = toggleRow("Tampilkan bubble", prefs.getBoolean("bubble_on", false)) { on -> setBubble(on) }
        bc.addView(br.first)
        bubbleToggle = br.second

        // profil
        val pc = addCard()
        pc.addView(label("Current profile"))
        val big = tv("—", 28f, C.TX, true)
        pc.addView(big)
        val seg = Seg(this, listOf("DAILY", "BALANCED", "PERF"), 1) { i ->
            val p = listOf("battery", "balanced", "performance")[i]
            big.text = Alpha.profileTitle(p)
            Sh.bg {
                Alpha.ensure()
                val r = Alpha.applyProfile(p)
                val cur = Alpha.currentProfile()
                Sh.ui.post {
                    if (!r.ok) toast("Gagal: " + firstLine(r))
                    if (cur.isNotEmpty()) big.text = Alpha.profileTitle(cur)
                }
            }
        }
        pc.addTop(seg, 14)
        Sh.bg {
            val cur = Alpha.currentProfile()
            Sh.ui.post {
                if (cur.isNotEmpty()) {
                    big.text = Alpha.profileTitle(cur)
                    seg.select(listOf("battery", "balanced", "performance").indexOf(cur))
                }
            }
        }

        // status game
        val sc = addCard()
        sc.addView(label("Status game"))
        val k1 = kv("Suhu", "—"); val k2 = kv("Mode fas-rs", "—"); val k3 = kv("Sesi", "—")
        sc.addView(k1.first); sc.addView(hairline()); sc.addView(k2.first); sc.addView(hairline()); sc.addView(k3.first)
        tTemp = k1.second; tFas = k2.second; tSess = k3.second
        refreshStatus()

        // render
        val rc = addCard()
        rc.addView(label("Render"))
        val dd = tv("…  ▾", 12f, C.TX)
        dd.background = fieldBg()
        dd.setPadding(dp(14), dp(13), dp(14), dp(13))
        val applyBtn = pillButton("Apply", true) {
            val info = renderInfo
            if (info == null || renderSel.isEmpty()) {
                toast("Render belum terbaca")
            } else {
                Sh.bg {
                    val r = Alpha.renderSet(renderSel)
                    Sh.ui.post { toast(firstLine(r)) }
                }
            }
        }
        val rr = LinearLayout(this)
        rr.gravity = Gravity.CENTER_VERTICAL
        rr.addView(dd, lp(0, WRAP, 2f))
        val al = lp(0, WRAP, 1f); al.leftMargin = dp(10)
        rr.addView(applyBtn, al)
        rc.addView(rr)
        dd.setOnClickListener {
            val info = renderInfo
            if (info != null) {
                val labels = info.available.map { Alpha.renderLabel(it) }.toTypedArray()
                AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                    .setItems(labels) { _, i ->
                        renderSel = info.available[i]
                        dd.text = Alpha.renderLabel(renderSel) + "  ▾"
                    }.show()
            }
        }
        Sh.bg {
            val info = Alpha.renderGet()
            Sh.ui.post {
                renderInfo = info
                if (info != null) {
                    renderSel = info.current
                    dd.text = Alpha.renderLabel(info.current) + "  ▾"
                }
            }
        }
    }

    private var bubbleToggle: Toggle? = null

    private fun setBubble(on: Boolean) {
        if (on) {
            if (!Settings.canDrawOverlays(this)) {
                toast("Izinkan 'Tampil di atas aplikasi lain' dulu")
                bubbleToggle?.on = false
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                return
            }
            if (Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 5)
            }
            prefs.edit().putBoolean("bubble_on", true).putBoolean("bubble_visible", true).apply()
            BubbleService.start(this, BubbleService.ACT_SHOW)
        } else {
            prefs.edit().putBoolean("bubble_on", false).apply()
            BubbleService.stop(this)
        }
    }

    private fun refreshStatus() {
        if (tTemp == null) return
        Sh.bg {
            val s = Alpha.status()
            Sh.ui.post {
                tTemp?.text = s.temp
                tFas?.text = s.fasMode
                tSess?.text = s.session
            }
        }
    }

    // ---------------------------------------------------------------- GAMES
    private fun buildGames() {
        val c = addCard()
        val head = LinearLayout(this)
        head.gravity = Gravity.CENTER_VERTICAL
        val cnt = label("Game")
        cnt.setPadding(0, 0, 0, 0)
        head.addView(cnt, lp(0, WRAP, 1f))
        val plus = tv("+", 18f, C.DARK, true)
        plus.gravity = Gravity.CENTER
        plus.background = shape(C.TX, 30)
        plus.setOnClickListener { openAdd() }
        head.addView(plus, lp(dp(38), dp(38)))
        c.addView(head)

        val search: EditText = editField("Cari game...")
        c.addTop(search, 12)
        val box = LinearLayout(this)
        box.orientation = LinearLayout.VERTICAL
        c.addTop(box, 4)

        var data: List<Alpha.Game> = emptyList()
        fun show(q: String) {
            box.removeAllViews()
            val s = q.trim().lowercase()
            val list = if (s.isEmpty()) data else data.filter { it.pkg.lowercase().contains(s) }
            cnt.text = "GAME · " + data.size
            for (g in list) box.addView(gameRow(g))
            if (list.isEmpty()) box.addView(tv("Belum ada game terdaftar", 11f, C.MU).also { it.setPadding(0, dp(14), 0, 0) })
        }
        gamesReload = {
            Sh.bg {
                val l = Alpha.games()
                Sh.ui.post { data = l; show(search.text.toString()) }
            }
        }
        search.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c2: Int) { }
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c2: Int) { show(s?.toString() ?: "") }
            override fun afterTextChanged(s: android.text.Editable?) { }
        })
        gamesReload?.invoke()
    }

    private var gamesReload: (() -> Unit)? = null

    private fun gameRow(g: Alpha.Game): View {
        val r = LinearLayout(this)
        r.gravity = Gravity.CENTER_VERTICAL
        r.setPadding(0, dp(12), 0, dp(12))
        val iv = ImageView(this)
        iv.setImageDrawable(AppCache.iconFor(this, g.pkg))
        r.addView(iv, lp(dp(38), dp(38)))
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.setPadding(dp(12), 0, dp(8), 0)
        col.addView(tv(AppCache.labelFor(this, g.pkg), 12f, C.TX, true))
        val k = tv(g.pkg, 10f, C.MU)
        k.maxLines = 1
        k.ellipsize = TextUtils.TruncateAt.END
        col.addView(k)
        val tag = tv(g.profile.uppercase() + " · " + (if (g.fasrs) "FAS-RS" else "UPERF"), 9f, C.TX)
        tag.letterSpacing = 0.1f
        tag.background = shape(0, 10, Color.parseColor("#40FFFFFF"), 1)
        tag.setPadding(dp(8), dp(1), dp(8), dp(1))
        col.addTop(tag, 5, WRAP)
        r.addView(col, lp(0, WRAP, 1f))
        val rm = tv("HAPUS", 10f, C.MU)
        rm.letterSpacing = 0.12f
        rm.background = shape(0, 20, C.LINE, 1)
        rm.setPadding(dp(12), dp(8), dp(12), dp(8))
        rm.setOnClickListener {
            confirm("Hapus ${g.pkg}?") {
                Sh.bg {
                    val res = Alpha.removeGame(g.pkg)
                    Sh.ui.post { toast(firstLine(res)); gamesReload?.invoke() }
                }
            }
        }
        r.addView(rm, lp(WRAP, WRAP))
        return r
    }

    private fun openAdd() {
        showAppSheet("Games", true) { pkg, prof, fps ->
            toast("Menambahkan…")
            Sh.bg {
                val r = Alpha.addGame(pkg, prof, fps)
                Sh.ui.post { toast(firstLine(r)); gamesReload?.invoke() }
            }
        }
    }

    // ---------------------------------------------------------------- CUSTOM
    private fun buildCustom() {
        if (sub == 0) {
            val c = addCard()
            c.addView(pillButton("Background & banner  ›") { sub = 1; build() })
            c.addTop(pillButton("App icon  ›") { sub = 2; build() }, 10)
            c.addTop(pillButton("Floating bubble  ›") { sub = 3; build() }, 10)
            return
        }
        val c = addCard()
        val back = tv("‹ KEMBALI", 10f, C.TX)
        back.letterSpacing = 0.14f
        back.background = shape(0, 20, C.BTN_LINE, 1)
        back.setPadding(dp(14), dp(8), dp(14), dp(8))
        back.setOnClickListener { sub = 0; build() }
        c.addTop(back, 0, WRAP)
        when (sub) {
            1 -> {
                c.addTop(label("Background & banner"), 14)
                c.addView(pillButton("Pilih gambar") {
                    val i = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    i.type = "image/*"
                    i.addCategory(Intent.CATEGORY_OPENABLE)
                    startActivityForResult(i, 11)
                })
                c.addTop(pillButton("Banner default") {
                    File(filesDir, "bg.jpg").delete()
                    applyBg()
                    toast("Background direset")
                }, 10)
                c.addTop(tv("Transparansi kartu", 12f, C.MU), 14)
                val sb = SeekBar(this)
                styleSeek(sb)
                sb.max = 80
                sb.progress = prefs.getInt("card_trans", 0)
                sb.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(s: SeekBar?, p: Int, u: Boolean) {
                        prefs.edit().putInt("card_trans", p).apply()
                        restyleCards()
                    }
                    override fun onStartTrackingTouch(s: SeekBar?) { }
                    override fun onStopTrackingTouch(s: SeekBar?) { }
                })
                c.addTop(sb, 6)
                c.addTop(tv("Penyesuaian gambar", 12f, C.MU), 12)
                c.addTop(Seg(this, listOf("CROP", "FIT", "FILL"), prefs.getInt("bg_fit", 0)) { i ->
                    prefs.edit().putInt("bg_fit", i).apply()
                    applyBg()
                }, 8)
            }
            2 -> {
                c.addTop(label("App icon"), 14)
                val r = LinearLayout(this)
                r.gravity = Gravity.CENTER_VERTICAL
                val iv = ImageView(this)
                iv.setImageResource(R.drawable.ic_launcher_src)
                iv.scaleType = ImageView.ScaleType.CENTER_CROP
                iv.clipToOutline = true
                iv.outlineProvider = object : ViewOutlineProvider() {
                    override fun getOutline(view: View, outline: Outline) {
                        outline.setRoundRect(0, 0, view.width, view.height, dp(13).toFloat())
                    }
                }
                r.addView(iv, lp(dp(52), dp(52)))
                val t = tv("Default", 12f, C.MU)
                t.setPadding(dp(14), 0, 0, 0)
                r.addView(t)
                c.addView(r)
            }
            else -> {
                c.addTop(label("Floating bubble"), 14)
                c.addView(tv("Ukuran", 12f, C.MU))
                val sb = SeekBar(this)
                styleSeek(sb)
                sb.max = 40
                sb.progress = prefs.getInt("bubble_size", 52) - 36
                sb.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(s: SeekBar?, p: Int, u: Boolean) { }
                    override fun onStartTrackingTouch(s: SeekBar?) { }
                    override fun onStopTrackingTouch(s: SeekBar?) {
                        prefs.edit().putInt("bubble_size", 36 + (s?.progress ?: 16)).apply()
                        refreshBubble()
                    }
                })
                c.addTop(sb, 6)
                c.addTop(Seg(this, listOf("BULAT", "KOTAK", "PIL"), prefs.getInt("bubble_shape", 0)) { i ->
                    prefs.edit().putInt("bubble_shape", i).apply()
                    refreshBubble()
                }, 12)
                c.addTop(tv("Tap bubble: pilih profil. Tahan: sembunyikan.\nMunculkan lagi lewat notifikasi.", 11f, C.MU), 14)
            }
        }
    }

    private fun refreshBubble() {
        if (prefs.getBoolean("bubble_on", false) && Settings.canDrawOverlays(this)) {
            BubbleService.start(this, BubbleService.ACT_REFRESH)
        }
    }

    private fun applyBg() {
        val f = File(filesDir, "bg.jpg")
        if (f.exists()) {
            val bmp = BitmapFactory.decodeFile(f.path)
            if (bmp != null) {
                bgImg.setImageBitmap(bmp)
                bgImg.scaleType = when (prefs.getInt("bg_fit", 0)) {
                    1 -> ImageView.ScaleType.FIT_CENTER
                    2 -> ImageView.ScaleType.FIT_XY
                    else -> ImageView.ScaleType.CENTER_CROP
                }
                scrim.visibility = View.VISIBLE
                return
            }
        }
        bgImg.setImageDrawable(null)
        scrim.visibility = View.GONE
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data
        if (requestCode == 11 && resultCode == RESULT_OK && uri != null) {
            Sh.bg {
                var ok = false
                try {
                    val o1 = BitmapFactory.Options()
                    o1.inJustDecodeBounds = true
                    contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, o1) }
                    var s = 1
                    while (max(o1.outWidth, o1.outHeight) / s > 1800) s *= 2
                    val o2 = BitmapFactory.Options()
                    o2.inSampleSize = s
                    val bmp = contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, o2) }
                    if (bmp != null) {
                        File(filesDir, "bg.jpg").outputStream().use { bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, it) }
                        ok = true
                    }
                } catch (_: Exception) { }
                Sh.ui.post {
                    if (ok) applyBg() else toast("Gagal memuat gambar")
                }
            }
        }
    }

    // ---------------------------------------------------------------- TOOLS
    private fun buildTools() {
        // peralatan
        val pc = addCard()
        pc.addView(label("Peralatan"))
        val kN = kv("Native", "—")
        val kA = kv("Aktif", "—")
        pc.addView(kN.first); pc.addView(hairline()); pc.addView(kA.first)
        val seg = Seg(this, resList.map { it.toString() }, resIdx) { i -> resIdx = i }
        pc.addTop(seg, 8)
        val loadDisp = {
            Sh.bg {
                val d = Alpha.display()
                Sh.ui.post {
                    disp = d
                    if (d != null) {
                        kN.second.text = "${d.nw}×${d.nh} · ${d.nd}"
                        val pct = d.cw * 100 / d.nw
                        kA.second.text = "${d.cw}×${d.ch} · ${pct}%"
                        val idx = resList.indexOfFirst { it >= pct - 4 }
                        if (idx >= 0) { resIdx = idx; seg.select(idx) }
                    }
                }
            }
        }
        loadDisp()
        val b1 = pillButton("Apply res") {
            val d = disp
            if (d == null) toast("Resolusi belum terbaca") else Sh.bg {
                val r = Alpha.applyRes(d, resList[resIdx])
                Sh.ui.post { toast(if (r.ok) "Resolusi diterapkan" else firstLine(r)) }
                loadDisp()
            }
        }
        val b2 = pillButton("Reset") {
            Sh.bg {
                val r = Alpha.resetRes()
                Sh.ui.post { toast(if (r.ok) "Resolusi direset" else firstLine(r)) }
                loadDisp()
            }
        }
        pc.addTop(rowOf(b1, b2), 10)
        pc.addTop(pillButton("Dexopt app") {
            showAppSheet("Dexopt", false) { pkg, _, _ ->
                toast("Dexopt $pkg…")
                Sh.bg {
                    val r = Alpha.dexopt(pkg)
                    Sh.ui.post { toast(firstLine(r).ifEmpty { "Selesai" }) }
                }
            }
        }, 10)
        pc.addTop(pillButton("Tutup semua app") {
            confirm("Hentikan semua aplikasi pihak ketiga?") {
                Sh.bg {
                    Alpha.closeAll(packageName)
                    Sh.ui.post { toast("Selesai") }
                }
            }
        }, 10)

        // log
        val lc = addCard()
        lc.addView(label("Tuning log"))
        val lbox = LinearLayout(this)
        lbox.orientation = LinearLayout.VERTICAL
        lc.addView(lbox)
        Sh.bg {
            val l = Alpha.logs(6)
            Sh.ui.post {
                if (l.isEmpty()) lbox.addView(tv("Belum ada log", 11f, C.MU))
                for (e in l) {
                    val r = LinearLayout(this)
                    r.setPadding(0, dp(5), 0, dp(5))
                    val a = tv(Alpha.ago(e.ts), 11f, C.MU); a.maxLines = 1
                    val b = tv(e.cat, 11f, C.TX, true); b.maxLines = 1
                    val m = tv(e.st + " " + e.msg, 11f, C.MU)
                    m.maxLines = 1
                    m.ellipsize = TextUtils.TruncateAt.END
                    r.addView(a, lp(dp(46), WRAP))
                    r.addView(b, lp(dp(34), WRAP))
                    r.addView(m, lp(0, WRAP, 1f))
                    lbox.addView(r)
                }
            }
        }
        lc.addTop(rowOf(
            pillButton("Semua log") { showLog() },
            pillButton("Salin") {
                Sh.bg {
                    val t = Alpha.rawLog(300)
                    Sh.ui.post {
                        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        cm.setPrimaryClip(ClipData.newPlainText("alpha.log", t))
                        toast("Log disalin")
                    }
                }
            }
        ), 10)

        // mesin
        val mc = addCard()
        mc.addView(label("Mesin"))
        val t1 = toggleRow("fas-rs pegang CPU", true) { on ->
            Sh.bg { Alpha.setFlag("GB_FASRS_FORCE_ALPHA", !on) }
            toast("Berlaku di game berikutnya")
        }
        val t2 = toggleRow("Boost penuh setelah dingin", false) { on ->
            Sh.bg { Alpha.setFlag("GB_COOLDOWN_EXTREME", on) }
            toast("Berlaku di game berikutnya")
        }
        val t3 = toggleRow("Cpuset game dipersempit", true) { on ->
            Sh.bg { Alpha.setFlag("NO_CPUSET", !on) }
            toast("Berlaku di game berikutnya")
        }
        mc.addView(t1.first); mc.addView(hairline()); mc.addView(t2.first); mc.addView(hairline()); mc.addView(t3.first)
        Sh.bg {
            val f = Alpha.flags()
            Sh.ui.post {
                t1.second.on = f.fasrsOwnsCpu
                t2.second.on = f.cooldownFull
                t3.second.on = f.cpusetNarrow
            }
        }

        // device
        val dc = addCard()
        dc.addView(label("Device"))
        val d1 = kv("SoC", "—"); val d2 = kv("GPU", "—"); val d3 = kv("CPU", "—"); val d4 = kv("Storage", "—")
        dc.addView(d1.first); dc.addView(hairline()); dc.addView(d2.first); dc.addView(hairline())
        dc.addView(d3.first); dc.addView(hairline()); dc.addView(d4.first)
        val loadDev = {
            Sh.bg {
                val m = Alpha.detected()
                Sh.ui.post {
                    d1.second.text = m["SOC_VENDOR"] ?: "—"
                    d2.second.text = m["GPU_VENDOR"] ?: "—"
                    d3.second.text = m["CPU_POLICIES"] ?: "—"
                    d4.second.text = m["STORAGE_DEVICES"] ?: "—"
                }
            }
        }
        loadDev()
        dc.addTop(pillButton("Deteksi ulang") {
            toast("Mendeteksi…")
            Sh.bg {
                Alpha.redetect()
                Sh.ui.post { loadDev() }
            }
        }, 10)

        // auto-start
        val ac = addCard()
        ac.addView(toggleRow("Auto-start saat boot", prefs.getBoolean("autostart", true)) { on ->
            prefs.edit().putBoolean("autostart", on).apply()
        }.first)
        ac.addTop(rowOf(
            pillButton("Refresh") { initAsync(); refreshStatus() },
            pillButton("Cari module") {
                Sh.bg {
                    val p = Alpha.findModule()
                    Sh.ui.post { toast(if (p.isEmpty()) "Modul tidak ditemukan" else p); build() }
                }
            }
        ), 6)
        val info = if (Alpha.ready) "Root OK · " + Alpha.mod else if (Alpha.rootOk) "Root OK · modul tidak ditemukan" else "Root tidak tersedia"
        ac.addTop(tv(info, 10f, C.MU), 12)

        // about
        val bc = addCard()
        bc.addView(label("About"))
        bc.addView(tv("Alpha Control by somwan"))
        bc.addTop(tv("Alpha · Uperf · fas-rs\nCredit: Matt Yang & yinwanxi (Uperf), shadow3 & shadow3aaa (fas-rs)", 10f, C.MU), 4)
        bc.addTop(pillButton("Buka Battery Lab") { openBatteryLab() }, 12)
    }

    private fun showLog() {
        Sh.bg {
            val t = Alpha.rawLog(200)
            Sh.ui.post {
                val tvv = tv(if (t.isEmpty()) "(kosong)" else t, 10f, C.TX)
                tvv.setPadding(dp(16), dp(12), dp(16), dp(12))
                tvv.setTextIsSelectable(true)
                val sv = ScrollView(this)
                sv.addView(tvv)
                AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                    .setView(sv)
                    .setPositiveButton("Tutup", null)
                    .show()
            }
        }
    }

    private fun openBatteryLab() {
        try {
            val i = Intent()
            i.component = ComponentName("com.transsion.batterylab", "com.transsion.batterylab.BatteryLabHomeActivity")
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
                toast("Battery Lab tidak ditemukan")
            }
        }
    }
}
