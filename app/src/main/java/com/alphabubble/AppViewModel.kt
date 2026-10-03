package com.alphabubble

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive

class AppViewModel(private val app: Application) : AndroidViewModel(app) {
    val prefs = Prefs(app)
    private val pm: PackageManager = app.packageManager

    // ---------- navigasi ----------
    var route by mutableStateOf("dash")
    var editPkg by mutableStateOf("")
    private val parents = mapOf(
        "auto" to "dash", "therm" to "dash",
        "stats" to "games", "detect" to "games", "edit" to "games", "addgame" to "games",
        "bgbanner" to "custom", "bubble" to "custom", "theme" to "custom",
        "dexopt" to "tools", "batlab" to "tools", "fulllog" to "tools",
    )
    val tab: String get() = parents[route] ?: route

    fun go(r: String) {
        route = r
        when (r) {
            "games", "stats" -> viewModelScope.launch { games = Alpha.games(); sessions = Alpha.sessions() }
            "tools" -> viewModelScope.launch { refreshTools() }
            "batlab" -> viewModelScope.launch { battery = Alpha.battery() }
            "fulllog" -> viewModelScope.launch { loadFullLog() }
            "addgame", "detect" -> ensureApps()
            "dexopt" -> ensureThirdParty()
            "dash", "therm" -> viewModelScope.launch { flags = Alpha.flags() }
            "auto" -> viewModelScope.launch { conf = Alpha.conf() }
        }
    }

    fun back(): Boolean {
        val p = parents[route] ?: return false
        route = p
        return true
    }

    // ---------- state modul ----------
    var rootOk by mutableStateOf(false)
    var modPath by mutableStateOf("")
    var loaded by mutableStateOf(false)
    var status by mutableStateOf(Status())
    var conf by mutableStateOf<Map<String, String>>(emptyMap())
    var flags by mutableStateOf<Map<String, Boolean>>(emptyMap())
    var games by mutableStateOf<List<GameEntry>>(emptyList())
    var sessions by mutableStateOf<List<SessionEntry>>(emptyList())
    var health by mutableStateOf(Health())
    var device by mutableStateOf<Map<String, String>>(emptyMap())
    var render by mutableStateOf(RenderInfo())
    var renderChoice by mutableStateOf("default")
    var logs by mutableStateOf<List<LogLine>>(emptyList())
    var logFilter by mutableStateOf("ALL")
    var battery by mutableStateOf(BatteryInfo())
    var msg by mutableStateOf<String?>(null)
    var dialog by mutableStateOf<Dlg?>(null)
    var busy by mutableStateOf<String?>(null)
    var askOverlay by mutableStateOf(false)

    // ---------- tampilan ----------
    var cardAlpha by mutableStateOf(prefs.cardAlpha)
    var fit by mutableStateOf(prefs.fit)
    var accent by mutableStateOf(prefs.accent)
    var blur by mutableStateOf(prefs.blur)
    var contrast by mutableStateOf(prefs.contrast)
    var saver by mutableStateOf(prefs.saver)
    var bgVer by mutableStateOf(prefs.bgVer)
    var bannerVer by mutableStateOf(prefs.bannerVer)
    var bubbleOn by mutableStateOf(prefs.bubbleOn)
    var bubbleSize by mutableStateOf(prefs.bubbleSize)
    var bubbleShape by mutableStateOf(prefs.bubbleShape)
    var bubbleOpacity by mutableStateOf(prefs.bubbleOpacity)
    var autostart by mutableStateOf(prefs.autostart)

    fun setCardAlpha(v: Float) { cardAlpha = v; prefs.cardAlpha = v }
    fun setFit(v: Int) { fit = v; prefs.fit = v }
    fun setAccent(v: Int) { accent = v; prefs.accent = v }
    fun setBlur(v: Int) { blur = v; prefs.blur = v }
    fun setContrast(v: Int) { contrast = v; prefs.contrast = v }
    fun setSaver(v: Boolean) { saver = v; prefs.saver = v }
    fun setBubbleSize(v: Int) { bubbleSize = v; prefs.bubbleSize = v }
    fun setBubbleShape(v: Int) { bubbleShape = v; prefs.bubbleShape = v }
    fun setBubbleOpacity(v: Int) { bubbleOpacity = v; prefs.bubbleOpacity = v }
    fun setAutostart(v: Boolean) { autostart = v; prefs.autostart = v }

