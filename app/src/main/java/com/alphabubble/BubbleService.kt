package com.alphabubble

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.provider.Settings
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

/**
 * Notifikasi ongoing (profil aktif) + SATU overlay floating (FloatingOverlay):
 * ringkas, penuh, merekam, dan bar tipis. Tidak ada bubble/HUD terpisah lagi.
 */
class BubbleService : Service() {
    companion object {
        const val CH = "alpha_profile"
        const val NID = 7
        const val ACT_SET = "com.alphabubble.SET_PROFILE"
        const val ACT_SHOW = "com.alphabubble.SHOW_BUBBLE"
        const val EXTRA_P = "profile"

        fun start(ctx: android.content.Context) {
            ContextCompat.startForegroundService(ctx, Intent(ctx, BubbleService::class.java))
        }

        fun stop(ctx: android.content.Context) {
            ctx.stopService(Intent(ctx, BubbleService::class.java))
        }
    }

    private lateinit var prefs: Prefs
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var floating: FloatingOverlay? = null
    private var profile = "none"
    private var tempC = 0f
    private var batt = -1
    private var gamePkg = ""
    private var hudPkg = ""
    private var recOn = false
    private var protectedFor = ""

    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == null) return@OnSharedPreferenceChangeListener
        if (key.startsWith("fl_") && key != "fl_x_p" && key != "fl_y_p" && key != "fl_x_l" && key != "fl_y_l") {
            floating?.rebuild()
        } else if (key.startsWith("bubble_") && key != "bubble_x" && key != "bubble_y") {
            rebuild()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
        createChannel()
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) startForeground(NID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(NID, n)
        prefs.sp.registerOnSharedPreferenceChangeListener(prefListener)
        val f = FloatingOverlay(this, prefs)
        f.onProfile = { p -> setProfile(p) }
        f.onRec = { toggleRec() }
        f.onHidden = { floating?.detach() }
        floating = f
        rebuild()
        scope.launch {
            while (isActive) {
                val s = Alpha.status()
                if (s != null) {
                    profile = s.profile
                    tempC = s.tempC
                    batt = s.batt
                    gamePkg = s.gamePkg
                    hudPkg = s.hudPkg.ifEmpty { s.gamePkg }
                    // Lindungi proses ini dari pembunuh memori tiap kali game baru terdeteksi (satu panggilan su, bukan tiap siklus).
                    if (hudPkg.isNotEmpty() && hudPkg != protectedFor) {
                        protectedFor = hudPkg
                        protectSelf()
                    }
                    recOn = s.rec
                    floating?.setProfileState(profile, recOn)
                    if (prefs.bubbleHidden || (!prefs.bubbleOn && !prefs.hudOn) || !Settings.canDrawOverlays(this@BubbleService)) {
                        floating?.detach()
                    } else {
                        floating?.setGame(hudPkg)
                    }
                    updateNotification()
                }
                delay(8000)
            }
        }
    }

    /** Turunkan oom_score_adj proses ini (butuh root). Gagal diam-diam: hanya tambahan, bukan syarat jalan. */
    private fun protectSelf() {
        val pid = android.os.Process.myPid()
        scope.launch {
            Root.exec("[ -w /proc/$pid/oom_score_adj ] && echo -300 > /proc/$pid/oom_score_adj", 5_000L)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACT_SET -> intent.getStringExtra(EXTRA_P)?.let { setProfile(it) }
            ACT_SHOW -> {
                prefs.bubbleHidden = false
                rebuild()
                if (hudPkg.isNotEmpty()) floating?.setGame(hudPkg)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        prefs.sp.unregisterOnSharedPreferenceChangeListener(prefListener)
        floating?.release()
        floating = null
        scope.cancel()
        super.onDestroy()
    }

    private fun rebuild() {
        updateNotification()
        if (prefs.bubbleHidden || (!prefs.bubbleOn && !prefs.hudOn) || !Settings.canDrawOverlays(this)) {
            floating?.detach()
            return
        }
        floating?.setProfileState(profile, recOn)
        floating?.attach()
        if (hudPkg.isNotEmpty()) floating?.setGame(hudPkg)
    }

    // ---------- profil ----------
    private fun setProfile(p: String) {
        if (p !in PROFILE_KEYS) return
        profile = p
        floating?.setProfileState(p, recOn)
        updateNotification()
        scope.launch {
            val r = Alpha.setProfile(p)
            Toast.makeText(
                this@BubbleService,
                if (r.ok) "Profil ${profileLabel(p)}" else "Gagal ganti profil",
                Toast.LENGTH_SHORT,
            ).show()
            Alpha.status()?.let {
                profile = it.profile
                tempC = it.tempC
                batt = it.batt
                gamePkg = it.gamePkg
            }
            floating?.setProfileState(profile, recOn)
            updateNotification()
        }
    }

    // ---------- rekam ----------
    private fun toggleRec() {
        val start = !recOn
        scope.launch {
            val r = if (start) Alpha.recStart() else Alpha.recStop()
            if (!r.ok) Toast.makeText(this@BubbleService, "Gagal mengakses rekaman", Toast.LENGTH_SHORT).show()
            Alpha.status()?.let {
                recOn = it.rec
                profile = it.profile
            }
            floating?.setProfileState(profile, recOn)
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
        val line1 = buildString {
            if (batt >= 0) append("Baterai $batt%")
            if (tempC > 0f) { if (isNotEmpty()) append(" · "); append("suhu baterai %.0f°C".format(tempC)) }
        }
        val gameName = if (gamePkg.isNotEmpty()) {
            try { packageManager.getApplicationLabel(packageManager.getApplicationInfo(gamePkg, 0)).toString() } catch (_: Exception) { gamePkg }
        } else ""
        val line2 = if (gameName.isNotEmpty()) "Game jalan: $gameName (profil game dipakai)" else ""
        val text = if (hidden) "Floating disembunyikan · ketuk untuk memunculkan" else line1.ifEmpty { "Alpha Fusion" }
        val big = listOf(text, line2).filter { it.isNotEmpty() }.joinToString("\n")
        val b = NotificationCompat.Builder(this, CH)
            .setSmallIcon(R.drawable.ic_stat_alpha)
            .setContentTitle("Profil aktif: ${profileLabel(profile)}")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(big))
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
            b.addAction(0, (if (k == profile) "● " else "") + PROFILE_LABELS[i], pi)
        }
        return b.build()
    }

    private fun updateNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NID, buildNotification())
    }
}
