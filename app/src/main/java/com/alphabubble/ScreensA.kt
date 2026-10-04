package com.alphabubble

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

fun fmtDur(s: Long): String {
    val h = s / 3600
    val m = (s % 3600) / 60
    val sec = s % 60
    return if (h > 0) "${h}j ${m}m" else if (m > 0) "${m}m ${sec}d" else "${sec}d"
}

fun fmtClock(s: Long): String = "%02d:%02d".format(s / 60, s % 60)

fun renderName(k: String): String = when (k) {
    "default" -> "Default"
    "skiagl" -> "OpenGL (Skia)"
    "skiavk" -> "Vulkan (Skia)"
    else -> k
}

// ---------------------------------------------------------------- DASH
@Composable
fun DashScreen(vm: AppViewModel) {
    val st = vm.status
    if (vm.loaded && (!vm.rootOk || vm.modPath.isEmpty())) {
        AlphaCard {
            Label("Perlu perhatian")
            txt(
                if (!vm.rootOk) "Akses root belum diberikan. Buka manager root (KernelSU/Magisk) dan izinkan Alpha Control."
                else "Modul Alpha Fusion tidak ditemukan. Flash modulnya dulu, lalu cari ulang.",
                12.sp, Amber,
            )
            Pill("CARI ULANG", { vm.findModule() })
        }
    }
    if (vm.loaded && vm.rootOk && vm.modPath.isNotEmpty()) {
        val modVer = st.ver
        if (!vm.statusOk) {
            AlphaCard {
                Label("Versi")
                txt("Modul belum kompatibel dengan app ini (alphactl tidak ada). Flash Alpha Fusion v${vm.appVer}.", 12.sp, Amber)
            }
        } else if (modVer > 0 && modVer != vm.appVer) {
            AlphaCard {
                Label("Versi")
                txt("Modul v$modVer, app v${vm.appVer}. Pasang keduanya dari build yang sama.", 12.sp, Amber)
            }
        }
    }
    AlphaCard { ToggleRow("Tampilkan bubble", null, vm.bubbleOn) { vm.updateBubbleOn(it) } }

    AlphaCard {
        Label("Current profile")
        txt(profileLabel(st.profile), 28.sp, weight = FontWeight.Medium, modifier = Modifier.padding(bottom = 8.dp))
        Seg(PROFILE_LABELS, PROFILE_KEYS.indexOf(st.profile), { vm.setProfile(PROFILE_KEYS[it]) })
        if (st.gamePkg.isNotEmpty()) {
            txt("Dikunci game: ${vm.label(st.gamePkg)}", 12.sp, Amber, modifier = Modifier.padding(top = 6.dp))
        }
    }

    val nRules = (if (vm.confStr("AUTO_BATT_ON", "0") == "1") 1 else 0) + (if (vm.confStr("AUTO_CHG_ON", "0") == "1") 1 else 0)
    AlphaCard(onClick = { vm.go("auto") }) {
        Label("Auto-profile")
        KV(if (nRules == 0) "Belum ada aturan aktif" else "$nRules aturan aktif", "›")
    }
    AlphaCard(onClick = { vm.go("therm") }) {
        Label("Proteksi thermal")
        KV("Batas ${st.thermalWarmC}°C · " + if (vm.flag("THERMAL_GUARD_OFF")) "mati" else "aktif", "›")
    }

    AlphaCard {
        Label("Status game")
        KV("Suhu", "%.1f°C".format(st.tempC))
        Divider()
        KV("Mode fas-rs", st.fasrsMode.ifEmpty { "—" })
        Divider()
        KV("Sesi", if (st.gamePkg.isEmpty()) "—" else "${vm.label(st.gamePkg)} · ${fmtClock(st.gameSecs)}")
    }

    AlphaCard {
        Label("Render")
        var open by remember { mutableStateOf(false) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                Box(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Color.Black.copy(alpha = 0.6f))
                        .clickable { open = true }.padding(horizontal = 14.dp, vertical = 14.dp),
                ) { txt(renderName(vm.renderChoice) + "  ▾", 13.sp) }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    vm.render.available.forEach { k ->
                        DropdownMenuItem(text = { Text(renderName(k), fontFamily = Mono) }, onClick = { vm.renderChoice = k; open = false })
                    }
                }
            }
            Box(Modifier.width(10.dp))
            Box(Modifier.width(120.dp)) { Pill("APPLY", { vm.applyRender() }, solid = true, modifier = Modifier.padding(top = 0.dp)) }
        }
    }
}

