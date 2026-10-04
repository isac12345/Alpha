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
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.abs

/**
 * Notifikasi ongoing (profil aktif) + bubble mengambang.
 * Tap bubble: panel pilih profil. Tahan: sembunyikan (munculkan lagi lewat notifikasi).
 * Ukuran/bentuk/opacity dibaca dari Prefs dan berlaku langsung tanpa force stop.
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
    private var bubble: TextView? = null
    private var bubbleLp: WindowManager.LayoutParams? = null
    private var panel: LinearLayout? = null
    private var profile = "none"
    private var tempC = 0f
    private var batt = -1

    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key != null && key.startsWith("bubble_") && key != "bubble_x" && key != "bubble_y") {
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
                    profile = s.profile; tempC = s.tempC; batt = s.batt
                    bubble?.text = profileShort(profile)
                    if (panel != null) showPanel(true)
                    updateNotification()
                }
                delay(8000)
            }
        }
    }

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
        removeBubble()
        scope.cancel()
        super.onDestroy()
    }

    // ---------- profil ----------
    private fun setProfile(p: String) {
        if (p !in PROFILE_KEYS) return
        profile = p
        bubble?.text = profileShort(p)
        updateNotification()
        scope.launch {
            val r = Alpha.setProfile(p)
            Toast.makeText(
                this@BubbleService,
                if (r.ok) "Profil ${profileLabel(p)}" else "Gagal ganti profil",
                Toast.LENGTH_SHORT,
            ).show()
            Alpha.status()?.let { profile = it.profile; tempC = it.tempC; batt = it.batt }
            bubble?.text = profileShort(profile)
            updateNotification()
        }
    }

    // ---------- notifikasi ----------
    private fun createChannel() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val ch = NotificationChannel(CH, "Profil Alpha", NotificationManager.IMPORTANCE_LOW)
        ch.setShowBadge(false)
        nm.createNotificationChannel(ch)
    }

    private fun buildNotification(): Notification {
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val hidden = prefs.bubbleHidden
        val content: PendingIntent = if (hidden) {
            PendingIntent.getService(this, 90, Intent(this, BubbleService::class.java).setAction(ACT_SHOW), flags)
        } else {
            PendingIntent.getActivity(
                this, 91,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                flags,
            )
        }
        val info = buildString {
            if (tempC > 0f) append("%.0f°C".format(tempC))
            if (batt >= 0) { if (isNotEmpty()) append(" · "); append("$batt%") }
        }
        val text = if (hidden) "Bubble disembunyikan · ketuk untuk memunculkan" else info.ifEmpty { "Alpha Fusion" }
        val b = NotificationCompat.Builder(this, CH)
            .setSmallIcon(R.drawable.ic_stat_alpha)
            .setContentTitle("Alpha · ${profileLabel(profile)}")
            .setContentText(text)
            .setContentIntent(content)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        PROFILE_KEYS.forEachIndexed { i, k ->
            val pi = PendingIntent.getService(
                this, 100 + i,
                Intent(this, BubbleService::class.java).setAction(ACT_SET).putExtra(EXTRA_P, k),
                flags,
            )
            b.addAction(0, PROFILE_LABELS[i], pi)
        }
        return b.build()
    }

    private fun updateNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NID, buildNotification())
    }

    // ---------- bubble ----------
    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun removeBubble() {
        bubble?.let { try { wm.removeView(it) } catch (_: Exception) { } }
        bubble = null
        bubbleLp = null
    }

    private fun removePanel() {
        panel?.let { try { wm.removeView(it) } catch (_: Exception) { } }
        panel = null
    }

    private fun rebuild() {
        removePanel()
        removeBubble()
        updateNotification()
        if (prefs.bubbleHidden || !Settings.canDrawOverlays(this)) return

        val size = dp(prefs.bubbleSize)
        val shape = prefs.bubbleShape
        val w = if (shape == 2) (size * 1.5f).toInt() else size
        val h = if (shape == 2) (size * 0.78f).toInt() else size

        val bg = GradientDrawable().apply {
            setColor(0xFFE8E6E1.toInt())
            when (shape) {
                0 -> this.shape = GradientDrawable.OVAL
                1 -> { this.shape = GradientDrawable.RECTANGLE; cornerRadius = dp(10).toFloat() }
                else -> { this.shape = GradientDrawable.RECTANGLE; cornerRadius = h.toFloat() }
            }
        }
        val tv = TextView(this).apply {
            text = profileShort(profile)
            gravity = Gravity.CENTER
            setTextColor(0xFF111111.toInt())
            textSize = 11f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            background = bg
            alpha = prefs.bubbleOpacity / 100f
        }
        val dm = resources.displayMetrics
        val p = WindowManager.LayoutParams(
            w, h, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        p.x = prefs.bubbleX.coerceIn(0, (dm.widthPixels - w).coerceAtLeast(0))
        p.y = prefs.bubbleY.coerceIn(0, (dm.heightPixels - h).coerceAtLeast(0))

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
        tv.setOnTouchListener { v, e ->
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
                    if (moved) snapToEdge(v, p, w, h)
                    else if (!longPressed) { if (panel != null) removePanel() else showPanel(false) }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longRun)
                    true
                }
                else -> false
            }
        }
        try {
            wm.addView(tv, p)
            bubble = tv
            bubbleLp = p
        } catch (_: Exception) {
            bubble = null
        }
    }

    private fun snapToEdge(v: View, p: WindowManager.LayoutParams, w: Int, h: Int) {
        val dm = resources.displayMetrics
        val target = if (p.x + w / 2 < dm.widthPixels / 2) 0 else (dm.widthPixels - w).coerceAtLeast(0)
        p.y = p.y.coerceIn(0, (dm.heightPixels - h).coerceAtLeast(0))
        val anim = ValueAnimator.ofInt(p.x, target)
        anim.duration = 180
        anim.addUpdateListener {
            p.x = it.animatedValue as Int
            if (v.isAttachedToWindow) try { wm.updateViewLayout(v, p) } catch (_: Exception) { }
        }
        anim.addListener(object : android.animation.AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: android.animation.Animator) {
                prefs.bubbleX = p.x
                prefs.bubbleY = p.y
            }
        })
        anim.start()
    }

    // ---------- panel pilih profil ----------
    private fun showPanel(refresh: Boolean) {
        val bp = bubbleLp ?: return
        if (refresh) removePanel()
        if (panel != null) return
        val dm = resources.displayMetrics
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            background = GradientDrawable().apply {
                setColor(0xF0181A1D.toInt()); cornerRadius = dp(24).toFloat()
                setStroke(dp(1), 0x33FFFFFF)
            }
        }
        PROFILE_KEYS.forEachIndexed { i, k ->
            val on = k == profile
            val b = TextView(this).apply {
                text = PROFILE_LABELS[i]
                textSize = 12f
                typeface = Typeface.MONOSPACE
                gravity = Gravity.CENTER
                setPadding(dp(14), dp(10), dp(14), dp(10))
                setTextColor(if (on) 0xFF111111.toInt() else 0xFFE8E6E1.toInt())
                background = GradientDrawable().apply {
                    cornerRadius = dp(20).toFloat()
                    setColor(if (on) 0xFFE8E6E1.toInt() else 0x00000000)
                }
                setOnClickListener { setProfile(k); removePanel() }
            }
            row.addView(b)
        }
        row.setOnTouchListener { _, e ->
            if (e.action == MotionEvent.ACTION_OUTSIDE) { removePanel(); true } else false
        }
        val pw = dp(300)
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        p.x = ((dm.widthPixels - pw) / 2).coerceAtLeast(0)
        val below = bp.y + (bubble?.height ?: bp.height) + dp(8)
        p.y = if (below + dp(60) < dm.heightPixels) below else (bp.y - dp(64)).coerceAtLeast(0)
        try {
            wm.addView(row, p)
            panel = row
        } catch (_: Exception) {
            panel = null
        }
    }
}
