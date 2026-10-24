package com.alphabubble

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.math.abs

/**
 * HUD kecil di atas game: FPS, beban GPU/CPU, suhu, dan tombol REC.
 *
 * Hidup di dalam BubbleService (pakai izin overlay yang sama). Metrik dibaca dari
 * hud_sample.sh --loop lewat SATU proses su yang terus terbuka, jadi tidak ada
 * spawn su tiap detik. Proses berhenti sendiri bila pipa ditutup (SIGPIPE di sisi shell).
 */
class HudOverlay(private val ctx: Context, private val prefs: Prefs) {

    private class Sample(val fps: Float?, val gpu: Int?, val cpu: Int?, val tempC: Float?)

    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val pkgRe = Regex("^[A-Za-z0-9._]+\\.[A-Za-z0-9._]+$")

    private var box: LinearLayout? = null
    private var lp: WindowManager.LayoutParams? = null
    private var fpsTv: TextView? = null
    private var infoTv: TextView? = null
    private var recTv: TextView? = null

    private var game = ""
    private var recording = false
    private var streamJob: Job? = null
    @Volatile private var proc: Process? = null

    // Hanya disentuh dari thread pembaca stream (IO)
    private var prevTs = ""
    private var prevCpuTotal = 0L
    private var prevCpuIdle = 0L

    private fun dp(v: Int): Int = (v * ctx.resources.displayMetrics.density).toInt()

    /** Dipanggil dari main thread tiap siklus status. pkg kosong = tidak ada game. */
    fun update(pkg: String, rec: Boolean) {
        recording = rec
        updateRecLabel()
        val want = prefs.hudOn && pkg.isNotEmpty() && pkgRe.matches(pkg) && Settings.canDrawOverlays(ctx)
        if (!want) {
            if (game.isNotEmpty() || box != null) stop()
            return
        }
        if (pkg != game || box == null) {
            stop()
            game = pkg
            show()
            startStream(pkg)
        }
    }

    fun release() {
        stop()
        scope.cancel()
    }

    private fun stop() {
        game = ""
        streamJob?.cancel()
        streamJob = null
        try { proc?.destroyForcibly() } catch (_: Exception) { }
        proc = null
        box?.let { try { wm.removeView(it) } catch (_: Exception) { } }
        box = null
        lp = null
        fpsTv = null
        infoTv = null
        recTv = null
    }

    // ---------- tampilan ----------
    private fun show() {
        val bg = GradientDrawable().apply {
            setColor(0xB3101214.toInt())
            cornerRadius = dp(10).toFloat()
        }
        val fps = TextView(ctx).apply {
            text = "-- FPS"
            setTextColor(0xFFE8E6E1.toInt())
            textSize = 16f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        }
        val info = TextView(ctx).apply {
            text = "GPU --  CPU --"
            setTextColor(0xFFB9B7B0.toInt())
            textSize = 10f
            typeface = Typeface.MONOSPACE
        }
        val rec = TextView(ctx).apply {
            textSize = 10f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            setPadding(0, dp(4), 0, 0)
            setOnClickListener { toggleRec() }
        }
        val b = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = bg
            setPadding(dp(9), dp(6), dp(9), dp(6))
            addView(fps)
            addView(info)
            addView(rec)
        }
        val dm = ctx.resources.displayMetrics
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        p.x = prefs.hudX.coerceIn(0, (dm.widthPixels - dp(40)).coerceAtLeast(0))
        p.y = prefs.hudY.coerceIn(0, (dm.heightPixels - dp(40)).coerceAtLeast(0))