// ---------------------------------------------------------------- AUTO-PROFILE
@Composable
fun AutoScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    var battOn by remember(vm.conf) { mutableStateOf(vm.confStr("AUTO_BATT_ON", "0") == "1") }
    var pct by remember(vm.conf) { mutableStateOf((vm.confStr("AUTO_BATT_PCT", "20").toIntOrNull() ?: 20).toFloat()) }
    var battProf by remember(vm.conf) { mutableStateOf(vm.confStr("AUTO_BATT_PROFILE", "battery")) }
    var chgOn by remember(vm.conf) { mutableStateOf(vm.confStr("AUTO_CHG_ON", "0") == "1") }
    var chgProf by remember(vm.conf) { mutableStateOf(vm.confStr("AUTO_CHG_PROFILE", "balanced")) }

    AlphaCard {
        Label("Baterai rendah")
        ToggleRow("Aktif", null, battOn) { battOn = it }
        SliderRow("Batas baterai", pct, 5f..50f, "${pct.toInt()}%", { pct = it })
        Seg(PROFILE_LABELS, PROFILE_KEYS.indexOf(battProf), { battProf = PROFILE_KEYS[it] })
    }
    AlphaCard {
        Label("Lagi charging")
        ToggleRow("Aktif", null, chgOn) { chgOn = it }
        Seg(PROFILE_LABELS, PROFILE_KEYS.indexOf(chgProf), { chgProf = PROFILE_KEYS[it] })
    }
    AlphaCard(onClick = { vm.go("games") }) {
        Label("Game dibuka")
        KV("Otomatis lewat profil per game", "›")
    }
    Pill("SIMPAN", { vm.saveAuto(battOn, pct.toInt(), battProf, chgOn, chgProf) }, solid = true)
}

// ---------------------------------------------------------------- THERMAL
@Composable
fun ThermScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val st = vm.status
    var warm by remember(st.thermalWarmC) { mutableStateOf(st.thermalWarmC.toFloat()) }
    val w = warm.toInt()
    val perf = st.active == "performance"
    val warmEff = if (perf) w + 10 else w
    val highEff = if (perf) w + 15 else w + 10
    val state = when {
        st.tempC >= 95 -> "KRITIS"
        st.tempC >= highEff -> "PANAS"
        st.tempC >= warmEff -> "HANGAT"
        else -> "AMAN"
    }
    val stateColor = when (state) { "AMAN" -> Mint; "HANGAT" -> Amber; else -> Coral }
    AlphaCard {
        Label("Suhu sekarang")
        Row(verticalAlignment = Alignment.Bottom) {
            txt("%.1f°C".format(st.tempC), 28.sp, weight = FontWeight.Medium)
            Box(Modifier.width(12.dp))
            txt(state, 12.sp, stateColor, spacing = 1.sp, modifier = Modifier.padding(bottom = 4.dp))
        }
        ToggleRow(
            "Turun profil otomatis", null,
            !vm.flag("THERMAL_GUARD_OFF"),
        ) { vm.setFlag("THERMAL_GUARD_OFF", !it) }
        if (vm.flag("THERMAL_GUARD_OFF")) txt("Proteksi mati. Batas kritis 95°C tetap jalan.", 12.sp, Amber)
    }
    AlphaCard {
        Label("Batas suhu")
        SliderRow("Hangat mulai dari", warm, 60f..90f, "$w°C", { warm = it }, { vm.setThermalWarm(warm.toInt()) })
        Divider()
        KV("Hangat", "$warmEff°C")
        Divider()
        KV("Panas", "$highEff°C")
        Divider()
        KV("Kritis", "95°C")
        Divider()
        KV("Boost balik", "< ${w - 5}°C")
    }
}

