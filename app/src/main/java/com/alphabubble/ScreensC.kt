package com.alphabubble

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ---------------------------------------------------------------- PERFORMA & FPS (satu tempat)
@Composable
fun PerfScreen(vm: AppViewModel) {
    BackBtn { vm.back() }

    // muat ulang daftar begitu satu rekaman selesai disimpan
    LaunchedEffect(FpsLog.saved) { if (FpsLog.saved > 0) { kotlinx.coroutines.delay(1500); vm.loadFpsFiles() } }

    AlphaCard {
        Label("Rekam data FPS")
        if (FpsLog.on) {
            txt("Merekam... ${FpsLog.rows} baris (1 baris per detik).", 13.sp, Mint)
        } else {
            txt("Buka game, lalu tekan MULAI. Data FPS, GPU, CPU, suhu, profil, dan status Overdrive disimpan ke Download/Alpha_fps_*.csv.", 12.sp, muted())
        }
        Pill(if (FpsLog.on) "STOP & SIMPAN" else "MULAI REKAM FPS", { vm.toggleFpsLog() }, solid = !FpsLog.on)
        txt("Tombol yang sama ada di floating (Rekam FPS). Hasilnya muncul di daftar di bawah.", 11.sp, muted(), modifier = Modifier.padding(top = 8.dp))
    }

    val sel = vm.fpsSel.mapNotNull { n -> vm.fpsFiles.firstOrNull { it.name == n } }
    if (sel.size == 2) {
        val a = sel[0]; val b = sel[1]
        AlphaCard {
            Label("Perbandingan")
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.weight(1.1f)) {}
                Box(Modifier.weight(1f)) { txt("A", 12.sp, muted(), align = TextAlign.End, modifier = Modifier.fillMaxWidth()) }
                Box(Modifier.weight(1f)) { txt("B", 12.sp, muted(), align = TextAlign.End, modifier = Modifier.fillMaxWidth()) }
            }
            fun row(k: String, x: String, y: String, better: Int) {  // better: 1 = A lebih baik, 2 = B, 0 = sama/NA
                cmpRow(k, x, y, better)
            }
            row("Mode", a.mode, b.mode, 0)
            row("Rata-rata FPS", "%.1f".format(a.avg), "%.1f".format(b.avg), if (a.avg > b.avg + 0.05) 1 else if (b.avg > a.avg + 0.05) 2 else 0)
            row("1% terendah", "%.1f".format(a.low1), "%.1f".format(b.low1), if (a.low1 > b.low1 + 0.05) 1 else if (b.low1 > a.low1 + 0.05) 2 else 0)
            row("Mulus (>=27 FPS)", "${a.pctOk}%", "${b.pctOk}%", if (a.pctOk > b.pctOk) 1 else if (b.pctOk > a.pctOk) 2 else 0)
            row("Patah (<15 FPS)", "${a.pctBad}%", "${b.pctBad}%", if (a.pctBad < b.pctBad) 1 else if (b.pctBad < a.pctBad) 2 else 0)
            row("Suhu baterai", "${a.tMin}-${a.tMax}°", "${b.tMin}-${b.tMax}°", 0)
            row("Durasi", dur(a.secs), dur(b.secs), 0)
            val verdict = when {
                a.avg > b.avg + 0.5 -> "A lebih kencang ${"%.1f".format(a.avg - b.avg)} FPS (${a.mode})."
                b.avg > a.avg + 0.5 -> "B lebih kencang ${"%.1f".format(b.avg - a.avg)} FPS (${b.mode})."
                else -> "Rata-rata FPS hampir sama."
            }
            txt(verdict, 12.sp, Mint, modifier = Modifier.padding(top = 8.dp))
            if (a.tMin > 0 && b.tMin > 0 && kotlin.math.abs(a.tMin - b.tMin) >= 4)
                txt("Suhu awal beda jauh (${a.tMin}° vs ${b.tMin}°): perbandingan kurang adil, ulangi dari suhu yang sama.", 11.sp, muted(), modifier = Modifier.padding(top = 6.dp))
        }
    } else {
        AlphaCard {
            Label("Perbandingan")
            txt("Pilih 2 rekaman di bawah (tekan PILIH) untuk membandingkan, mis. Performa vs Overdrive di game yang sama.", 12.sp, muted())
        }
    }

    AlphaCard {
        Label("Rekaman tersimpan")
        if (vm.fpsLoading) txt("Membaca...", 12.sp, muted())
        else if (vm.fpsFiles.isEmpty()) txt("Belum ada rekaman di Download/Alpha_fps_*.csv.", 12.sp, muted())
        vm.fpsFiles.forEach { f ->
            val on = f.name in vm.fpsSel
            val tag = when (vm.fpsSel.indexOf(f.name)) { 0 -> "A"; 1 -> "B"; else -> "" }
            Column(Modifier.fillMaxWidth().padding(top = 10.dp)) {
                txt(f.name.removePrefix("Alpha_fps_").removeSuffix(".csv").replace('_', ' ') + "  ·  " + f.mode, 13.sp, maxLines = 1, weight = FontWeight.Medium)
                txt("rata-rata ${"%.1f".format(f.avg)} · 1% ${"%.1f".format(f.low1)} · mulus ${f.pctOk}% · ${dur(f.secs)}", 11.sp, muted(), maxLines = 1)
                txt("suhu ${f.tMin}-${f.tMax}°" + (if (f.pkg.isNotEmpty()) " · ${vm.label(f.pkg)}" else ""), 11.sp, muted(), maxLines = 1)
                Pill(if (on) "DIPILIH $tag" else "PILIH", { vm.toggleFpsSel(f.name) }, highlight = on)
            }
        }
        Pill("MUAT ULANG", { vm.loadFpsFiles() })
    }

    val ses = vm.prefs.fpsSessions
    if (ses.isNotEmpty()) {
        AlphaCard {
            Label("Riwayat sesi otomatis")
            txt("Dicatat sendiri tiap kali main game (tanpa perlu menekan rekam).", 11.sp, muted())
            ses.take(6).forEach { x ->
                val mode = if (x.ovdPct >= 50) "OVERDRIVE" else profileLabel(x.profile).uppercase()
                Column(Modifier.fillMaxWidth().padding(top = 10.dp)) {
                    txt(vm.label(x.pkg), 13.sp, maxLines = 1)
                    txt("$mode · rata-rata ${x.avg} · 1% terendah ${x.low1} · ${dur(x.secs)}", 12.sp, muted(), maxLines = 1)
                }
            }
        }
    }
}

private fun dur(secs: Int): String = "${secs / 60}m${(secs % 60).toString().padStart(2, '0')}d"

@Composable
private fun cmpRow(k: String, x: String, y: String, better: Int) {
    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.weight(1.1f)) { txt(k, 11.sp, muted()) }
        Box(Modifier.weight(1f)) { txt(x, 12.sp, if (better == 1) Mint else Paper, align = TextAlign.End, modifier = Modifier.fillMaxWidth()) }
        Box(Modifier.weight(1f)) { txt(y, 12.sp, if (better == 2) Mint else Paper, align = TextAlign.End, modifier = Modifier.fillMaxWidth()) }
    }
}