    fun setBubbleOn(on: Boolean) {
        if (on) {
            if (!Settings.canDrawOverlays(app)) {
                askOverlay = true
                toast("Izinkan 'tampil di atas app lain' dulu")
                return
            }
            prefs.bubbleHidden = false
            prefs.bubbleOn = true
            bubbleOn = true
            BubbleService.start(app)
        } else {
            prefs.bubbleOn = false
            bubbleOn = false
            BubbleService.stop(app)
        }
    }

    // ---------- util ----------
    private var toastJob: Job? = null
    fun toast(s: String) {
        msg = s
        toastJob?.cancel()
        toastJob = viewModelScope.launch { delay(2600); msg = null }
    }

    fun label(pkg: String): String = try {
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { pkg }

    // ---------- siklus hidup & polling ----------
    @Volatile var visible = false
    private var autoEnsured = false
    private var tick = 0

    init {
        viewModelScope.launch {
            bootstrap()
            while (true) {
                delay(3000)
                if (!visible || !rootOk) continue
                tick++
                refreshStatus()
                when (route) {
                    "batlab" -> battery = Alpha.battery()
                    "tools" -> if (tick % 2 == 0) { Alpha.health()?.let { health = it }; loadRecentLog() }
                }
            }
        }
    }

    private suspend fun bootstrap() {
        rootOk = Root.hasRoot()
        if (rootOk) {
            modPath = Root.modPath(true)
            if (modPath.isNotEmpty()) refreshAll()
        }
        loaded = true
        if (prefs.bubbleOn && Settings.canDrawOverlays(app)) BubbleService.start(app)
    }

    suspend fun refreshAll() {
        refreshStatus()
        conf = Alpha.conf()
        flags = Alpha.flags()
        games = Alpha.games()
        sessions = Alpha.sessions()
        Alpha.health()?.let { health = it }
        device = Alpha.device()
        Alpha.render()?.let { render = it; renderChoice = it.current }
        refreshRes()
        loadRecentLog()
    }

    private suspend fun refreshTools() {
        Alpha.health()?.let { health = it }
        flags = Alpha.flags()
        device = Alpha.device()
        refreshRes()
        loadRecentLog()
    }

    suspend fun refreshStatus() {
        val s = Alpha.status() ?: return
        status = s
        if (!s.auto && !autoEnsured) {
            autoEnsured = true
            Alpha.autoStart()
        } else if (s.auto) autoEnsured = true
    }

    private suspend fun loadRecentLog() { logs = Alpha.parseLog(Alpha.logRaw(300)) }
    private suspend fun loadFullLog() { logs = Alpha.parseLog(Alpha.logRaw(800)) }

    // ---------- profil ----------
    fun setProfile(p: String) {
        viewModelScope.launch {
            status = status.copy(profile = p, active = p)
            val r = Alpha.setProfile(p)
            toast(if (r.ok) "Profil ${profileLabel(p)} diterapkan" else "Gagal ganti profil: ${r.out.take(60)}")
            refreshStatus()
        }
    }

    // ---------- flag & thermal & auto ----------
    fun flag(name: String): Boolean = flags[name] == true

    fun setFlag(name: String, on: Boolean) {
        viewModelScope.launch {
            flags = flags + (name to on)
            if (!Alpha.setFlag(name, on)) toast("Gagal menyimpan pengaturan")
            flags = Alpha.flags()
        }
    }

    fun setThermalWarm(c: Int) {
        viewModelScope.launch {
            if (Alpha.setThermalWarm(c)) { status = status.copy(thermalWarmC = c); toast("Batas suhu $c°C disimpan") }
            else toast("Gagal menyimpan batas suhu")
        }
    }

    fun setBootGuard(on: Boolean) {
        viewModelScope.launch {
            health = health.copy(bootGuard = on)
            Alpha.setFlag("BOOT_GUARD_OFF", !on)
            Alpha.health()?.let { health = it }
            toast(if (on) "Boot guard aktif" else "Boot guard dimatikan")
        }
    }

    fun confStr(k: String, d: String): String = conf[k] ?: d

    fun saveAuto(battOn: Boolean, pct: Int, battProf: String, chgOn: Boolean, chgProf: String) {
        viewModelScope.launch {
            val ok = Alpha.setConf("AUTO_BATT_ON", if (battOn) "1" else "0") &&
                Alpha.setConf("AUTO_BATT_PCT", pct.toString()) &&
                Alpha.setConf("AUTO_BATT_PROFILE", battProf) &&
                Alpha.setConf("AUTO_CHG_ON", if (chgOn) "1" else "0") &&
                Alpha.setConf("AUTO_CHG_PROFILE", chgProf)
            conf = Alpha.conf()
            Alpha.autoStart()
            toast(if (ok) "Aturan auto-profile tersimpan" else "Sebagian gagal disimpan")
        }
    }

    // ---------- game ----------
    fun addGame(pkg: String, fps: String, profile: String, after: () -> Unit = {}) {
        viewModelScope.launch {
            busy = "Menyimpan game..."
            val r = Alpha.addGame(pkg, fps, profile)
            games = Alpha.games()
            busy = null
            if (r.out.startsWith("OK")) { toast("${label(pkg)} disimpan"); after() }
            else toast(r.out.lineSequence().firstOrNull { it.startsWith("ERROR") } ?: "Gagal menyimpan game")
        }
    }

    fun addGames(pkgs: List<String>, profile: String, after: () -> Unit = {}) {
        viewModelScope.launch {
            busy = "Menambah ${pkgs.size} game..."
            var ok = 0
            for (p in pkgs) if (Alpha.addGame(p, "", profile).out.startsWith("OK")) ok++
            games = Alpha.games()
            busy = null
            toast("$ok game ditambahkan")
            after()
        }
    }

    fun removeGame(pkg: String) {
        viewModelScope.launch {
            busy = "Menghapus..."
            Alpha.removeGame(pkg)
            games = Alpha.games()
            busy = null
            toast("${label(pkg)} dihapus")
        }
    }

    // ---------- daftar app (tanpa root) ----------
    var apps by mutableStateOf<List<AppItem>>(emptyList())
    private var appsLoading = false

    private val gamePrefixes = listOf(
        "com.kurogame.", "com.mihoyo.", "com.miHoYo.", "com.HoYoverse.", "com.hoyoverse.", "com.tencent.ig",
        "com.tencent.tmgp", "com.pubg", "com.activision.", "com.mobile.legends", "com.moonton.", "com.garena.",
        "com.supercell.", "com.proximabeta", "com.netease.", "com.levelinfinite.", "com.hypergryph.",
        "com.YoStarEN.", "com.YoStarJP.", "com.epicgames.", "com.riotgames.", "com.roblox.", "com.mojang.",
        "com.innersloth.", "com.dts.freefire", "com.nexon.", "com.gryphline.", "com.lilithgames.", "com.sunborn.",
        "com.habby.", "com.fantome.", "com.ea.", "com.gameloft.", "com.king.", "com.zhiliaoapp.musically.go",
    )

    @Suppress("DEPRECATION")
    private fun isGameApp(ai: ApplicationInfo): Boolean {
        if (ai.category == ApplicationInfo.CATEGORY_GAME) return true
        if ((ai.flags and ApplicationInfo.FLAG_IS_GAME) != 0) return true
        return gamePrefixes.any { ai.packageName.startsWith(it) }
    }

    fun ensureApps() {
        if (apps.isNotEmpty() || appsLoading) return
        appsLoading = true
        viewModelScope.launch {
            apps = withContext(Dispatchers.IO) {
                val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                pm.queryIntentActivities(i, 0)
                    .map { it.activityInfo.applicationInfo }
                    .distinctBy { it.packageName }
                    .filter { it.packageName != app.packageName }
                    .map { AppItem(it.packageName, pm.getApplicationLabel(it).toString(), isGameApp(it)) }
                    .sortedWith(compareByDescending<AppItem> { it.isGame }.thenBy { it.label.lowercase() })
            }
            appsLoading = false
        }
    }

    fun loadThirdParty(): List<AppItem> =
        pm.getInstalledApplications(0)
            .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 && it.packageName != app.packageName }
            .map { AppItem(it.packageName, pm.getApplicationLabel(it).toString(), isGameApp(it)) }
            .sortedBy { it.label.lowercase() }

