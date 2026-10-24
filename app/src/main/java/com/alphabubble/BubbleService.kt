package com.alphabubble

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.animation.ValueAnimator
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Notifikasi ongoing (profil aktif) + satu overlay mengambang gabungan:
 * profil + (bila HUD aktif) FPS/GPU/CPU/suhu + tombol REC.
 * Tap: panel pilih profil. Tahan: sembunyikan (munculkan lagi lewat notifikasi).
 */
class BubbleService : Service() {
    companion object {
        const val CH = "alpha_profile"
        const val NID = 7
        const val ACT_SET = "com.alphabubble.SET_PROFILE"
        const val ACT_SHOW = "com.alphabubble.SHOW_BUBBLE"
        const val EXTRA_P = "profile"

        fun start(ctx: Context) {
            ContextCompat.startForegroundService(ctx, Intent(ctx, BubbleService::class.java))
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, BubbleService::class.java))
        }
    }

    private lateinit var wm: WindowManager
    private lateinit var prefs: Prefs
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val handler = Handler(Looper.getMainLooper())
    private var box: LinearLayout? = null
    private var boxLp: WindowManager.LayoutParams? = null
    private var panel: LinearLayout? = null
    private var profile = "none"
    private var tempC = 0f
    private var gamePkg = ""
    private var hudPkg = ""
    private var recOn = false

    // --- HUD stream (dipindah dari HudOverlay) ---
    private class Sample(val fps: Float?, val gpu: Int?, val cpu: Int?, val tempC: Float?)
    private var fpsTv: TextView? = null
    private var infoTv: TextView? = null
    private var recTv: TextView? = null
    private var game = ""
    private var recording = false
    private var streamJob: Job? = null
    @Volatile private var proc: Process? = null
    @Volatile private var prevTs = ""
    @Volatile private var prevCpuTotal = 0L
    @Volatile private var prevCpuIdle = 0L
    private val pkgRe = Regex("^[A-Za-z0-9._]+\\.[A-Za-z0-9._]+$")

    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key != null && (key.startsWith("bubble_") && key != "bubble_x" && key != "bubble_y")) {
            handler.post { rebuild() }
        } else if (key == "hud_on") {
            handler.post { rebuild() }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        prefs = Prefs(this)
        createChannel()
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) startForeground(NID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(NID, n)
        prefs.sp.registerOnSharedPreferenceChangeListener(prefListener)
        rebuild()
        scope.launch {
            while (isActive) {
                val s = Alpha.status()
                if (s != null) {
                    profile = s.profile; tempC = s.tempC; batt = s.batt; gamePkg = s.gamePkg
                    hudPkg = s.hudPkg.ifEmpty { s.gamePkg }
                    recOn = s.rec
                    if (prefs.hudOn) recording = s.rec
                    if (prefs.hudOn) {
                        val want = hudPkg.isNotEmpty() && pkgRe.matches(hudPkg)
                        if (want) {
                            if (game != hudPkg || fpsTv == null) {
                                stopStream()
                                game = hudPkg
                                startStream(hudPkg)
                            }
                        } else {
                            stopStream()
                            game = ""
                        }
                        updateRecLabel()
                    } else {
                        stopStream()
                        game = ""
                    }
                    box?.let { /* noop: views already wired */ }
                    bubbleText()?.text = profileShort(profile)
                    if (panel != null) showPanel(true)
                    updateNotification()
                }
                delay(8000)
            }
        }
    }

    private var batt = -1

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACT_SET -> intent?.getStringExtra(EXTRA_P)?.let { setProfile(it) }
            ACT_SHOW -> { prefs.bubbleHidden = false; rebuild() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        prefs.sp.unregisterOnSharedPreferenceChangeListener(prefListener)
        handler.removeCallbacksAndMessages(null)
        removePanel()
        removeBox()
        scope.cancel()
        super.onDestroy()
    }

    private fun bubbleText(): TextView? = box?.getChildAt(0) as? TextView

    // ---------- profil ----------
    private fun setProfile(p: String) {
        if (p !in PROFILE_KEYS) return
        profile = p
        bubbleText()?.text = profileShort(p)
        updateNotification()
        scope.launch {
            val r = Alpha.setProfile(p)
            if (r.code != 0) toast(r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
        }
    }

    private fun profileShort(p: String): String = when (p) {
        "battery" -> "BAT"; "balanced" -> "BAL"; "performance" -> "PERF"; else -> "—"
    }

    // ---------- rebuild ----------
    private fun removeBox() {
        stopStream()
        box?.let { try { wm.removeView(it) } catch (_: Exception) { } }
        box = null; boxLp = null
        fpsTv = null; infoTv = null; recTv = null
    }

    private fun rebuild() {
        if (prefs.bubbleHidden) { removeBox(); return }
        removeBox()
        val size = prefs.bubbleSize
        val shape = prefs.bubbleShape
        val w = (size * if (shape == 2) 0.78f else 1f).toInt()
        val h = if (shape == 2) (size * 0.78f).toInt() else size
        val hudOn = prefs.hudOn

        val bg = GradientDrawable().apply {
            setColor(0xB3101214.toInt())
            cornerRadius = dp(10).toFloat()
        }
        val b = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(9), dp(6), dp(9), dp(6))
            background = bg
            alpha = prefs.bubbleOpacity / 100f
        }
        val profileTv = TextView(this).apply {
            text = profileShort(profile)
            setTextColor(0xFFE8E6E1.toInt())
            textSize = 14f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        b.addView(profileTv, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        if (hudOn) {
            val fps = TextView(this).apply {
                text = "-- FPS"
                setTextColor(0xFFE8E6E1.toInt())
                textSize = 16f
                typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            }
            val info = TextView(this).apply {
                text = "GPU --  CPU --"
                setTextColor(0xFFB9B7B0.toInt())
                textSize = 10f
                typeface = Typeface.MONOSPACE
            }
            val rec = TextView(this).apply {
                textSize = 10f
                typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
                setPadding(0, dp(4), 0, 0)
                setOnClickListener { toggleRec() }
            }
            b.addView(fps, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
            b.addView(info, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
            b.addView(rec, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
            fpsTv = fps; infoTv = info; recTv = rec
            updateRecLabel()
        }

        val dm = resources.displayMetrics
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        p.x = prefs.bubbleX.coerceIn(0, (dm.widthPixels - dp(40)).coerceAtLeast(0))
        p.y = prefs.bubbleY.coerceIn(0, (dm.heightPixels - dp(40)).coerceAtLeast(0))

        val slop = ViewConfiguration.get(this).scaledTouchSlop
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0
        var moved = false; var longPressed = false
        val longRun = Runnable {
            if (!moved) {
                longPressed = true
                prefs.bubbleHidden = true
                Toast.makeText(this, "Bubble disembunyikan. Munculkan lagi lewat notifikasi.", Toast.LENGTH_LONG).show()
            }
        }
        b.setOnTouchListener { v, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY; startX = p.x; startY = p.y
                    moved = false; longPressed = false
                    handler.postDelayed(longRun, 650)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (!moved && (abs(dx) > slop || abs(dy) > slop)) {
                        moved = true
                        handler.removeCallbacks(longRun)
                        removePanel()
                    }
                    if (moved) {
                        p.x = (startX + dx).toInt()
                        p.y = (startY + dy).toInt()
                        try { wm.updateViewLayout(v, p) } catch (_: Exception) { }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longRun)
                    if (!moved && !longPressed) {
                        if (panel == null) showPanel(false) else removePanel()
                    }
                    if (moved) { prefs.bubbleX = p.x; prefs.bubbleY = p.y }
                    true
                }
                else -> false
            }
        }
        try {
            wm.addView(b, p)
            box = b; boxLp = p
        } catch (_: Exception) {
            box = null
        }
    }

    // ---------- panel pilih profil ----------
    private fun showPanel(refresh: Boolean) {
        val bp = boxLp ?: return
        if (refresh) removePanel()
        if (panel != null) return
        val dm = resources.displayMetrics
        val boxp = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            background = GradientDrawable().apply {
                setColor(0xF2181A1D.toInt()); cornerRadius = dp(18).toFloat()
                setStroke(dp(1), 0x33FFFFFF)
            }
        }
        PROFILE_KEYS.forEachIndexed { i, k ->
            val on = k == profile
            val item = TextView(this).apply {
                text = PROFILE_LABELS[i]
                textSize = 12f
                typeface = Typeface.create(Typeface.MONOSPACE, if (on) Typeface.BOLD else Typeface.NORMAL)
                gravity = Gravity.CENTER
                setPadding(dp(10), dp(11), dp(10), dp(11))
                setTextColor(if (on) 0xFF111111.toInt() else 0xFFE8E6E1.toInt())
                background = GradientDrawable().apply {
                    cornerRadius = dp(14).toFloat()
                    setColor(if (on) 0xFFE8E6E1.toInt() else 0x00000000)
                }
                setOnClickListener { setProfile(k); removePanel() }
            }
            boxp.addView(item, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        }
        boxp.setOnTouchListener { _, e ->
            if (e.action == MotionEvent.ACTION_OUTSIDE) { removePanel(); true } else false
        }
        val pw = dp(128)
        val p = WindowManager.LayoutParams(
            pw, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        val bw = bp.width
        p.x = if (bp.x + bw / 2 < dm.widthPixels / 2) bp.x + bw + dp(8) else (bp.x - pw - dp(8)).coerceAtLeast(0)
        p.y = bp.y.coerceAtMost((dm.heightPixels - dp(150)).coerceAtLeast(0))
        try {
            wm.addView(boxp, p)
            panel = boxp
        } catch (_: Exception) {
            panel = null
        }
    }

    private fun removePanel() {
        panel?.let { try { wm.removeView(it) } catch (_: Exception) { } }
        panel = null
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val c = NotificationChannel(CH, "Alpha Fusion", NotificationManager.IMPORTANCE_LOW)
            c.description = "Profil aktif"; c.setShowBadge(false)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(c)
        }
    }

    private fun buildNotification(): Notification {
        val pi = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CH)
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setContentTitle("Alpha Fusion")
            .setContentText("Profil: ${profileShort(profile)}")
            .setContentIntent(pi)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification() {
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NID, buildNotification())
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()

    // ---------- HUD stream (single overlay) ----------
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
            Toast.makeText(this@BubbleService, r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal", Toast.LENGTH_SHORT).show()
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

    private fun parse(lines: List<String>): Sample {
        val m = HashMap<String, String>()
        for (l in lines) {
            val i = l.indexOf('=')
            if (i > 0) m[l.substring(0, i)] = l.substring(i + 1).trim()
        }
        val ts = m["last_ts"].orEmpty()
        val x10 = m["fps_x10"]?.toIntOrNull()
        val fps: Float? = when {
            x10 == null || ts.isEmpty() -> null
            ts == prevTs -> 0f
            else -> x10 / 10f
        }
        if (ts.isNotEmpty()) prevTs = ts
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

    private fun startStream(pkg: String) {
        prevTs = ""; prevCpuTotal = 0L; prevCpuIdle = 0L
        streamJob = scope.launch {
            val mod = Root.modPath()
            if (mod.isEmpty()) return@launch
            withContext(Dispatchers.IO) {
                var p: Process? = null
                try {
                    p = ProcessBuilder("su", "-c", "sh $mod/common/hud_sample.sh --loop $pkg")
                        .redirectErrorStream(true).start()
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

    private fun stopStream() {
        streamJob?.cancel()
        streamJob = null
        try { proc?.destroyForcibly() } catch (_: Exception) { }
        proc = null
        prevTs = ""; prevCpuTotal = 0L; prevCpuIdle = 0L
    }

        }
