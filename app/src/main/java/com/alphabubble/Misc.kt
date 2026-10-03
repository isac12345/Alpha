package com.alphabubble

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

class BubbleService : Service() {
    companion object {
        const val CH = "alpha_bubble"
        const val ACT_SHOW = "alpha.show"
        const val ACT_REFRESH = "alpha.refresh"
        const val NID = 71

        fun prefs(c: Context): SharedPreferences = c.getSharedPreferences("alpha", Context.MODE_PRIVATE)

        fun start(c: Context, action: String? = null) {
            val i = Intent(c, BubbleService::class.java)
            if (action != null) i.action = action
            if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i) else c.startService(i)
        }

        fun stop(c: Context) {
            c.stopService(Intent(c, BubbleService::class.java))
        }
    }

    private lateinit var wm: WindowManager
    private var bubble: TextView? = null
    private var panel: View? = null
    private var profile = ""
    private var polling = false
    private val h = Handler(Looper.getMainLooper())

    private val poll = object : Runnable {
        override fun run() {
            Sh.bg {
                Alpha.ensure()
                val p = Alpha.currentProfile()
                Sh.ui.post {
                    if (p != profile) {
                        profile = p
                        update()
                    }
                }
            }
            h.postDelayed(this, 10000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CH, "Alpha", NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NID, buildNotif())
        val p = prefs(this)
        when (intent?.action) {
            ACT_SHOW -> {
                p.edit().putBoolean("bubble_visible", true).apply()
                showBubble()
            }
            ACT_REFRESH -> {
                val wasShown = bubble != null
                hideBubble(false)
                if (wasShown || p.getBoolean("bubble_visible", true)) showBubble()
            }
            else -> if (p.getBoolean("bubble_visible", true)) showBubble()
        }
        if (!polling) {
            polling = true
            h.post(poll)
        }
        return START_STICKY
    }

    private fun buildNotif(): Notification {
        val showI = Intent(this, BubbleService::class.java).setAction(ACT_SHOW)
        val fl = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val pi = if (Build.VERSION.SDK_INT >= 26) PendingIntent.getForegroundService(this, 1, showI, fl)
        else PendingIntent.getService(this, 1, showI, fl)
        val open = PendingIntent.getActivity(this, 2, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val act = Notification.Action.Builder(Icon.createWithResource(this, R.drawable.ic_stat), "Buka", open).build()
        return Notification.Builder(this, CH)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Alpha")
            .setContentText("Profil: " + Alpha.profileTitle(profile))
            .setOngoing(true)
            .setContentIntent(pi)
            .addAction(act)
            .build()
    }

    private fun update() {
        bubble?.text = when (profile) {
            "battery" -> "BAT"
            "balanced" -> "BAL"
            "performance" -> "PERF"
            else -> "α"
        }
        getSystemService(NotificationManager::class.java).notify(NID, buildNotif())
    }

    private fun showBubble() {
        if (bubble != null) return
        if (!Settings.canDrawOverlays(this)) return
        val p = prefs(this)
        val size = dp(p.getInt("bubble_size", 52))
        val shapeIdx = p.getInt("bubble_shape", 0)
        val width = if (shapeIdx == 2) (size * 1.6f).toInt() else size

        val t = TextView(this)
        t.gravity = Gravity.CENTER
        t.textSize = 10f
        t.setTextColor(C.DARK)
        t.typeface = android.graphics.Typeface.create(android.graphics.Typeface.MONOSPACE, android.graphics.Typeface.BOLD)
        val g = GradientDrawable()
        g.setColor(C.TX)
        when (shapeIdx) {
            0 -> g.shape = GradientDrawable.OVAL
            1 -> g.cornerRadius = dp(12).toFloat()
            else -> g.cornerRadius = size / 2f
        }
        t.background = g

        val lpw = WindowManager.LayoutParams(
            width, size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        lpw.gravity = Gravity.TOP or Gravity.START
        lpw.x = p.getInt("bubble_x", dp(8))
        lpw.y = p.getInt("bubble_y", dp(200))

        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        var longFired = false
        val longRun = Runnable {
            longFired = true
            hideBubble(true)
        }
        t.setOnTouchListener { v, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY
                    startX = lpw.x; startY = lpw.y
                    moved = false; longFired = false
                    h.postDelayed(longRun, 700L)
                }
                MotionEvent.ACTION_MOVE -> {
                    val mx = e.rawX - downX
                    val my = e.rawY - downY
                    if (!moved && (abs(mx) > dp(6) || abs(my) > dp(6))) {
                        moved = true
                        h.removeCallbacks(longRun)
                        closePanel()
                    }
                    if (moved) {
                        lpw.x = (startX + mx).toInt()
                        lpw.y = (startY + my).toInt()
                        try { wm.updateViewLayout(v, lpw) } catch (_: Exception) { }
                    }
                }
                MotionEvent.ACTION_UP -> {
                    h.removeCallbacks(longRun)
                    if (moved) {
                        prefs(this).edit().putInt("bubble_x", lpw.x).putInt("bubble_y", lpw.y).apply()
                    } else if (!longFired) {
                        if (panel != null) closePanel() else openPanel(lpw, width)
                    }
                }
                MotionEvent.ACTION_CANCEL -> h.removeCallbacks(longRun)
            }
            true
        }
        try {
            wm.addView(t, lpw)
            bubble = t
            update()
        } catch (_: Exception) { }
    }

    private fun hideBubble(persist: Boolean) {
        closePanel()
        bubble?.let { try { wm.removeView(it) } catch (_: Exception) { } }
        bubble = null
        if (persist) prefs(this).edit().putBoolean("bubble_visible", false).apply()
    }

    private fun openPanel(bp: WindowManager.LayoutParams, bubbleW: Int) {
        val box = LinearLayout(this)
        box.orientation = LinearLayout.VERTICAL
        box.background = shape(C.CARD, 18, C.BTN_LINE, 1)
        box.setPadding(dp(6), dp(6), dp(6), dp(6))
        val items = listOf("BATTERY" to "battery", "BALANCED" to "balanced", "PERF" to "performance")
        for ((name, key) in items) {
            val t = tv(name, 11f, if (key == profile) C.DARK else C.TX, key == profile)
            t.gravity = Gravity.CENTER
            t.setPadding(dp(10), dp(11), dp(10), dp(11))
            if (key == profile) t.background = shape(C.TX, 14)
            t.setOnClickListener {
                profile = key
                update()
                closePanel()
                Sh.bg {
                    Alpha.ensure()
                    Alpha.applyProfile(key)
                    val cur = Alpha.currentProfile()
                    Sh.ui.post {
                        if (cur.isNotEmpty()) profile = cur
                        update()
                    }
                }
            }
            box.addView(t, lp(MATCH, WRAP))
        }
        val pw = dp(130)
        val screenW = resources.displayMetrics.widthPixels
        val pl = WindowManager.LayoutParams(
            pw, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        )
        pl.gravity = Gravity.TOP or Gravity.START
        pl.x = if (bp.x < screenW / 2) bp.x + bubbleW + dp(8) else bp.x - pw - dp(8)
        pl.y = bp.y
        box.setOnTouchListener { _, e ->
            if (e.action == MotionEvent.ACTION_OUTSIDE) closePanel()
            false
        }
        try {
            wm.addView(box, pl)
            panel = box
        } catch (_: Exception) { }
    }

    private fun closePanel() {
        panel?.let { try { wm.removeView(it) } catch (_: Exception) { } }
        panel = null
    }

    override fun onDestroy() {
        h.removeCallbacksAndMessages(null)
        hideBubble(false)
        super.onDestroy()
    }
}

class ProfileTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        Sh.bg {
            Alpha.ensure()
            val p = Alpha.currentProfile()
            Sh.ui.post { paint(p) }
        }
    }

    private fun paint(p: String) {
        val t = qsTile ?: return
        t.label = "Alpha: " + Alpha.profileTitle(p)
        t.state = Tile.STATE_ACTIVE
        t.updateTile()
    }

    override fun onClick() {
        super.onClick()
        Sh.bg {
            Alpha.ensure()
            val cur = Alpha.currentProfile()
            val next = when (cur) {
                "battery" -> "balanced"
                "balanced" -> "performance"
                else -> "battery"
            }
            Alpha.applyProfile(next)
            Sh.ui.post { paint(next) }
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        if (i.action != Intent.ACTION_BOOT_COMPLETED) return
        val p = BubbleService.prefs(c)
        if (p.getBoolean("autostart", true) && p.getBoolean("bubble_on", false)) {
            try { BubbleService.start(c) } catch (_: Exception) { }
        }
    }
}
