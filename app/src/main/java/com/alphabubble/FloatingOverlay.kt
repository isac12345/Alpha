package com.alphabubble

import android.app.ActivityManager
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.SystemClock
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Satu jendela overlay: RINGKAS (pil), PENUH (panel), MEREKAM, dan BAR TIPIS.
 * Menggantikan bubble profil + HudOverlay lama. Semua angka dari satu stream
 * hud_sample.sh --loop; tidak ada proses/polling kedua.
 */
class FloatingOverlay(private val ctx: Context, private val prefs: Prefs) {

    companion object {
        private const val PANEL = 0xE00E131E.toInt()
        private const val CARD = 0x0FFFFFFF
        private const val BORDER = 0x1FFFFFFF
        private const val TEXT = 0xFFE8ECF4.toInt()
        private const val LABEL = 0xFFA6B0C3.toInt()
        private const val HINT = 0xFF98A2B3.toInt()
        private const val SEG_TEXT = 0xFFB4BDCE.toInt()
        private const val DARK = 0xFF1B1203.toInt()
        private const val RED = 0xFFE5484D.toInt()
        private const val REC_TAG = 0xFFFF9AA0.toInt()
        private const val CPU = 0xFF60A5FA.toInt()
        private const val GPU = 0xFFF5A524.toInt()
        private const val RAM = 0xFF34D399.toInt()
        private const val TEMP = 0xFFFB7185.toInt()
        private const val P_BATTERY = 0xFF34D399.toInt()
        private const val P_BALANCED = 0xFF60A5FA.toInt()
        private const val P_PERF = 0xFFF5A524.toInt()
        private const val OD = 0xFFD946EF.toInt()
        private const val OD_TEXT = 0xFFF0ABFC.toInt()
        private const val OD_END = 0xFF9333EA.toInt()
        private const val OD_GLOW = 0xB3D946EF.toInt()
        private const val MODE_PILL = 0
        private const val MODE_PANEL = 1
        private const val MODE_THIN = 2
        private val PROFILE_TEXT = listOf("Baterai", "Seimbang", "Performa")
    }

    var onProfile: ((String) -> Unit)? = null
    var onRec: (() -> Unit)? = null
    var onHidden: (() -> Unit)? = null
    var onOvd: ((Boolean) -> Unit)? = null
    var onSession: ((FpsSession) -> Unit)? = null

    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val probe = View(ctx)
    private var probeOn = false

    private val scale: Float get() = prefs.flScale / 100f
    private fun px(v: Number): Int = (v.toFloat() * scale).toInt().coerceAtLeast(1)
    private fun pf(v: Number): Float = v.toFloat() * scale

    private var root: FrameLayout? = null
    private var lp: WindowManager.LayoutParams? = null
    private var attached = false
    private var addedAt = 0L
    private var mode = MODE_PILL

    private var pill: View? = null
    private var panel: View? = null
    private var thin: View? = null

    private var fpsPill: TextView? = null
    private var fpsBig: TextView? = null
    private var fpsThin: TextView? = null
    private var fpsPillLbl: TextView? = null
    private var idleRun = 0

    // ---- statistik FPS: per sesi game dan per rekaman (1 sampel/detik, hanya saat ada frame)
    private var sesPkg = ""
    private var sesStart = 0L
    private var sesOvdTicks = 0
    private var sesProfile = ""
    private val sesFps = ArrayList<Float>(1024)
    private val recFps = ArrayList<Float>(512)

    // ---- rekam data FPS ke CSV (bukan video) ----
    private var csvOn = false
    private var csvStart = 0L
    private val csvBuf = StringBuilder()
    private var csvRows = 0
    private var csvBtnLbl: TextView? = null
    private var csvDot: View? = null

    fun toggleFpsLog() {
        if (!csvOn) {
            csvOn = true
            FpsLog.on = true; FpsLog.rows = 0
            csvStart = SystemClock.elapsedRealtime()
            csvRows = 0
            csvBuf.setLength(0)
            csvBuf.append("t_detik,paket,fps,gpu_persen,gpu_mhz,cpu_persen,suhu_soc,suhu_baterai,profil,overdrive\n")
            paintCsv()
            Toast.makeText(ctx, "Rekam data FPS dimulai", Toast.LENGTH_SHORT).show()
        } else {
            csvOn = false
            FpsLog.on = false
            paintCsv()
            saveCsv()
        }
    }

    private fun paintCsv() {
        paintThinBtns()
        csvBtnLbl?.text = if (csvOn) "Stop FPS" else "Rekam FPS"
        csvDot?.background = GradientDrawable().apply {
            shape = if (csvOn) GradientDrawable.RECTANGLE else GradientDrawable.OVAL
            cornerRadius = pf(3)
            setColor(Color.WHITE)
        }
    }

    private fun csvRow(s: Sample) {
        if (csvRows >= 40000) return
        val t = (SystemClock.elapsedRealtime() - csvStart) / 1000.0
        csvBuf.append("%.1f".format(java.util.Locale.US, t)).append(',').append(curFg).append(',')
        csvBuf.append(s.fps?.let { "%.1f".format(java.util.Locale.US, it) } ?: "").append(',')
        csvBuf.append(s.gpu?.toString() ?: "").append(',').append(s.gpuMhz?.toString() ?: "").append(',')
        csvBuf.append(s.cpu?.toString() ?: "").append(',')
        csvBuf.append(s.socC?.let { "%.0f".format(java.util.Locale.US, it) } ?: "").append(',')
        csvBuf.append(s.batC?.let { "%.0f".format(java.util.Locale.US, it) } ?: "").append(',')
        csvBuf.append(profile).append(',').append(if (odOn) 1 else 0).append('\n')
        csvRows++
        FpsLog.rows = csvRows
    }