// ---------------------------------------------------------------- GAMES
@Composable
fun GamesScreen(vm: AppViewModel) {
    val last = vm.sessions.firstOrNull()
    AlphaCard(onClick = { vm.go("stats") }) {
        Label("Statistik sesi terakhir")
        if (last == null) KV("Belum ada sesi (min. 1 menit)", "›")
        else KV("${vm.label(last.pkg)} · ${fmtDur(last.durSecs)}", "%.1f°C ›".format(last.peakC))
    }

    AlphaCard {
        var q by remember { mutableStateOf("") }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { Label("Game · ${vm.games.size}") }
            Box(
                Modifier.size(44.dp).clip(CircleShape).background(LocalUi.current.accent).clickable { vm.go("addgame") },
                contentAlignment = Alignment.Center,
            ) { txt("+", 22.sp, Ink, FontWeight.Medium) }
        }
        Pill("AUTO-DETECT GAME", { vm.go("detect") }, highlight = true)
        Field(q, { q = it }, "Cari game...")
        val list = vm.games.filter { q.isBlank() || vm.label(it.pkg).contains(q, true) || it.pkg.contains(q, true) }
        if (list.isEmpty()) {
            txt(if (vm.games.isEmpty()) "Belum ada game. Tekan + atau Auto-detect." else "Tidak ada yang cocok.", 12.sp, muted(), modifier = Modifier.padding(top = 10.dp))
        }
        list.forEach { g ->
            Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                AppIcon(g.pkg)
                Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                    txt(vm.label(g.pkg), 14.sp, weight = FontWeight.Medium, maxLines = 1)
                    Box(Modifier.padding(top = 4.dp)) {
                        SmallPill(profileLabel(g.profile) + " · FAS-RS" + if (g.fps.isNotEmpty()) " · ${g.fps} FPS" else "")
                    }
                }
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    SmallPill("EDIT", { vm.editPkg = g.pkg; vm.go("edit") }, highlight = true)
                    SmallPill("HAPUS", {
                        vm.dialog = Dlg.Confirm("Hapus game", "Hapus ${vm.label(g.pkg)} dari daftar? Game kembali ditangani seperti app biasa.", "HAPUS") { vm.removeGame(g.pkg) }
                    })
                }
            }
        }
    }
}

// ---------------------------------------------------------------- STATISTIK
@Composable
fun StatsScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val fmt = SimpleDateFormat("dd MMM HH:mm", Locale.getDefault())
    val last = vm.sessions.firstOrNull()
    if (last == null) {
        AlphaCard { txt("Belum ada sesi game tercatat. Sesi dicatat setelah game dimainkan minimal 1 menit.", 12.sp, muted()) }
        return
    }
    AlphaCard {
        Label("Sesi terakhir · ${vm.label(last.pkg)}")
        KV("Durasi main", fmtDur(last.durSecs))
        Divider()
        KV("Suhu puncak", "%.1f°C".format(last.peakC))
        Divider()
        KV("Baterai", "${last.battStart}% → ${last.battEnd}%")
        Divider()
        val drain = if (last.durSecs >= 300) "%.1f%%/jam".format((last.battStart - last.battEnd) * 3600f / last.durSecs) else "—"
        KV("Drain baterai", drain)
        Divider()
        KV("Profil", profileLabel(last.profile))
    }
    val recent = vm.sessions.take(7).reversed()
    AlphaCard {
        Label("Suhu puncak ${recent.size} sesi")
        Row(Modifier.fillMaxWidth().height(90.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
            recent.forEachIndexed { i, s ->
                val frac = ((s.peakC - 30f) / 50f).coerceIn(0.06f, 1f)
                Box(
                    Modifier.weight(1f).height((84f * frac).dp).clip(RoundedCornerShape(4.dp))
                        .background(if (i == recent.size - 1) Mint else Color(0xFF3A3D44)),
                )
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            txt("lama", 12.sp, muted()); txt("baru", 12.sp, muted())
        }
    }
    AlphaCard {
        Label("Riwayat")
        vm.sessions.take(15).forEach { s ->
            KV("${vm.label(s.pkg)} · ${fmt.format(Date(s.epoch * 1000))}", fmtDur(s.durSecs))
        }
    }
}

// ---------------------------------------------------------------- AUTO-DETECT
@Composable
fun DetectScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val reg = vm.games.map { it.pkg }.toSet()
    val found = vm.apps.filter { it.isGame && it.pkg !in reg }
    var sel by remember { mutableStateOf<Set<String>?>(null) }
    var prof by remember { mutableStateOf(2) }
    val chosen = (sel ?: found.map { it.pkg }.toSet()).filter { p -> found.any { it.pkg == p } }
    AlphaCard {
        Label("Game ditemukan · ${found.size}")
        if (vm.apps.isEmpty()) txt("Membaca daftar app...", 12.sp, muted())
        else if (found.isEmpty()) txt("Tidak ada game baru. Tambah manual lewat tombol + di tab Games.", 12.sp, muted())
        found.forEach { a ->
            val on = a.pkg in chosen
            Row(
                Modifier.fillMaxWidth().clickable { sel = if (on) chosen.toSet() - a.pkg else chosen.toSet() + a.pkg }.padding(top = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).background(if (on) Mint else Color.Transparent),
                    contentAlignment = Alignment.Center,
                ) { if (on) txt("✓", 14.sp, Color(0xFF04342C)) else Box(Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.12f))) }
                Box(Modifier.width(10.dp))
                AppIcon(a.pkg, 36.dp)
                Column(Modifier.weight(1f).padding(start = 10.dp)) {
                    txt(a.label, 13.sp, maxLines = 1)
                    txt(a.pkg, 11.sp, muted(), maxLines = 1)
                }
            }
        }
    }
    if (found.isNotEmpty()) {
        AlphaCard {
            Label("Profil awal")
            Seg(PROFILE_LABELS, prof, { prof = it })
            Pill("TAMBAH ${chosen.size} GAME", {
                if (chosen.isNotEmpty()) vm.addGames(chosen.toList(), PROFILE_KEYS[prof]) { vm.back() }
            }, solid = true, enabled = chosen.isNotEmpty())
        }
    }
}