    var thirdParty by mutableStateOf<List<AppItem>>(emptyList())

    fun ensureThirdParty() {
        if (thirdParty.isNotEmpty()) return
        viewModelScope.launch { thirdParty = withContext(Dispatchers.IO) { loadThirdParty() } }
    }

    // ---------- render ----------
    fun applyRender() {
        viewModelScope.launch {
            busy = "Mengganti render..."
            val r = Alpha.setRender(renderChoice)
            busy = null
            Alpha.render()?.let { render = it }
            dialog = Dlg.Info(
                "Render", r.out.ifEmpty { "Selesai" },
                if (r.out.startsWith("OK")) "TUTUP SEMUA APP" else null,
                if (r.out.startsWith("OK")) ({ askCloseApps() }) else null,
            )
        }
    }

    // ---------- resolusi ----------
    var resInfo by mutableStateOf<Alpha.ResInfo?>(null)
    var resPct by mutableStateOf(100)
    var resCountdown by mutableStateOf(0)
    private var resJob: Job? = null
    private var resRestore: String = ""

    suspend fun refreshRes() {
        val r = Alpha.resolution() ?: return
        resInfo = r
        if (resCountdown == 0) {
            val pct = Math.round(r.act.w * 100f / r.nat.w)
            resPct = listOf(60, 70, 80, 90, 100).minByOrNull { kotlin.math.abs(it - pct) } ?: 100
        }
    }