    private fun saveCsv() {
        if (csvRows == 0) {
            Toast.makeText(ctx, "Tidak ada data FPS yang terekam", Toast.LENGTH_SHORT).show()
            return
        }
        val text = csvBuf.toString()
        val rows = csvRows
        csvBuf.setLength(0)
        scope.launch(Dispatchers.IO) {
            val ts = java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.US).format(java.util.Date())
            val name = "Alpha_fps_$ts.csv"
            val tmp = java.io.File(ctx.cacheDir, name)
            val ok = try {
                tmp.writeText(text)
                val r = Root.exec("mkdir -p /sdcard/Download && cp '${tmp.absolutePath}' /sdcard/Download/$name && echo OK", 20_000L)
                r.out.contains("OK")
            } catch (_: Exception) { false }
            try { tmp.delete() } catch (_: Exception) { }
            kotlinx.coroutines.withContext(Dispatchers.Main) {
                FpsLog.saved++
                Toast.makeText(ctx, if (ok) "Data FPS ($rows baris) disimpan: Download/$name" else "Gagal menyimpan data FPS", Toast.LENGTH_LONG).show()
            }
        }
    }

    /** Dipanggil tiap polling status: pkg = game terdaftar yang aktif (kosong = tidak ada). Ganti game = sesi lama selesai. */
    fun setSession(pkg: String) {
        if (pkg == sesPkg) return
        endSession()
        sesPkg = pkg
        sesStart = System.currentTimeMillis()
        sesOvdTicks = 0
        sesProfile = profile
        sesFps.clear()
    }

    private fun endSession() {
        if (sesPkg.isEmpty()) return
        val st = FpsSession.stats(sesFps)
        if (st != null) {
            val n = sesFps.size
            onSession?.invoke(FpsSession(sesStart, sesPkg, st.first, st.second, n,
                ((System.currentTimeMillis() - sesStart) / 1000L).toInt(), sesOvdTicks * 100 / n, sesProfile))
        }
        sesFps.clear()
        sesPkg = ""
    }

    private fun finishRecording() {
        val st = FpsSession.stats(recFps)
        recFps.clear()
        if (st != null) Toast.makeText(ctx, "Rekaman: rata-rata ${st.first} FPS, 1% terendah ${st.second} FPS", Toast.LENGTH_LONG).show()
    }
    private var fpsBigLbl: TextView? = null
    private var fpsThinLbl: TextView? = null
    private val valViews = arrayOfNulls<TextView>(4)
    private val barViews = arrayOfNulls<BarView>(4)
    private val cards = arrayOfNulls<View>(4)
    private val thinVals = arrayOfNulls<TextView>(4)
    private val thinGroups = arrayOfNulls<View>(4)
    private val rings = ArrayList<RingView>()
    private var segButtons = ArrayList<TextView>()
    private var segRow: View? = null
    private var odRow: LinearLayout? = null
    private var odFlame: FlameView? = null
    private var odName: TextView? = null
    private var odSmall: TextView? = null
    private var odOn = false
    private var odLevel = ""
    private var odAvail = false
    private var topRow: View? = null
    private var bigRow: View? = null
    private var gridRow: View? = null
    private var footRow: View? = null
    private var hintRec: View? = null
    private var graph: GraphView? = null
    private var panelBox: LinearLayout? = null

    private var profile = "none"
    private var recOn = false
    private var recStart = 0L
    private var started = false
    private var screenW = 0
    private var screenH = 0
    private val lastInt = IntArray(4) { -1 }

    private var game = ""
    private var job: Job? = null
    private var proc: Process? = null
    private var prevTs = ""
    private var curFg = ""
    private var cpuTotal = 0L
    private var cpuIdle = 0L
    private var gpuMaxMhz = 0

    // ---------------- publik ----------------

    fun attach() {
        if (prefs.bubbleHidden) return
        if (!Settings.canDrawOverlays(ctx)) return
        if (root == null) build()
        addWindow()
    }

    fun detach() {
        removeWindow()
        stopStream()
    }

    fun release() {
        removeWindow()
        if (probeOn) {
            try { wm.removeView(probe) } catch (_: Exception) { }
            probeOn = false
        }
        stopStream()
        scope.cancel()
    }

    /** Pilihan "Tampilan awal" berubah: ciutkan langsung ke bentuk itu (kecuali panel sedang dibuka). */
    fun applyStartMode() {
        mode = MODE_PILL
        rebuild()
    }

    fun rebuild() {
        val m = mode
        removeWindow()
        root = null
        valViews.fill(null)
        barViews.fill(null)
        cards.fill(null)
        thinVals.fill(null)
        thinGroups.fill(null)
        rings.clear()
        segButtons = ArrayList()
        graph = null
        segRow = null
        odRow = null
        odFlame = null
        odName = null
        odSmall = null
        topRow = null
        bigRow = null
        gridRow = null
        footRow = null
        hintRec = null
        fpsPill = null
        fpsBig = null
        fpsThin = null
        fpsPillLbl = null
        fpsBigLbl = null
        fpsThinLbl = null
        panelBox = null
        mode = m
        if (!prefs.bubbleHidden) {
            build()
            addWindow()
        }
    }

    fun setProfileState(p: String, rec: Boolean) {
        val changed = p != profile || rec != recOn
        profile = p
        if (rec != recOn) {
            if (rec) recFps.clear() else finishRecording()
            recOn = rec
            recStart = if (rec) SystemClock.elapsedRealtime() else 0L
        }
        if (changed) {
            val acc = accentColor()
            for (r in rings) { r.accent = acc; r.invalidate() }
            paintSeg()
            applyRec()
        }
        if (recOn) tickTimer()
    }

    fun setGame(pkg: String) {
        // aliran mati sendiri (su mati / pipa putus) atau jendela hilang: jangan berhenti di sini, mulai ulang
        val healthy = job?.isActive == true && attached
        if (pkg == game && healthy) return
        stopStream()
        game = pkg
        prevTs = ""
        cpuTotal = 0L
        cpuIdle = 0L
        gpuMaxMhz = 0
        for (i in lastInt.indices) lastInt[i] = -1
        if (pkg.isEmpty() || prefs.bubbleHidden) return
        attach()
        job = scope.launch(Dispatchers.IO) { loop(pkg) }
    }

    // ---------------- data ----------------

    private class Sample(val fps: Float?, val gpu: Int?, val gpuMhz: Int?, val cpu: Int?, val tempC: Float?, val socC: Float? = null, val batC: Float? = null)

    private suspend fun loop(pkg: String) {
        try {
            val mod = Root.modPath()
            if (mod.isEmpty()) return
            val p = ProcessBuilder("su", "-c", "sh '$mod/common/hud_sample.sh' --loop '$pkg'")
                .redirectErrorStream(true)
                .start()
            proc = p
            val br = BufferedReader(InputStreamReader(p.inputStream))
            val block = ArrayList<String>(32)
            while (true) {
                val line = br.readLine() ?: break
                if (line == "--") {
                    val s = parse(block)
                    block.clear()
                    scope.launch { apply(s) }
                } else if (block.size < 32) {
                    block.add(line)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("FloatingOverlay", "stream gagal: ${e.message}")
        } finally {
            try { proc?.destroyForcibly() } catch (_: Exception) { }
            proc = null
        }
    }

    private fun stopStream() {
        game = ""
        job?.cancel()
        job = null
        try { proc?.destroyForcibly() } catch (_: Exception) { }
        proc = null
    }

    private fun parse(lines: List<String>): Sample {
        val m = HashMap<String, String>()
        for (l in lines) {
            val i = l.indexOf('=')
            if (i > 0) m[l.substring(0, i)] = l.substring(i + 1).trim()
        }
        var ts = m["last_ts"].orEmpty()
        val x10 = m["fps_x10"]?.toIntOrNull()
        // Ganti app di depan: timestamp lama milik app sebelumnya tidak boleh dianggap "macet".
        val fgPkg = m["pkg"].orEmpty()
        if (fgPkg != curFg) { curFg = fgPkg; prevTs = "" }
        // Jalur layer: timestamp frame mentah dikirim script (shell ROM ini 32-bit, tidak bisa menghitung
        // angka 14 digit), FPS dihitung di sini dengan Long 64-bit seperti Smollming.
        val lat = m["lat"].orEmpty()
        var fpsLat: Float? = null
        if (lat.isNotEmpty()) {
            val arr = ArrayList<Long>(80)
            for (tok in lat.split(' ')) {
                val v = tok.toLongOrNull() ?: continue
                if (v > 0L) arr.add(v)
            }
            if (arr.size >= 3) {
                arr.sort()
                val last = arr[arr.size - 1]
                ts = last.toString()
                if (ts == prevTs) {
                    fpsLat = 0f
                } else {
                    val lo = last - 1_000_000_000L
                    var first = last
                    var n = 0
                    for (v in arr) {
                        if (v >= lo) {
                            n++
                            if (v < first) first = v
                        }
                    }
                    val span = last - first
                    if (n > 1 && span > 0L) {
                        val f = ((n - 1) * 1_000_000_000.0 / span).toFloat()
                        if (f.isFinite() && f <= 480f) fpsLat = f
                    }
                }
            }
        }
        val fps: Float? = when {
            lat.isNotEmpty() -> fpsLat
            x10 == null || ts.isEmpty() -> null
            ts == prevTs -> 0f
            x10 < 0 || x10 > 2400 -> null      // di atas 240 FPS = angka ngawur (mis. daftar layer berubah)
            else -> x10 / 10f
        }
        if (ts.isNotEmpty()) prevTs = ts

        var cpu: Int? = null
        val parts = m["cpu"].orEmpty().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (parts.size >= 9 && parts[0] == "cpu") {
            val v = parts.drop(1).take(8).map { it.toLongOrNull() ?: 0L }
            val total = v.sum()
            val idle = v[3] + v[4]
            val dt = total - cpuTotal
            val di = idle - cpuIdle
            if (cpuTotal > 0L && dt > 0L) cpu = (((dt - di) * 100) / dt).toInt().coerceIn(0, 100)
            cpuTotal = total
            cpuIdle = idle
        }
        val gpu = m["gpu"]?.toIntOrNull()?.coerceIn(0, 100)
        val gpuMhz = m["gpu_freq"]?.toIntOrNull()?.takeIf { it in 1..5000 }
        val soc = m["soc_mc"]?.toIntOrNull() ?: 0
        val bat = m["temp_mc"]?.toIntOrNull() ?: 0
        // suhu ngawur (> 105 C, sensor error) dibuang supaya tidak merusak grafik/statistik
        val socC = (soc / 1000f).takeIf { it in 1f..105f }
        val batC = (bat / 1000f).takeIf { it in 1f..105f }
        val t = socC ?: batC
        return Sample(fps, gpu, gpuMhz, cpu, t, socC, batC)
    }

    private fun apply(s: Sample) {
        if (prefs.bubbleHidden) return
        if (recOn) tickTimer()
        if (csvOn) csvRow(s)
        val fpsText = when {
            !prefs.flMFps -> null
            s.fps == null -> "--"
            else -> s.fps.toInt().toString()
        }
        val fv = s.fps
        if (fv != null && fv >= 1f) {
            if (sesPkg.isNotEmpty() && sesFps.size < 7200) { sesFps.add(fv); if (odOn) sesOvdTicks++ }
            if (recOn && recFps.size < 3600) recFps.add(fv)
        }
        // Layar diam (tidak ada frame baru) memang 0 FPS; 3 detik berturut-turut ditandai IDLE supaya tidak dikira error.
        idleRun = if (s.fps != null && s.fps < 0.5f) idleRun + 1 else 0
        val lbl = if (idleRun >= 3) "IDLE" else "FPS"
        setText(fpsPillLbl, lbl)
        setText(fpsThinLbl, lbl)
        setText(fpsBigLbl, lbl)
        if (fpsText != null) {
            setText(fpsPill, fpsText)
            setText(fpsThin, fpsText)
            if (mode == MODE_PANEL) setText(fpsBig, fpsText)
        }
        if (mode != MODE_PILL && s.fps != null && prefs.flGraph) graph?.add(s.fps)

        if (mode == MODE_PILL) return
        // String hanya dibuat kalau angka berubah (tidak ada alokasi tiap tick).
        val cpuV = s.cpu
        if (prefs.flMCpu && cpuV != null && lastInt[0] != cpuV) metric(0, cpuV, cpuV.toString() + "%", cpuV / 100f)
        val gpuV = s.gpu
        if (prefs.flMGpu) {
            if (gpuV != null) {
                if (lastInt[1] != gpuV) metric(1, gpuV, gpuV.toString() + "%", gpuV / 100f)
            } else {
                // Kernel tanpa node beban GPU: tampilkan frekuensi (MHz). Nilai negatif = penanda mode MHz.
                val mhz = s.gpuMhz
                if (mhz != null) {
                    if (mhz > gpuMaxMhz) gpuMaxMhz = mhz
                    if (lastInt[1] != -mhz) metric(1, -mhz, mhz.toString() + "M", mhz.toFloat() / gpuMaxMhz.toFloat())
                }
            }
        }
        if (prefs.flMRam) {
            val mi = ActivityManager.MemoryInfo()
            am.getMemoryInfo(mi)
            if (mi.totalMem > 0) {
                val used = ((mi.totalMem - mi.availMem) * 10 / 1_073_741_824L).toInt()
                if (lastInt[2] != used) metric(2, used, (used / 10).toString() + "." + (used % 10) + "G", (mi.totalMem - mi.availMem).toFloat() / mi.totalMem.toFloat())
            }
        }
        val tempV = s.tempC
        if (prefs.flMTemp && tempV != null) {
            val t = tempV.toInt()
            if (lastInt[3] != t) metric(3, t, t.toString() + "\u00B0", (t / 100f).coerceIn(0f, 1f))
        }
    }

    private fun metric(idx: Int, value: Int, text: String, frac: Float) {
        if (lastInt[idx] != value) {
            lastInt[idx] = value
            setText(valViews[idx], text)
            setText(thinVals[idx], text)
        }
        val bar = barViews[idx] ?: return
        if (abs(bar.frac - frac) > 0.004f) {
            bar.frac = frac
            bar.invalidate()
        }
    }

    private fun tickTimer() {
        val start = recStart
        val secs = if (start > 0L) ((SystemClock.elapsedRealtime() - start) / 1000L).toInt() else 0
        val mm = secs / 60
        val ss = secs % 60
        val txt = (if (mm < 10) "0" else "") + mm + ":" + (if (ss < 10) "0" else "") + ss
        val tv = topRow?.findViewWithTag<TextView>("timer")
        setText(tv, txt)
    }

    // ---------------- jendela ----------------

    private fun build() {
        if (!started) {
            started = true
            mode = MODE_PILL
        }
        val f = FrameLayout(ctx)
        pill = buildPill()
        panel = buildPanel()
        thin = buildThin()
        pill?.layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT)
        thin?.layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT)
        f.addView(pill)
        f.addView(panel)
        f.addView(thin)
        root = f
        paintSeg()
        applyRec()
        applyMetrics()
        applyMode()
        touch(f)
    }

    private fun addWindow() {
        // jendela hilang tanpa kita minta (sistem membuangnya): anggap belum terpasang, pasang ulang
        // (beri waktu 3 dtk setelah addView: isAttachedToWindow baru true di frame berikutnya)
        if (attached && root?.isAttachedToWindow == false && SystemClock.uptimeMillis() - addedAt > 3000L) {
            try { root?.let { wm.removeViewImmediate(it) } } catch (_: Exception) { }
            attached = false; lp = null
        }
        if (attached) return
        val r = root ?: return
        if (!Settings.canDrawOverlays(ctx)) return
        if (gameFg) ensureProbe()
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        p.x = savedX()
        p.y = savedY()
        lp = p
        try {
            wm.addView(r, p)
            attached = true
            addedAt = SystemClock.uptimeMillis()
        } catch (_: Exception) {
            // "sudah ditambahkan": jendela memang ada, jangan kehilangan lp/attached (itu yang mematikan geser)
            attached = r.parent != null || r.isAttachedToWindow
            if (attached) lp = p
            return
        }
        r.post { clamp() }
    }

    private fun removeWindow() {
        root?.let { v -> if (attached) try { wm.removeView(v) } catch (_: Exception) { } }
        attached = false
        lp = null
    }

    /**
     * Jendela probe transparan seluas layar. Ukurannya yang dipakai untuk batas
     * geser, karena HP ini kadang melaporkan metrik portrait saat game landscape.
     */
    /**
     * Jendela probe seluas layar HANYA dipasang saat game di depan. Di app biasa (Play Store dll.) jendela
     * seluas layar membuat Android menganggap layar "tertutup" dan app sensitif mengabaikan semua sentuhan.
     */
    private var gameFg = false
    private fun syncProbe(game: Boolean) {
        if (game == gameFg) return
        gameFg = game
        if (game) {
            if (attached) ensureProbe()
        } else if (probeOn) {
            try { wm.removeView(probe) } catch (_: Exception) { }
            probeOn = false
            screenW = 0; screenH = 0
            if (attached) { lp?.let { q -> q.x = savedX(); q.y = savedY() }; clamp() }
        }
    }

    private fun ensureProbe() {
        if (probeOn) return
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        // Android 12+: overlay seluas layar dengan alpha jendela > 0,8 dianggap "menutupi" app di belakangnya,
        // dan app sensitif (Play Store: profil/pembayaran) lalu mengabaikan semua sentuhan = tampak beku.
        // Jendela probe isinya kosong, jadi alpha rendah tidak mengubah tampilan tapi membuat sentuhan lolos.
        p.alpha = 0.1f
        try {
            wm.addView(probe, p)
            probeOn = true
        } catch (_: Exception) {
            probeOn = false
            return
        }
        probe.addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
            if (v.width > 0 && v.height > 0 && (v.width != screenW || v.height != screenH)) {
                screenW = v.width
                screenH = v.height
                if (attached) {
                    lp?.let { q ->
                        q.x = savedX()
                        q.y = savedY()
                    }
                    clamp()
                }
            }
        }
    }

    private fun landscape(): Boolean {
        val w = if (screenW > 0) screenW else ctx.resources.displayMetrics.widthPixels
        val h = if (screenH > 0) screenH else ctx.resources.displayMetrics.heightPixels
        return w > h
    }

    private fun savedX(): Int = if (landscape()) prefs.flXl else prefs.flXp
    private fun savedY(): Int = if (landscape()) prefs.flYl else prefs.flYp

    private fun savePos() {
        val p = lp ?: return
        if (landscape()) {
            prefs.flXl = p.x
            prefs.flYl = p.y
        } else {
            prefs.flXp = p.x
            prefs.flYp = p.y
        }
    }

    private fun clamp() {
        val r = root ?: return
        val p = lp ?: return
        if (!attached) return
        val sw = if (screenW > 0) screenW else ctx.resources.displayMetrics.widthPixels
        val sh = if (screenH > 0) screenH else ctx.resources.displayMetrics.heightPixels
        p.x = p.x.coerceIn(0, max(0, sw - r.width))
        p.y = p.y.coerceIn(0, max(0, sh - r.height))
        try { wm.updateViewLayout(r, p) } catch (_: Exception) { }
    }

    private fun moveTo(x: Int, y: Int) {
        val r = root ?: return
        val p = lp ?: return
        if (!attached) return
        p.x = x
        p.y = y
        try { wm.updateViewLayout(r, p) } catch (_: Exception) { }
    }

    private fun touch(v: View) {
        val slop = ViewConfiguration.get(ctx).scaledTouchSlop
        var dx = 0f
        var dy = 0f
        var sx = 0
        var sy = 0
        var moved = false
        var downAt = 0L
        v.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    dx = e.rawX
                    dy = e.rawY
                    sx = lp?.x ?: 0
                    sy = lp?.y ?: 0
                    moved = false
                    downAt = SystemClock.uptimeMillis()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val mx = e.rawX - dx
                    val my = e.rawY - dy
                    if (!moved && (abs(mx) > slop || abs(my) > slop)) moved = true
                    if (moved) moveTo(sx + mx.toInt(), sy + my.toInt())
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val held = SystemClock.uptimeMillis() - downAt
                    if (moved) {
                        savePos()
                        clamp()
                    } else if (held >= 500L) {
                        hide()
                    } else {
                        toggle()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (moved) {
                        savePos()
                        clamp()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun toggle() {
        mode = if (mode == MODE_PILL) (if (prefs.flStartThin) MODE_THIN else MODE_PANEL) else MODE_PILL
        applyMode()
        root?.post { clamp() }
    }

    private fun hide() {
        prefs.bubbleHidden = true
        onHidden?.invoke()
        Toast.makeText(ctx, "Floating disembunyikan. Munculkan lagi lewat notifikasi.", Toast.LENGTH_LONG).show()
    }

    private fun applyMode() {
        pill?.visibility = if (mode == MODE_PILL) View.VISIBLE else View.GONE
        panel?.visibility = if (mode == MODE_PANEL) View.VISIBLE else View.GONE
        thin?.visibility = if (mode == MODE_THIN) View.VISIBLE else View.GONE
        for (i in lastInt.indices) lastInt[i] = -1
        if (mode == MODE_PANEL) graph?.clear()
    }

    // ---------------- tampilan ----------------

    private fun panelColor(): Int {
        val a = (prefs.flAlpha / 100f * 255).toInt().coerceIn(0, 255)
        return Color.argb(a, 14, 19, 30)
    }

    private fun accentColor(): Int {
        if (odOn) return OD
        if (prefs.flAccentFixed) return prefs.flAccentColor
        return when (profile) {
            "battery" -> P_BATTERY
            "balanced" -> P_BALANCED
            "performance" -> P_PERF
            else -> P_PERF
        }
    }

    private fun roundBg(color: Int, radius: Float, stroke: Int): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
            if (stroke != 0) setStroke(px(1), stroke)
        }

    private fun textView(s: String, sizePx: Float, color: Int, bold: Boolean): TextView =
        TextView(ctx).apply {
            text = s
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_PX, pf(sizePx))
            typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
            includeFontPadding = false
            gravity = Gravity.CENTER_VERTICAL
        }

    private fun setText(tv: TextView?, s: String) {
        if (tv != null && tv.text.toString() != s) tv.text = s
    }

    private fun fpsLabel(sizePx: Float, spacing: Float): TextView =
        textView("FPS", sizePx, LABEL, true).apply { letterSpacing = spacing }

    private fun buildPill(): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(8), 0, px(16), 0)
            background = roundBg(panelColor(), pf(24), BORDER)
            minimumHeight = px(48)
        }
        val ring = RingView(32, accentColor())
        rings.add(ring)
        row.addView(ring)
        val b = textView("--", 24f, TEXT, true).apply { letterSpacing = -0.02f }
        fpsPill = b
        row.addView(b, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(12) })
        val l1 = fpsLabel(11f, 0.08f)
        fpsPillLbl = l1
        row.addView(l1, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(5) })
        return row
    }

    private fun buildThin(): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(8), 0, px(6), 0)
            background = roundBg(panelColor(), pf(26), BORDER)
            minimumHeight = px(52)
        }
        val ring = RingView(36, accentColor())
        rings.add(ring)
        row.addView(ring)
        val b = textView("--", 24f, TEXT, true).apply { letterSpacing = -0.02f }
        fpsThin = b
        row.addView(b, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(14) })
        val l2 = fpsLabel(10f, 0.08f)
        fpsThinLbl = l2
        row.addView(l2, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(5) })
        val sep = View(ctx).apply { setBackgroundColor(0x24FFFFFF) }
        row.addView(sep, LinearLayout.LayoutParams(px(1), px(24)).apply { marginStart = px(14); marginEnd = px(14) })
        val mNames = listOf("CPU", "GPU", "RAM", "SUHU")
        for (i in 0 until 4) {
            val grp = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.BOTTOM }
            grp.addView(textView(mNames[i], 10f, LABEL, true).apply { letterSpacing = 0.1f })
            val v = textView("--", 15f, TEXT, true)
            grp.addView(v, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(4) })
            thinVals[i] = v
            thinGroups[i] = grp
            row.addView(grp, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = if (i == 0) 0 else px(14) })
        }
        val spacer = View(ctx)
        row.addView(spacer, LinearLayout.LayoutParams(0, 1, 1f))
        // tombol cepat: profil (ketuk = ganti), Overdrive, rekam data FPS
        val bp = thinBtn { 
            val next = when (profile) { "battery" -> "balanced"; "balanced" -> "performance"; else -> "battery" }
            onProfile?.invoke(next)
        }
        thinProf = bp
        row.addView(bp, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(40)).apply { marginStart = px(12) })
        val bo = thinBtn { if (odOn || odAvail) onOvd?.invoke(!odOn) }
        thinOd = bo
        row.addView(bo, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(40)).apply { marginStart = px(8) })
        val bc = thinBtn { toggleFpsLog() }
        thinCsv = bc
        row.addView(bc, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(40)).apply { marginStart = px(8) })
        paintThinBtns()
        val rb = recCircle()
        row.addView(rb, LinearLayout.LayoutParams(px(44), px(44)).apply { marginStart = px(8) })
        return row
    }

    private var thinProf: TextView? = null
    private var thinOd: TextView? = null
    private var thinCsv: TextView? = null

    private fun thinBtn(onClick: () -> Unit): TextView =
        textView("", 12f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER
            setPadding(px(12), 0, px(12), 0)
            isClickable = true
            setOnClickListener { onClick() }
        }

    private fun paintThinBtns() {
        thinProf?.apply {
            text = when (profile) { "battery" -> "DAY"; "balanced" -> "BAL"; "performance" -> "PERF"; else -> "..." }
            background = roundBg(0x33FFFFFF, pf(20), 0)
        }
        thinOd?.apply {
            text = "OD"
            setTextColor(if (odOn) Color.WHITE else OD_TEXT)
            background = if (odOn) GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(OD, OD_END)).apply { cornerRadius = pf(20) }
                         else roundBg(0x1AD946EF, pf(20), 0x8CD946EF.toInt())
            alpha = if (!odOn && !odAvail) 0.5f else 1f
        }
        thinCsv?.apply {
            text = if (csvOn) "STOP" else "FPS"
            background = roundBg(if (csvOn) 0xCCE5484D.toInt() else 0x33FFFFFF, pf(20), 0)
        }
    }

    private fun recCircle(): View {
        val box = FrameLayout(ctx).apply {
            background = roundBg(0x2EE5484D, pf(22), 0)
            isClickable = true
            contentDescription = "Mulai rekam"
            setOnClickListener { onRec?.invoke() }
        }
        val dot = View(ctx).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(RED) }
        }
        box.addView(dot, FrameLayout.LayoutParams(px(16), px(16), Gravity.CENTER))
        return box
    }

    private fun csvButton(): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(14), 0, px(16), 0)
            background = roundBg(0x33FFFFFF, pf(22), 0)
            minimumHeight = px(44)
            isClickable = true
            setOnClickListener { toggleFpsLog() }
        }
        val dot = View(ctx)
        csvDot = dot
        row.addView(dot, LinearLayout.LayoutParams(px(12), px(12)))
        val lbl = textView(if (csvOn) "Stop FPS" else "Rekam FPS", 13f, Color.WHITE, true)
        csvBtnLbl = lbl
        row.addView(lbl, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(8) })
        paintCsv()
        return row
    }

    private fun recButton(stop: Boolean): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(14), 0, px(18), 0)
            background = roundBg(RED, pf(22), 0)
            minimumHeight = px(44)
            isClickable = true
            setOnClickListener { onRec?.invoke() }
        }
        val sq = View(ctx).apply {
            background = GradientDrawable().apply {
                cornerRadius = pf(if (stop) 3 else 7)
                setColor(Color.WHITE)
            }
        }
        row.addView(sq, LinearLayout.LayoutParams(px(14), px(14)))
        row.addView(textView(if (stop) "Berhenti" else "Rekam", 14f, Color.WHITE, true), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(8) })
        return row
    }

    private fun buildPanel(): View {
        val box = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(16), px(16), px(16), px(16))
            background = roundBg(panelColor(), pf(20), BORDER)
        }
        panelBox = box
        var first = true
        fun add(v: View, m: Int = 14) {
            box.addView(v, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                topMargin = if (first) 0 else px(m)
            })
            first = false
        }

        val seg = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(px(4), px(4), px(4), px(4))
            background = roundBg(CARD, pf(14), 0)
        }
        segButtons = ArrayList()
        for ((i, k) in PROFILE_KEYS.withIndex()) {
            val b = textView(PROFILE_TEXT[i], 13f, SEG_TEXT, true).apply {
                gravity = Gravity.CENTER
                isClickable = true
                setOnClickListener { if (!odOn) onProfile?.invoke(k) }
            }
            seg.addView(b, LinearLayout.LayoutParams(0, px(44), 1f).apply { marginStart = if (i == 0) 0 else px(6) })
            segButtons.add(b)
        }
        segRow = seg
        add(seg)
        add(buildOdRow(), 8)

        val top = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val dot = View(ctx).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(RED) }
        }
        top.addView(dot, LinearLayout.LayoutParams(px(12), px(12)))
        val tm = textView("00:00", 20f, TEXT, true).apply { tag = "timer"; letterSpacing = 0.02f }
        top.addView(tm, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(10) })
        top.addView(textView("REC", 11f, REC_TAG, true).apply { letterSpacing = 0.12f }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(10) })
        top.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f))
        top.addView(recButton(true), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(44)))
        topRow = top
        add(top)

        val big = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.BOTTOM }
        val nb = textView("--", 60f, TEXT, true).apply { letterSpacing = -0.03f }
        fpsBig = nb
        big.addView(nb)
        val l3 = fpsLabel(13f, 0.1f)
        fpsBigLbl = l3
        big.addView(l3, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(6) })
        if (prefs.flGraph) {
            big.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f))
            val g = GraphView(GPU)
            graph = g
            big.addView(g)
        }
        bigRow = big
        add(big)

        val grid = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        val names = listOf("CPU", "GPU", "RAM", "SUHU")
        for (i in 0 until 4) {
            grid.addView(card(names[i], i), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = if (i == 0) 0 else px(8) })
        }
        gridRow = grid
        add(grid)

        val foot = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        foot.addView(recButton(false), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(44)))
        foot.addView(csvButton(), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(44)).apply { marginStart = px(8) })
        foot.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f))
        val hint = textView("Ketuk: ringkas\nTahan: sembunyikan", 11f, HINT, false).apply {
            gravity = Gravity.END
            setLineSpacing(0f, 1.4f)
        }
        foot.addView(hint, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(12) })
        footRow = foot
        add(foot)

        val recHint = textView("Profil terkunci selama merekam. Satu sesi = satu file video.", 11f, HINT, false).apply {
            setLineSpacing(0f, 1.4f)
        }
        hintRec = recHint
        add(recHint)

        val flp = FrameLayout.LayoutParams(px(380), FrameLayout.LayoutParams.WRAP_CONTENT)
        box.layoutParams = flp
        return box
    }

    private fun card(label: String, idx: Int): View {
        val box = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(10), px(10), px(10), px(8))
            background = roundBg(CARD, pf(12), 0)
        }
        box.addView(textView(label, 10f, LABEL, true).apply { letterSpacing = 0.1f })
        val v = textView("--", 18f, TEXT, true)
        valViews[idx] = v
        box.addView(v, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = px(4) })
        val bar = BarView(barColor(idx))
        barViews[idx] = bar
        box.addView(bar, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, px(3)).apply { topMargin = px(4) })
        cards[idx] = box
        return box
    }

    private fun barColor(idx: Int): Int = when (idx) {
        0 -> CPU
        1 -> GPU
        2 -> RAM
        else -> TEMP
    }

    private fun buildOdRow(): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(14), 0, px(14), 0)
            minimumHeight = px(44)
            isClickable = true
            setOnClickListener {
                if (!odAvail && !odOn) Toast.makeText(ctx, "Buka game terdaftar dulu, Overdrive hanya untuk game", Toast.LENGTH_SHORT).show()
                else onOvd?.invoke(!odOn)
            }
        }
        val fl = FlameView(OD_TEXT)
        odFlame = fl
        row.addView(fl, LinearLayout.LayoutParams(px(18), px(18)))
        val nm = textView("Overdrive", 14f, OD_TEXT, true)
        odName = nm
        row.addView(nm, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(8) })
        row.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f))
        val sm = textView("", 11f, HINT, true).apply { letterSpacing = 0.02f }
        odSmall = sm
        row.addView(sm)
        odRow = row
        applyOvd()
        return row
    }

    /** Status Overdrive dari modul. avail = ada game terdaftar yang aktif (syarat untuk menyalakan). */
    fun setOvd(on: Boolean, level: String, avail: Boolean) {
        syncProbe(avail)
        if (on == odOn && level == odLevel && avail == odAvail) return
        val modeChanged = on != odOn
        odOn = on; odLevel = level; odAvail = avail
        applyOvd()
        if (modeChanged) {
            val acc = accentColor()
            for (r in rings) { r.accent = acc; r.invalidate() }
            paintSeg()
        }
    }

    private fun applyOvd() {
        paintThinBtns()
        val row = odRow
        if (row != null) {
            if (odOn) {
                row.background = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(OD, OD_END)).apply { cornerRadius = pf(22) }
                odFlame?.color = Color.WHITE; odFlame?.invalidate()
                odName?.setTextColor(Color.WHITE)
                odSmall?.setTextColor(0xD9FFFFFF.toInt())
                setText(odSmall, if (odLevel == "safe") "AKTIF \u00B7 AMAN (PANAS)" else if (odLevel == "mid") "AKTIF \u00B7 TURUN SEDIKIT" else "AKTIF")
            } else {
                row.background = roundBg(0x1AD946EF, pf(22), 0x8CD946EF.toInt())
                odFlame?.color = OD_TEXT; odFlame?.invalidate()
                odName?.setTextColor(OD_TEXT)
                odSmall?.setTextColor(HINT)
                setText(odSmall, if (odAvail) "Mesin sendiri, tanpa Uperf/fas-rs" else "Butuh game aktif")
            }
            row.alpha = if (!odOn && !odAvail) 0.6f else 1f
        }
        val edge = if (odOn) OD_GLOW else BORDER
        panelBox?.background = roundBg(panelColor(), pf(20), if (recOn) 0x8CE5484D.toInt() else edge)
        pill?.background = roundBg(panelColor(), pf(24), edge)
        thin?.background = roundBg(panelColor(), pf(26), edge)
    }

    private inner class FlameView(var color: Int) : View(ctx) {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val path = Path()
        override fun onDraw(c: Canvas) {
            val w = width.toFloat(); val h = height.toFloat()
            p.color = color
            p.strokeWidth = w * 0.09f
            path.reset()
            path.moveTo(0.50f * w, 0.06f * h)
            path.cubicTo(0.62f * w, 0.33f * h, 0.34f * w, 0.40f * h, 0.34f * w, 0.62f * h)
            path.cubicTo(0.34f * w, 0.80f * h, 0.66f * w, 0.80f * h, 0.66f * w, 0.62f * h)
            path.cubicTo(0.66f * w, 0.50f * h, 0.62f * w, 0.43f * h, 0.58f * w, 0.37f * h)
            path.cubicTo(0.82f * w, 0.48f * h, 0.90f * w, 0.62f * h, 0.90f * w, 0.70f * h)
            path.cubicTo(0.90f * w, 0.88f * h, 0.72f * w, 0.96f * h, 0.50f * w, 0.96f * h)
            path.cubicTo(0.28f * w, 0.96f * h, 0.10f * w, 0.88f * h, 0.10f * w, 0.70f * h)
            path.cubicTo(0.10f * w, 0.40f * h, 0.38f * w, 0.30f * h, 0.50f * w, 0.06f * h)
            c.drawPath(path, p)
        }
    }

    private fun paintSeg() {
        paintThinBtns()
        if (segButtons.size < 3) return
        val acc = accentColor()
        for (i in 0 until 3) {
            val on = PROFILE_KEYS[i] == profile
            val b = segButtons[i]
            b.background = roundBg(if (on) acc else Color.TRANSPARENT, pf(10), 0)
            b.setTextColor(if (on) DARK else SEG_TEXT)
            b.alpha = if (recOn || odOn) 0.45f else 1f
        }
    }

    private fun applyRec() {
        segRow?.visibility = if (recOn) View.GONE else View.VISIBLE
        odRow?.visibility = if (recOn) View.GONE else View.VISIBLE
        topRow?.visibility = if (recOn) View.VISIBLE else View.GONE
        footRow?.visibility = if (recOn) View.GONE else View.VISIBLE
        hintRec?.visibility = if (recOn) View.VISIBLE else View.GONE
        panelBox?.background = roundBg(panelColor(), pf(20), if (recOn) 0x8CE5484D.toInt() else if (odOn) OD_GLOW else BORDER)
        if (recOn && recStart == 0L) recStart = SystemClock.elapsedRealtime()
        tickTimer()
    }

    private fun applyMetrics() {
        for (i in 0 until 4) {
            val on = when (i) {
                0 -> prefs.flMCpu
                1 -> prefs.flMGpu
                2 -> prefs.flMRam
                else -> prefs.flMTemp
            }
            cards[i]?.visibility = if (on) View.VISIBLE else View.GONE
            thinGroups[i]?.visibility = if (on) View.VISIBLE else View.GONE
        }
        val fpsVis = if (prefs.flMFps) View.VISIBLE else View.GONE
        fpsPill?.visibility = fpsVis
        fpsPillLbl?.visibility = fpsVis
        fpsBig?.visibility = fpsVis
        fpsBigLbl?.visibility = fpsVis
        fpsThin?.visibility = fpsVis
        fpsThinLbl?.visibility = fpsVis
        // FPS dimatikan: pil ringkas hanya logo (cincin berwarna sesuai mode), padding dibuat simetris
        (pill as? LinearLayout)?.setPadding(px(8), 0, if (prefs.flMFps) px(16) else px(8), 0)
    }

    // ---------------- komponen gambar ----------------

    private inner class RingView(sizePx: Int, var accent: Int) : View(ctx) {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        private val path = Path()
        private val stroke = pf(2f)

        init {
            layoutParams = LinearLayout.LayoutParams(px(sizePx), px(sizePx))
        }

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            p.style = Paint.Style.FILL
            p.color = Color.argb(46, Color.red(accent), Color.green(accent), Color.blue(accent))
            canvas.drawCircle(w / 2f, h / 2f, w / 2f, p)
            p.style = Paint.Style.STROKE
            p.strokeWidth = stroke
            p.color = accent
            canvas.drawCircle(w / 2f, h / 2f, w / 2f - stroke / 2f, p)
            val ic = w * 0.5f
            val s = ic / 24f
            canvas.save()
            canvas.translate((w - ic) / 2f, (h - ic) / 2f)
            canvas.scale(s, s)
            path.reset()
            path.moveTo(13f, 2f)
            path.lineTo(4f, 14f)
            path.lineTo(11f, 14f)
            path.lineTo(10f, 22f)
            path.lineTo(19f, 10f)
            path.lineTo(12f, 10f)
            path.close()
            p.style = Paint.Style.STROKE
            p.strokeWidth = 2.4f
            p.strokeJoin = Paint.Join.ROUND
            p.strokeCap = Paint.Cap.ROUND
            canvas.drawPath(path, p)
            canvas.restore()
        }
    }

    private inner class BarView(private val color: Int) : View(ctx) {
        var frac = 0f

        override fun onDraw(canvas: Canvas) {
            val r = height / 2f
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            p.color = 0x1FFFFFFF
            canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), r, r, p)
            if (frac > 0f) {
                p.color = color
                canvas.drawRoundRect(0f, 0f, width * frac.coerceIn(0f, 1f), height.toFloat(), r, r, p)
            }
        }
    }

    private inner class GraphView(private val color: Int) : View(ctx) {
        private val vals = FloatArray(30)
        private var n = 0
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        private val path = Path()

        init {
            layoutParams = LinearLayout.LayoutParams(px(170), px(48))
        }

        fun add(fps: Float?) {
            if (fps == null) return
            for (i in 0 until vals.size - 1) vals[i] = vals[i + 1]
            vals[vals.size - 1] = fps
            if (n < vals.size) n++
            invalidate()
        }

        fun clear() {
            vals.fill(0f)
            n = 0
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            p.style = Paint.Style.STROKE
            p.strokeWidth = pf(1f)
            p.color = 0x1AFFFFFF
            p.pathEffect = DashPathEffect(floatArrayOf(pf(3f), pf(4f)), 0f)
            canvas.drawLine(0f, pf(8f), width.toFloat(), pf(8f), p)
            p.pathEffect = null
            if (n < 2) return
            var mn = Float.MAX_VALUE
            var mx = -Float.MAX_VALUE
            for (i in vals.size - n until vals.size) {
                mn = min(mn, vals[i])
                mx = max(mx, vals[i])
            }
            if (mx - mn < 1f) mx = mn + 1f
            path.reset()
            for (i in 0 until n) {
                val v = vals[vals.size - n + i]
                val x = width * i / (n - 1f)
                val y = pf(6f) + (1f - (v - mn) / (mx - mn)) * (height - pf(12f))
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            p.color = color
            p.strokeWidth = pf(2f)
            p.strokeJoin = Paint.Join.ROUND
            p.strokeCap = Paint.Cap.ROUND
            canvas.drawPath(path, p)
        }
    }
}
