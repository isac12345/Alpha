package com.alphabubble

import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

fun relTime(ms: Long?): String {
    if (ms == null) return "—"
    val d = (System.currentTimeMillis() - ms) / 60000
    return when {
        d < 1 -> "now"
        d < 60 -> "${d}m"
        d < 1440 -> "${d / 60}j"
        else -> "${d / 1440}h"
    }
}

// ---------------------------------------------------------------- CUSTOM
@Composable
fun CustomScreen(vm: AppViewModel) {
    AlphaCard {
        Pill("BACKGROUND & BANNER  ›", { vm.go("bgbanner") }, modifier = Modifier.padding(top = 0.dp))
        Pill("FLOATING BUBBLE  ›", { vm.go("bubble") })
        Pill("TEMA WARNA  ›", { vm.go("theme") })
    }
    txt("Ikon aplikasi kustom menyusul di update berikutnya.", 11.sp, muted())
}

@Composable
fun BgBannerScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val pickBg = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> if (uri != null) vm.setBackground(uri) }
    val pickBanner = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> if (uri != null) vm.setBanner(uri) }
    AlphaCard {
        Label("Background")
        Pill("PILIH GAMBAR BACKGROUND", { pickBg.launch("image/*") }, modifier = Modifier.padding(top = 0.dp))
        Pill("HAPUS BACKGROUND", { vm.clearBackground() })
        Label("Banner", Modifier.padding(top = 16.dp))
        Pill("PILIH GAMBAR BANNER", { pickBanner.launch("image/*") }, modifier = Modifier.padding(top = 0.dp))
        Pill("BANNER DEFAULT", { vm.resetBanner() })
    }
    AlphaCard {
        val t = 1f - vm.cardAlpha
        SliderRow("Transparansi kartu", t, 0f..0.9f, "${(t * 100).toInt()}%", { vm.setCardAlpha(1f - it) })
        Label("Penyesuaian gambar", Modifier.padding(top = 10.dp))
        Seg(listOf("CROP", "FIT", "FILL"), vm.fit, { vm.setFit(it) })
        txt("CROP memenuhi layar dengan memotong tepi, FIT menampilkan utuh, FILL meregangkan.", 11.sp, muted())
    }
}

@Composable
fun BubbleScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    AlphaCard {
        Label("Floating bubble")
        SliderRow("Ukuran", vm.bubbleSize.toFloat(), 36f..80f, "${vm.bubbleSize} dp", { vm.setBubbleSize(it.toInt()) })
        SliderRow("Opacity", vm.bubbleOpacity.toFloat(), 30f..100f, "${vm.bubbleOpacity}%", { vm.setBubbleOpacity(it.toInt()) })
        Label("Bentuk", Modifier.padding(top = 10.dp))
        Seg(listOf("BULAT", "KOTAK", "PIL"), vm.bubbleShape, { vm.setBubbleShape(it) })
        txt(
            "Tap bubble: pilih profil. Tahan: sembunyikan. Munculkan lagi lewat notifikasi. Lepas bubble dekat tepi layar, ia menempel otomatis. Perubahan langsung berlaku.",
            11.sp, muted(), modifier = Modifier.padding(top = 8.dp),
        )
    }
}

@Composable
fun ThemeScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val swatches = listOf(0xFFE8E6E1.toInt(), 0xFF5DCAA5.toInt(), 0xFFAFA9EC.toInt(), 0xFFF0997B.toInt(), 0xFF85B7EB.toInt(), 0xFFEF9F27.toInt())
    AlphaCard {
        Label("Warna aksen")
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            swatches.forEach { c ->
                val on = vm.accent == c
                Box(
                    Modifier.size(36.dp).clip(CircleShape).background(Color(c))
                        .border(BorderStroke(2.dp, if (on) Color.White else Color.Transparent), CircleShape)
                        .clickable { vm.setAccent(c) },
                )
            }
        }
        Box(
            Modifier.padding(top = 12.dp).clip(CircleShape).background(LocalUi.current.accent).padding(horizontal = 18.dp, vertical = 8.dp),
        ) { txt("PRATINJAU AKSEN", 11.sp, Ink, spacing = 1.2.sp) }
        SliderRow("Blur background", vm.blur.toFloat(), 0f..100f, "${vm.blur}%", { vm.setBlur(it.toInt()) })
        if (Build.VERSION.SDK_INT < 31) txt("Blur butuh Android 12 ke atas.", 11.sp, Amber)
        SliderRow("Kontras teks", vm.contrast.toFloat(), 30f..100f, "${vm.contrast}%", { vm.setContrast(it.toInt()) })
        ToggleRow("Mode hemat", "matikan animasi dan wallpaper berat", vm.saver) { vm.setSaver(it) }
    }
}