    fun applyRes() {
        val info = resInfo ?: run { toast("Info layar belum terbaca"); return }
        resJob?.cancel()
        resRestore = Alpha.restoreCommand(info)
        val target = Alpha.resCommand(info.nat, resPct)
        resJob = viewModelScope.launch {
            resCountdown = 10
            Alpha.applyResWithGuard(target, resRestore, 13)
            refreshRes()
            var n = 10
            while (n > 0 && resCountdown > 0) {
                delay(1000)
                n--
                resCountdown = n
            }
            if (resCountdown == 0 && n == 0) {
                Alpha.revertRes(resRestore)
                refreshRes()
                toast("Tidak dikonfirmasi, resolusi dikembalikan")
            }
        }
    }

    fun keepRes() {
        resJob?.cancel()
        resCountdown = 0
        viewModelScope.launch { Alpha.keepRes(); refreshRes(); toast("Resolusi dipertahankan") }
    }

    fun revertRes() {
        resJob?.cancel()
        resCountdown = 0
        viewModelScope.launch { Alpha.revertRes(resRestore.ifEmpty { "wm size reset; wm density reset" }); refreshRes(); toast("Resolusi dikembalikan") }
    }

    fun resetRes() {
        resJob?.cancel()
        resCountdown = 0
        viewModelScope.launch { Alpha.resetRes(); refreshRes(); toast("Resolusi direset") }
    }

    // ---------- tutup semua app ----------
    private val protectedExact = setOf(
        "android", "com.android.systemui", "com.android.phone", "com.android.server.telecom",
        "com.android.bluetooth", "com.android.nfc", "com.android.shell", "com.android.keychain",
        "com.android.se", "com.google.android.gms", "com.google.android.gsf",
        "com.topjohnwu.magisk", "me.weishu.kernelsu", "com.rifsxd.ksunext", "me.bmax.apatch",
    )
    private val protectedContains = listOf(
        "dialer", "telecom", "incallui", "inputmethod", "keyboard", "launcher", "systemui", "wallpaper",
        "permissioncontroller", "packageinstaller", "bluetooth", "nfc", "emergency", "clock", "alarm", "calendar",
    )