// ---------------------------------------------------------------- EDIT GAME
@Composable
fun EditScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val pkg = vm.editPkg
    val g = vm.games.firstOrNull { it.pkg == pkg }
    var prof by remember(pkg) { mutableStateOf(PROFILE_KEYS.indexOf(g?.profile ?: "balanced").coerceAtLeast(0)) }
    var fps by remember(pkg) { mutableStateOf(g?.fps ?: "") }
    AlphaCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AppIcon(pkg)
            Column(Modifier.padding(start = 10.dp)) {
                txt(vm.label(pkg), 14.sp, weight = FontWeight.Medium, maxLines = 1)
                txt(pkg, 11.sp, muted(), maxLines = 1)
            }
        }
        Spacer(Modifier.height(8.dp))
        Label("Profil")
        Seg(PROFILE_LABELS, prof, { prof = it })
        Label("FPS target (opsional, mis. 30,60,90)")
        Field(fps, { fps = it.filter { c -> c.isDigit() || c == ',' } }, "30,60", numeric = false)
        Pill("SIMPAN", { vm.addGame(pkg, fps, PROFILE_KEYS[prof]) { vm.back() } }, solid = true)
    }
}

// ---------------------------------------------------------------- TAMBAH GAME
@Composable
fun AddGameScreen(vm: AppViewModel) {
    var q by remember { mutableStateOf("") }
    var pick by remember { mutableStateOf("") }
    var prof by remember { mutableStateOf(2) }
    var fps by remember { mutableStateOf("") }
    val reg = vm.games.map { it.pkg }.toSet()
    val list = vm.apps.filter { it.pkg !in reg && (q.isBlank() || it.label.contains(q, true) || it.pkg.contains(q, true)) }
    AlphaCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { txt("GAMES", 16.sp, weight = FontWeight.Medium, spacing = 3.sp) }
            SmallPill("CLOSE", { vm.back() })
        }
        Field(q, { q = it }, "Cari aplikasi...")
        Box(Modifier.fillMaxWidth().height(300.dp)) {
            if (vm.apps.isEmpty()) txt("Membaca daftar app...", 12.sp, muted(), modifier = Modifier.padding(top = 12.dp))
            LazyColumn(Modifier.fillMaxWidth()) {
                items(list, key = { it.pkg }) { a ->
                    val on = a.pkg == pick
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                            .background(if (on) Color.White.copy(alpha = 0.1f) else Color.Transparent)
                            .clickable { pick = a.pkg }.padding(vertical = 8.dp, horizontal = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        AppIcon(a.pkg, 40.dp)
                        Column(Modifier.weight(1f).padding(start = 12.dp)) {
                            txt(a.label, 14.sp, weight = FontWeight.Medium, maxLines = 1)
                            txt(a.pkg, 12.sp, muted(), maxLines = 1)
                        }
                        if (a.isGame) SmallPill("GAME")
                    }
                }
            }
        }
        txt(if (pick.isEmpty()) "Pilih aplikasi di atas" else "Dipilih: ${vm.label(pick)}", 12.sp, muted(), modifier = Modifier.padding(top = 8.dp))
        Seg(PROFILE_LABELS, prof, { prof = it })
        Field(fps, { fps = it.filter { c -> c.isDigit() || c == ',' } }, "FPS target (opsional, mis. 30,60,90)")
        Pill("ADD", { if (pick.isNotEmpty()) vm.addGame(pick, fps, PROFILE_KEYS[prof]) { vm.back() } }, solid = true, enabled = pick.isNotEmpty())
    }
}