// ---------------------------------------------------------------- TOOLS
@Composable
fun ToolsScreen(vm: AppViewModel) {
    val ri = vm.resInfo
    AlphaCard {
        Label("Peralatan")
        if (ri != null) {
            KV("Native", "${ri.nat.w}×${ri.nat.h} · ${ri.nat.d}")
            Divider()
            val pct = Math.round(ri.act.w * 100f / ri.nat.w)
            KV("Aktif", "${ri.act.w}×${ri.act.h} · $pct%")
        } else KV("Layar", "membaca...")
        val opts = listOf(60, 70, 80, 90, 100)
        Seg(opts.map { it.toString() }, opts.indexOf(vm.resPct).coerceAtLeast(0), { vm.resPct = opts[it] })
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f)) { Pill("APPLY RES", { vm.applyRes() }, enabled = vm.resCountdown == 0) }
            Box(Modifier.weight(1f)) { Pill("RESET", { vm.resetRes() }, enabled = vm.resCountdown == 0) }
        }
        if (vm.resCountdown > 0) {
            Column(
                Modifier.fillMaxWidth().padding(top = 10.dp).clip(RoundedCornerShape(14.dp))
                    .border(BorderStroke(0.6.dp, Mint), RoundedCornerShape(14.dp)).padding(12.dp),
            ) {
                txt("Layar oke? Balik otomatis dalam ${vm.resCountdown} detik.", 12.sp)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.weight(1f)) { Pill("PERTAHANKAN", { vm.keepRes() }, solid = true) }
                    Box(Modifier.weight(1f)) { Pill("KEMBALIKAN", { vm.revertRes() }) }
                }
            }
        }
        Pill("DEXOPT APP", { vm.go("dexopt") })
        Pill("TUTUP SEMUA APP", { vm.askCloseApps() })
    }

    AlphaCard {
        Label("Tuning log")
        val filters = listOf("ALL" to "SEMUA", "ERROR" to "ERROR", "CPU" to "CPU", "GAME" to "GAME", "INPUT" to "INPUT")
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            filters.forEach { (k, t) -> Chip(t, vm.logFilter == k) { vm.logFilter = k } }
        }
        val shown = vm.logs.filter { Alpha.logMatches(it, vm.logFilter) }.takeLast(6).reversed()
        if (shown.isEmpty()) txt("Belum ada log.", 12.sp, muted())
        shown.forEach { LogRow(it) }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f)) { Pill("SEMUA LOG", { vm.go("fulllog") }) }
            Box(Modifier.weight(1f)) { Pill("SALIN", { vm.copyLog() }) }
        }
    }

    AlphaCard {
        Label("Mesin")
        ToggleRow("fas-rs pegang CPU", null, !vm.flag("GB_FASRS_FORCE_ALPHA")) { vm.setFlag("GB_FASRS_FORCE_ALPHA", !it) }
        Divider()
        ToggleRow("Boost penuh setelah dingin", null, vm.flag("GB_COOLDOWN_EXTREME")) { vm.setFlag("GB_COOLDOWN_EXTREME", it) }
        Divider()
        ToggleRow("Cpuset game dipersempit", null, !vm.flag("NO_CPUSET")) { vm.setFlag("NO_CPUSET", !it) }
    }

    AlphaCard(isNew = true) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { Label("Health check modul") }
            NewTag()
        }
        val h = vm.health
        StatusRow("Uperf", h.uperf)
        StatusRow("fas-rs", h.fasrs)
        StatusRow("Monitor", h.monitor)
        StatusRow("Watchdog", h.watchdog)
        StatusRow("Auto-profile", h.auto)
        Divider()
        ToggleRow("Boot guard", "boot gagal 2x berturut-turut, tuning dilewati otomatis" + if (h.bootFail > 0) " (gagal: ${h.bootFail}x)" else "", h.bootGuard) { vm.setBootGuard(it) }
        Pill("CEK ULANG", { vm.checkHealth() })
    }

    AlphaCard {
        Label("Device")
        val d = vm.device
        KV("SoC", d["SOC_VENDOR"].orEmpty().ifEmpty { "—" })
        Divider()
        KV("GPU", d["GPU_VENDOR"].orEmpty().ifEmpty { "—" })
        Divider()
        KV("CPU", d["CPU_POLICIES"].orEmpty().ifEmpty { "—" })
        Divider()
        KV("Storage", d["STORAGE_DEVICES"].orEmpty().ifEmpty { "—" })
        Pill("DETEKSI ULANG", { vm.redetect() })
    }

    AlphaCard {
        ToggleRow("Auto-start saat boot", null, vm.autostart) { vm.setAutostart(it) }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f)) { Pill("REFRESH", { vm.refreshButton() }) }
            Box(Modifier.weight(1f)) { Pill("CARI MODULE", { vm.findModule() }) }
        }
        val line = when {
            !vm.rootOk -> "Root belum diberikan"
            vm.modPath.isEmpty() -> "Root OK · modul tidak ditemukan"
            else -> "Root OK · ${vm.modPath}"
        }
        txt(line, 11.sp, muted(), modifier = Modifier.padding(top = 10.dp))
    }

    AlphaCard {
        Label("About")
        txt("Alpha Control by somwan", 15.sp, weight = FontWeight.Medium)
        txt("Alpha · Uperf · fas-rs" + if (vm.status.ver > 0) " · modul ${vm.status.ver}" else "", 12.sp, muted(), modifier = Modifier.padding(top = 4.dp))
        txt("Credit: Matt Yang & yinwanxi (Uperf), shadow3 & shadow3aaa (fas-rs)", 12.sp, muted(), modifier = Modifier.padding(top = 2.dp))
        Pill("BUKA BATTERY LAB", { vm.go("batlab") })
    }
}