        val slop = ViewConfiguration.get(ctx).scaledTouchSlop
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0; var moved = false
        b.setOnTouchListener { v, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY; startX = p.x; startY = p.y; moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (!moved && (abs(dx) > slop || abs(dy) > slop)) moved = true
                    if (moved) {
                        p.x = (startX + dx).toInt().coerceIn(0, (dm.widthPixels - v.width).coerceAtLeast(0))
                        p.y = (startY + dy).toInt().coerceIn(0, (dm.heightPixels - v.height).coerceAtLeast(0))
                        try { wm.updateViewLayout(v, p) } catch (_: Exception) { }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (moved) { prefs.hudX = p.x; prefs.hudY = p.y }
                    true
                }
                else -> false
            }
        }
        try {
            wm.addView(b, p)
            box = b; lp = p; fpsTv = fps; infoTv = info; recTv = rec
            updateRecLabel()
        } catch (_: Exception) {
            box = null
        }
    }

    private fun updateRecLabel() {
        recTv?.apply {
            text = if (recording) "■ STOP" else "● REC"
            setTextColor(if (recording) 0xFFFF6B6B.toInt() else 0xFF8FD6B5.toInt())
        }
    }

    private fun toggleRec() {
        scope.launch {
            val r = if (recording) Alpha.recStop() else Alpha.recStart()
            val ok = r.out.startsWith("OK")
            recording = if (recording) !ok else ok
            updateRecLabel()
            Toast.makeText(ctx, r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal", Toast.LENGTH_SHORT).show()
        }
    }

    private fun render(s: Sample) {
        fpsTv?.apply {
            text = if (s.fps == null) "-- FPS" else "%.0f FPS".format(s.fps)
            setTextColor(
                when {
                    s.fps == null -> 0xFFB9B7B0.toInt()
                    s.fps >= 55f -> 0xFF8FD6B5.toInt()
                    s.fps >= 30f -> 0xFFE8E6E1.toInt()
                    else -> 0xFFEF9F27.toInt()
                },
            )
        }
        infoTv?.text = buildString {
            append("GPU ").append(s.gpu?.let { "$it%" } ?: "--")
            append("  CPU ").append(s.cpu?.let { "$it%" } ?: "--")
            if (s.tempC != null && s.tempC > 0f) append("  ").append("%.0f°C".format(s.tempC))
        }
    }

    // ---------- stream metrik ----------
    private fun startStream(pkg: String) {
        prevTs = ""; prevCpuTotal = 0L; prevCpuIdle = 0L
        streamJob = scope.launch {
            if (!pkg.matches(Regex("^[A-Za-z0-9._]+$"))) return@launch
            val mod = Root.modPath()
            if (mod.isEmpty()) return@launch
            withContext(Dispatchers.IO) {
                var p: Process? = null
                try {
                    p = ProcessBuilder("su", "-c", "sh '$mod/common/hud_sample.sh' --loop '$pkg'")
                        .redirectErrorStream(true)
                        .start()
                    proc = p
                    val br = BufferedReader(InputStreamReader(p.inputStream))
                    val block = ArrayList<String>()
                    while (true) {
                        val line = br.readLine() ?: break
                        if (line == "--") {
                            val s = parse(block)
                            block.clear()
                            scope.launch { render(s) }
                        } else if (block.size < 32) block.add(line)
                    }
                } catch (_: Exception) {
                } finally {
                    try { p?.destroyForcibly() } catch (_: Exception) { }
                }
            }
        }
    }

    private fun parse(lines: List<String>): Sample {
        val m = HashMap<String, String>()
        for (l in lines) {
            val i = l.indexOf('=')
            if (i > 0) m[l.substring(0, i)] = l.substring(i + 1).trim()
        }
        // FPS: timestamp frame terakhir tidak berubah antar sampel = game macet / layar statis
        val ts = m["last_ts"].orEmpty()
        val x10 = m["fps_x10"]?.toIntOrNull()
        val fps: Float? = when {
            x10 == null || ts.isEmpty() -> null
            ts == prevTs -> 0f
            else -> x10 / 10f
        }
        if (ts.isNotEmpty()) prevTs = ts

        // CPU: "cpu  user nice system idle iowait irq softirq steal ..."
        var cpu: Int? = null
        val parts = m["cpu"].orEmpty().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (parts.size >= 8 && parts[0] == "cpu") {
            val v = parts.drop(1).take(8).map { it.toLongOrNull() ?: 0L }
            val total = v.sum()
            val idle = v[3] + v[4]
            val dt = total - prevCpuTotal
            val di = idle - prevCpuIdle
            if (prevCpuTotal > 0L && dt > 0L) cpu = (((dt - di) * 100) / dt).toInt().coerceIn(0, 100)
            prevCpuTotal = total
            prevCpuIdle = idle
        }

        val gpu = m["gpu"]?.toIntOrNull()?.coerceIn(0, 100)
        val soc = m["soc_mc"]?.toIntOrNull() ?: 0
        val bat = m["temp_mc"]?.toIntOrNull() ?: 0
        val t = (if (soc > 0) soc else bat) / 1000f
        return Sample(fps, gpu, cpu, if (t > 0f) t else null)
    }
}
