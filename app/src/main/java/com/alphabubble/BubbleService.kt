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
import kotlinx.coroutines.Job
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
        const val ACT_FPSLOG = "com.alphabubble.FPS_LOG"
        const val EXTRA_P = "profile"

        private const val WANT = "/data/adb/alpha/.bubble_want"

        /** Penanda untuk watchdog modul: "floating harus hidup". Dihapus saat pengguna mematikannya. */
        private fun mark(on: Boolean) {
            kotlin.concurrent.thread(isDaemon = true) {
                Root.execBlocking(if (on) "mkdir -p /data/adb/alpha; : > $WANT" else "rm -f $WANT", 8_000L)
            }
        }

        fun start(ctx: android.content.Context) {
            mark(true)
            ContextCompat.startForegroundService(ctx, Intent(ctx, BubbleService::class.java))
        }

        fun stop(ctx: android.content.Context) {
            mark(false)
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
    private var flJob: Job? = null

    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == null) return@OnSharedPreferenceChangeListener
        if (key.startsWith("fl_") && key != "fl_x_p" && key != "fl_y_p" && key != "fl_x_l" && key != "fl_y_l") {
            // slider mengirim puluhan perubahan per detik: gabungkan jadi satu rebuild setelah 150 ms tenang
            flJob?.cancel()
            flJob = scope.launch { delay(150); floating?.rebuild() }
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
        harden()
        screenOn = object : android.content.BroadcastReceiver() {
            override fun onReceive(c: android.content.Context?, i: Intent?) {
                // layar menyala / buka kunci: pasang floating lagi seketika, tanpa menunggu siklus 8 dtk
                rebuild()
            }
        }
        val flt = android.content.IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON); addAction(Intent.ACTION_USER_PRESENT)
        }
        ContextCompat.registerReceiver(this, screenOn, flt, ContextCompat.RECEIVER_NOT_EXPORTED)
        val f = FloatingOverlay(this, prefs)
        f.onProfile = { p -> setProfile(p) }
        f.onRec = { toggleRec() }
        f.onOvd = { on -> toggleOvd(on) }
        f.onSession = { st ->
            prefs.fpsSessions = listOf(st) + prefs.fpsSessions
            val mode = if (st.ovdPct >= 50) "Overdrive" else profileLabel(st.profile)
            Toast.makeText(this, "Sesi selesai ($mode): rata-rata ${st.avg} FPS, 1% terendah ${st.low1} FPS", Toast.LENGTH_LONG).show()
        }
        f.onHidden = { floating?.detach() }
        floating = f
        rebuild()
        scope.launch {
            while (isActive) {
                val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                if (!pm.isInteractive) {
                    // layar mati: tidak perlu memanggil su; cukup segarkan notifikasi dari baterai sistem
                    // hentikan aliran HUD (proses su + dumpsys) selama layar mati
                    floating?.detach()
                    readBattery(); updateNotification()
                    var w = 0
                    while (isActive && !pm.isInteractive && w < 15) { delay(2000); w++ }
                    continue
                }
                val s = Alpha.status()
                if (s == null) {
                    // status gagal/lambat: floating tetap dipastikan ada (jangan hilang menunggu su)
                    if (!(prefs.bubbleHidden || (!prefs.bubbleOn && !prefs.hudOn) || !Settings.canDrawOverlays(this@BubbleService))) floating?.setGame("auto")
                }
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
                    floating?.setOvd(s.ovd, s.ovdLevel, s.gamePkg.isNotEmpty())
                    floating?.setSession(s.gamePkg)
                    floating?.setProfileState(profile, recOn)
                    if (prefs.bubbleHidden || (!prefs.bubbleOn && !prefs.hudOn) || !Settings.canDrawOverlays(this@BubbleService)) {
                        floating?.detach()
                    } else {
                        floating?.setGame("auto")
                    }
                }
                // baterai/suhu selalu dari sistem (tanpa su) supaya notifikasi tidak basi walau status gagal/lambat
                readBattery()
                updateNotification()
                delay(8000)
            }
        }
    }

    private var screenOn: android.content.BroadcastReceiver? = null

    /** Minta sistem jangan membekukan/membunuh service ini: whitelist hemat daya, bucket aktif, oom. Butuh root, gagal diam-diam. */
    private fun harden() {
        val pkg = packageName
        val pid = android.os.Process.myPid()
        scope.launch {
            Root.exec(
                "dumpsys deviceidle whitelist +$pkg >/dev/null 2>&1; " +
                    "cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1; " +
                    "cmd appops set $pkg RUN_IN_BACKGROUND allow >/dev/null 2>&1; " +
                    "am set-standby-bucket $pkg active >/dev/null 2>&1; " +
                    "[ -w /proc/$pid/oom_score_adj ] && echo -500 > /proc/$pid/oom_score_adj; true",
                10_000L,
            )
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
            ACT_FPSLOG -> {
                // layar Performa di app: mulai/berhenti rekam data FPS; pastikan floating terpasang (aliran HUD)
                if (!FpsLog.on) { prefs.bubbleHidden = false; rebuild() }
                floating?.toggleFpsLog()
            }
            ACT_SHOW -> {
                prefs.bubbleHidden = false
                rebuild()
                floating?.setGame("auto")
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        prefs.sp.unregisterOnSharedPreferenceChangeListener(prefListener)
        try { screenOn?.let { unregisterReceiver(it) } } catch (_: Exception) {}
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
        floating?.setGame("auto")
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
    private fun toggleOvd(on: Boolean) {
        scope.launch {
            val r = if (on) Alpha.ovdStart() else Alpha.ovdStop()
            if (on && !r.ok) {
                val msg = r.out.lines().firstOrNull { it.startsWith("ERROR") }?.removePrefix("ERROR:")?.trim() ?: "Overdrive gagal"
                Toast.makeText(this@BubbleService, msg, Toast.LENGTH_LONG).show()
            }
            Alpha.status()?.let { floating?.setOvd(it.ovd, it.ovdLevel, it.gamePkg.isNotEmpty()) }
        }
    }

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
            .setShowWhen(false)
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

    private fun readBattery() {
        try {
            val i = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return
            val lv = i.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1)
            val sc = i.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, 100)
            if (lv >= 0 && sc > 0) batt = lv * 100 / sc
            val t = i.getIntExtra(android.os.BatteryManager.EXTRA_TEMPERATURE, -1)
            if (t > 0) tempC = t / 10f
        } catch (_: Exception) {}
    }

    private fun updateNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NID, buildNotification())
    }
}