@Composable
fun LogRow(l: LogLine) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        txt(relTime(l.timeMs), 11.sp, muted(), modifier = Modifier.width(34.dp), maxLines = 1)
        txt(l.cat, 11.sp, weight = FontWeight.Medium, modifier = Modifier.width(86.dp), maxLines = 1)
        txt((l.status + " " + l.msg).trim(), 11.sp, muted(), modifier = Modifier.weight(1f), maxLines = 1)
    }
}

@Composable
fun FullLogScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    AlphaCard {
        val filters = listOf("ALL" to "SEMUA", "ERROR" to "ERROR", "CPU" to "CPU", "GAME" to "GAME", "INPUT" to "INPUT")
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            filters.forEach { (k, t) -> Chip(t, vm.logFilter == k) { vm.logFilter = k } }
        }
        val shown = vm.logs.filter { Alpha.logMatches(it, vm.logFilter) }.takeLast(300).reversed()
        if (shown.isEmpty()) txt("Tidak ada baris yang cocok.", 12.sp, muted())
        shown.forEach { l ->
            txt(l.raw, 10.sp, muted(), modifier = Modifier.padding(vertical = 2.dp))
        }
        Pill("SALIN", { vm.copyLog() })
    }
}

// ---------------------------------------------------------------- DEXOPT
@Composable
fun DexoptScreen(vm: AppViewModel) {
    BackBtn { if (!vm.dexRunning) vm.back() }
    val modes = listOf(
        Triple("speed-profile", "SEIMBANG", "pakai profil pemakaian · disarankan"),
        Triple("speed", "CEPAT", "compile penuh · storage lebih besar"),
        Triple("everything", "MAKSIMAL", "semua method · paling besar dan lama"),
        Triple("verify", "RINGAN", "verifikasi saja · hemat storage"),
        Triple("reset", "RESET", "kembalikan ke compile bawaan sistem"),
    )
    AlphaCard {
        Label("Mode dexopt")
        modes.forEach { (k, t, d) ->
            val on = vm.dexMode == k
            Row(
                Modifier.fillMaxWidth().clickable(enabled = !vm.dexRunning) { vm.dexMode = k }.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(18.dp).clip(CircleShape).border(BorderStroke(1.2.dp, if (on) LocalUi.current.accent else muted()), CircleShape).padding(4.dp),
                ) { if (on) Box(Modifier.fillMaxWidth().height(10.dp).clip(CircleShape).background(LocalUi.current.accent)) }
                Column(Modifier.padding(start = 12.dp)) {
                    txt(t, 13.sp, weight = FontWeight.Medium, spacing = 1.sp)
                    txt(d, 11.sp, muted())
                }
            }
        }
    }

    AlphaCard {
        Label("Jalankan")
        txt("${vm.dexSel.size} app dipilih · mode ${vm.dexMode}", 12.sp, muted())
        if (vm.dexRunning) {
            Box(Modifier.fillMaxWidth().padding(top = 10.dp).height(6.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.15f))) {
                val f = if (vm.dexTotal == 0) 0f else vm.dexDone.toFloat() / vm.dexTotal
                Box(Modifier.fillMaxWidth(f.coerceIn(0.02f, 1f)).height(6.dp).clip(CircleShape).background(LocalUi.current.accent))
            }
            txt("${vm.dexDone}/${vm.dexTotal} · ${vm.dexCurrent}", 12.sp, modifier = Modifier.padding(top = 8.dp), maxLines = 1)
            txt("Berhasil ${vm.dexOk} · gagal ${vm.dexFail}", 11.sp, muted())
            Pill("BATALKAN", { vm.dexCancel() })
        } else {
            Pill("MULAI DEXOPT", { vm.dexStart() }, solid = true, enabled = vm.dexSel.isNotEmpty())
        }
    }

    AlphaCard {
        val list = vm.thirdParty
        Label("App pihak ketiga · ${list.size}")
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip("PILIH SEMUA", false) { if (!vm.dexRunning) vm.dexSelectAll(list.map { it.pkg }) }
            Chip("KOSONGKAN", false) { if (!vm.dexRunning) vm.dexClear() }
        }
        if (list.isEmpty()) txt("Membaca daftar app...", 12.sp, muted(), modifier = Modifier.padding(top = 10.dp))
        list.forEach { a ->
            val on = a.pkg in vm.dexSel
            Row(
                Modifier.fillMaxWidth().clickable(enabled = !vm.dexRunning) { vm.dexToggle(a.pkg) }.padding(top = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).background(if (on) Mint else Color.White.copy(alpha = 0.12f)),
                    contentAlignment = Alignment.Center,
                ) { if (on) txt("✓", 14.sp, Color(0xFF04342C)) }
                Box(Modifier.width(10.dp))
                AppIcon(a.pkg, 36.dp)
                Column(Modifier.weight(1f).padding(start = 10.dp)) {
                    txt(a.label, 13.sp, maxLines = 1)
                    txt(a.pkg, 10.sp, muted(), maxLines = 1)
                }
            }
        }
    }
}