    private fun protectedPackages(): Set<String> {
        val s = HashSet<String>(protectedExact)
        s.add(app.packageName)
        try {
            val home = pm.resolveActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), PackageManager.MATCH_DEFAULT_ONLY)
            home?.activityInfo?.packageName?.let { s.add(it) }
        } catch (_: Exception) { }
        try {
            val ime = Settings.Secure.getString(app.contentResolver, "default_input_method")
            if (!ime.isNullOrEmpty()) s.add(ime.substringBefore('/'))
        } catch (_: Exception) { }
        return s
    }

    private fun systemLaunchables(prot: Set<String>): List<String> {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(i, 0)
            .map { it.activityInfo.applicationInfo }
            .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) != 0 }
            .map { it.packageName }
            .distinct()
            .filter { p -> p !in prot && protectedContains.none { p.contains(it, ignoreCase = true) } }
    }

    fun askCloseApps() {
        dialog = Dlg.Confirm(
            title = "Tutup semua app",
            text = "Semua app yang terbuka ditutup, termasuk game yang sedang jalan. Alpha Control tidak ikut ditutup.",
            okLabel = "TUTUP",
            checkLabel = "Termasuk app sistem (bukan layanan inti)",
            checkDefault = true,
            onOk = { includeSystem -> closeApps(includeSystem) },
        )
    }

    private fun closeApps(includeSystem: Boolean) {
        viewModelScope.launch {
            busy = "Menutup app..."
            val prot = protectedPackages()
            val third = withContext(Dispatchers.IO) {
                pm.getInstalledApplications(0)
                    .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 }
                    .map { it.packageName }
                    .filter { it !in prot }
            }
            val sys = if (includeSystem) withContext(Dispatchers.IO) { systemLaunchables(prot) } else emptyList()
            val all = third + sys
            Alpha.forceStop(all)
            busy = null
            toast("${all.size} app ditutup" + if (includeSystem) " (${sys.size} sistem)" else "")
        }
    }

    // ---------- dexopt ----------
    var dexMode by mutableStateOf("speed-profile")
    var dexSel by mutableStateOf<Set<String>>(emptySet())
    var dexRunning by mutableStateOf(false)
    var dexDone by mutableStateOf(0)
    var dexTotal by mutableStateOf(0)
    var dexCurrent by mutableStateOf("")
    var dexOk by mutableStateOf(0)
    var dexFail by mutableStateOf(0)
    private var dexJob: Job? = null

    fun dexToggle(pkg: String) { dexSel = if (pkg in dexSel) dexSel - pkg else dexSel + pkg }
    fun dexSelectAll(all: List<String>) { dexSel = all.toSet() }
    fun dexClear() { dexSel = emptySet() }

    fun dexStart() {
        if (dexRunning || dexSel.isEmpty()) return
        val list = dexSel.toList()
        dexJob = viewModelScope.launch {
            dexRunning = true
            dexDone = 0; dexOk = 0; dexFail = 0; dexTotal = list.size
            try {
                for (p in list) {
                    if (!isActive) break
                    dexCurrent = label(p)
                    if (Alpha.dexopt(p, dexMode)) dexOk++ else dexFail++
                    dexDone++
                }
                toast("Dexopt selesai: $dexOk berhasil, $dexFail gagal")
            } catch (e: CancellationException) {
                toast("Dexopt dibatalkan")
                throw e
            } finally {
                dexRunning = false
                dexCurrent = ""
            }
        }
    }

    fun dexCancel() { dexJob?.cancel() }

    // ---------- device / modul ----------
    fun redetect() {
        viewModelScope.launch {
            busy = "Mendeteksi ulang..."
            device = Alpha.device(redetect = true)
            busy = null
            toast("Deteksi ulang selesai")
        }
    }

    fun refreshButton() {
        viewModelScope.launch {
            busy = "Memuat ulang..."
            rootOk = Root.hasRoot()
            if (rootOk) { if (modPath.isEmpty()) modPath = Root.modPath(true); refreshAll() }
            busy = null
            toast("Dimuat ulang")
        }
    }

    fun findModule() {
        viewModelScope.launch {
            busy = "Mencari modul..."
            rootOk = Root.hasRoot()
            modPath = if (rootOk) Root.modPath(true) else ""
            if (modPath.isNotEmpty()) refreshAll()
            busy = null
            toast(if (modPath.isNotEmpty()) "Modul ditemukan" else "Modul tidak ditemukan")
        }
    }

    fun checkHealth() {
        viewModelScope.launch {
            Alpha.health()?.let { health = it }
            toast("Health check diperbarui")
        }
    }

    fun copyLog() {
        val text = logs.takeLast(200).joinToString("\n") { it.raw }
        val cm = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("alpha.log", text))
        toast("Log disalin")
    }

    // ---------- gambar ----------
    fun setBackground(uri: Uri) {
        viewModelScope.launch {
            val ok = withContext(Dispatchers.IO) { Imaging.import(app, uri, Imaging.bgFile(app), 1600) }
            if (ok) { prefs.bgVer = prefs.bgVer + 1; bgVer = prefs.bgVer; toast("Background diganti") } else toast("Gagal membaca gambar")
        }
    }

    fun clearBackground() {
        Imaging.bgFile(app).delete()
        prefs.bgVer = prefs.bgVer + 1; bgVer = prefs.bgVer
        toast("Background dihapus")
    }

    fun setBanner(uri: Uri) {
        viewModelScope.launch {
            val ok = withContext(Dispatchers.IO) { Imaging.import(app, uri, Imaging.bannerFile(app), 1400) }
            if (ok) { prefs.bannerVer = prefs.bannerVer + 1; bannerVer = prefs.bannerVer; toast("Banner diganti") } else toast("Gagal membaca gambar")
        }
    }

    fun resetBanner() {
        Imaging.bannerFile(app).delete()
        prefs.bannerVer = prefs.bannerVer + 1; bannerVer = prefs.bannerVer
        toast("Banner default dipakai")
    }
}