// ---------------------------------------------------------------- BATTERY LAB
@Composable
fun BatLabScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val b = vm.battery
    AlphaCard {
        Label("Battery Lab")
        txt(if (b.level >= 0) "${b.level}%" else "—", 28.sp, weight = FontWeight.Medium, modifier = Modifier.padding(bottom = 6.dp))
        KV("Status", b.status.ifEmpty { "—" })
        Divider()
        KV("Kondisi", b.health.ifEmpty { "—" })
        Divider()
        KV("Suhu baterai", "%.1f°C".format(b.tempC))
        Divider()
        KV("Tegangan", if (b.voltageMv > 0) "${b.voltageMv} mV" else "—")
        Divider()
        KV("Arus", if (b.currentMa != 0) "${kotlin.math.abs(b.currentMa)} mA" else "—")
        Divider()
        val w = kotlin.math.abs(b.voltageMv.toLong() * b.currentMa.toLong()) / 1_000_000f
        KV("Daya", if (b.currentMa != 0) "%.2f W".format(w) else "—")
        Divider()
        KV("Siklus", if (b.cycles >= 0) b.cycles.toString() else "—")
        Divider()
        KV("Kapasitas vs desain", if (b.healthPct >= 0) "${b.healthPct}%" else "—")
        Divider()
        KV("Teknologi", b.tech.ifEmpty { "—" })
    }
    txt("Dibaca dari sysfs baterai tiap 3 detik selama layar ini terbuka. Satuan dan tanda arus berbeda antar perangkat; nilai yang tidak disediakan kernel ditampilkan —.", 11.sp, muted())
}
