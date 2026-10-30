package com.alphabubble

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
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

    vm.fpsFiles.firstOrNull { it.name == vm.fpsView }?.let { FpsDetail(vm, it) }

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
            @Composable fun row(k: String, x: String, y: String, better: Int) {  // better: 1 = A lebih baik, 2 = B, 0 = sama/NA
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
            txt("Pilih 2 rekaman di bawah (tekan BANDINGKAN) untuk membandingkan, mis. Performa vs Overdrive di game yang sama.", 12.sp, muted())
        }
    }

    AlphaCard {
        Label("Rekaman tersimpan")
        if (vm.fpsLoading) txt("Membaca...", 12.sp, muted())
        else if (vm.fpsFiles.isEmpty()) txt("Belum ada rekaman di Download/Alpha_fps_*.csv.", 12.sp, muted())
        if (vm.fpsSkipped > 0) txt("${vm.fpsSkipped} rekaman tidak punya data FPS: ROM ini tidak menyediakan sumber FPS untuk game tersebut (GPU/CPU/suhu tetap terekam).", 11.sp, Coral, modifier = Modifier.padding(top = 6.dp))
        vm.fpsFiles.forEach { f ->
            val on = f.name in vm.fpsSel
            val tag = when (vm.fpsSel.indexOf(f.name)) { 0 -> "A"; 1 -> "B"; else -> "" }
            Column(Modifier.fillMaxWidth().padding(top = 10.dp)) {
                txt(f.name.removePrefix("Alpha_fps_").removeSuffix(".csv").replace('_', ' ') + "  ·  " + f.mode, 13.sp, maxLines = 1, weight = FontWeight.Medium)
                txt("rata-rata ${"%.1f".format(f.avg)} · 1% ${"%.1f".format(f.low1)} · mulus ${f.pctOk}% · ${dur(f.secs)}", 11.sp, muted(), maxLines = 1)
                txt("suhu ${f.tMin}-${f.tMax}°" + (if (f.pkg.isNotEmpty()) " · ${vm.label(f.pkg)}" else ""), 11.sp, muted(), maxLines = 1)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.weight(1f)) { Pill("LIHAT", { vm.fpsView = f.name }, highlight = f.name == vm.fpsView) }
                    Box(Modifier.weight(1f)) { Pill(if (on) "DIPILIH $tag" else "BANDINGKAN", { vm.toggleFpsSel(f.name) }, highlight = on) }
                }
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

private fun fileDate(name: String): String {
    val m = Regex("(\\d{4})(\\d{2})(\\d{2})_(\\d{2})(\\d{2})").find(name) ?: return name
    val (y, mo, d, h, mi) = m.destructured
    val bln = listOf("Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des")
    return "$d ${bln.getOrElse(mo.toInt() - 1) { mo }} $y, $h:$mi"
}

/** Tampilan detail satu rekaman: cincin rata-rata, grafik bertab, strip momen lambat, kotak statistik. */
@Composable
private fun FpsDetail(vm: AppViewModel, f: FpsFile) {
    val ui = LocalUi.current
    val acc = ui.accent
    var tab by remember(f.name) { mutableStateOf(0) }
    var touch by remember(f.name) { mutableStateOf(-1) }
    val smooth = f.smoothPct
    val verdict = when { smooth >= 95 -> "Mulus"; smooth >= 80 -> "Agak patah"; else -> "Patah-patah" }

    AlphaCard {
        txt(if (f.pkg.isNotEmpty()) vm.label(f.pkg) else "Rekaman FPS", 18.sp, weight = FontWeight.Medium, maxLines = 1)
        txt(fileDate(f.name) + "  \u00B7  " + f.mode, 12.sp, muted(), maxLines = 1)
        Row(Modifier.fillMaxWidth().padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            Box(Modifier.size(108.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    val sw = 9.dp.toPx()
                    val inset = sw / 2
                    drawArc(Color.White.copy(alpha = 0.12f), 0f, 360f, false, Offset(inset, inset), Size(size.width - sw, size.height - sw), style = Stroke(sw))
                    val frac = (f.avg / 60.0).coerceIn(0.0, 1.0).toFloat()
                    drawArc(acc, -90f, 360f * frac, false, Offset(inset, inset), Size(size.width - sw, size.height - sw), style = Stroke(sw, cap = StrokeCap.Round))
                }
                txt(Math.round(f.avg).toString(), 26.sp, weight = FontWeight.Medium)
            }
            Column(Modifier.weight(1f)) {
                txt("Rata-rata FPS", 12.sp, muted())
                txt("%.1f".format(f.avg), 32.sp, weight = FontWeight.Medium)
                Box(Modifier.padding(top = 8.dp).clip(CircleShape).background(acc.copy(alpha = 0.18f)).padding(horizontal = 12.dp, vertical = 6.dp)) {
                    txt("$verdict \u00B7 $smooth%", 12.sp, acc, maxLines = 1)
                }
            }
        }
    }

    AlphaCard {
        val tabs = listOf("FPS", "Frame time", "CPU", "GPU", "Suhu")
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            tabs.forEachIndexed { i, t -> Chip(t, tab == i) { tab = i; touch = -1 } }
        }
        val raw: FloatArray = when (tab) {
            0 -> f.fpsS
            1 -> FloatArray(f.fpsS.size) { if (f.fpsS[it] > 0.5f) 1000f / f.fpsS[it] else 0f }
            2 -> f.cpuS
            3 -> f.gpuS
            else -> f.tempS
        }
        val valid = raw.any { it >= 0f } && raw.isNotEmpty()
        if (!valid || raw.size < 2) {
            txt("Tidak ada data untuk grafik ini.", 12.sp, muted())
        } else {
            val unit = when (tab) { 0 -> " FPS"; 1 -> " ms"; 4 -> "\u00B0"; else -> "%" }
            val maxV = maxOf(raw.max(), 1f).let { if (tab == 0) maxOf(it, 30f) else it } * 1.1f
            txt(
                if (touch in raw.indices) "%.1f%s  \u00B7  detik ${touch * f.secs / maxOf(1, raw.size - 1)}".format(raw[touch], unit)
                else "Sentuh grafik untuk melihat nilai",
                12.sp, muted(), modifier = Modifier.padding(bottom = 8.dp),
            )
            var w by remember { mutableStateOf(1) }
            Canvas(
                Modifier.fillMaxWidth().height(170.dp)
                    .onSizeChanged { w = maxOf(1, it.width) }
                    .pointerInput(raw) { detectTapGestures(onPress = { o -> touch = (o.x / w * (raw.size - 1)).toInt().coerceIn(0, raw.size - 1); tryAwaitRelease() }) }
                    .pointerInput(raw) { detectDragGestures { c, _ -> touch = (c.position.x / w * (raw.size - 1)).toInt().coerceIn(0, raw.size - 1) } },
            ) {
                val h = size.height
                for (g in 0..2) drawLine(Color.White.copy(alpha = 0.10f), Offset(0f, h * g / 2f), Offset(size.width, h * g / 2f), 1.dp.toPx())
                val path = Path(); val fill = Path()
                var started = false
                raw.forEachIndexed { i, v ->
                    val x = size.width * i / (raw.size - 1)
                    val y = h - (v.coerceAtLeast(0f) / maxV) * h
                    if (!started) { path.moveTo(x, y); fill.moveTo(x, h); fill.lineTo(x, y); started = true }
                    else { path.lineTo(x, y); fill.lineTo(x, y) }
                }
                fill.lineTo(size.width, h); fill.close()
                drawPath(fill, Brush.verticalGradient(listOf(acc.copy(alpha = 0.30f), Color.Transparent)))
                drawPath(path, acc, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round))
                if (touch in raw.indices) {
                    val x = size.width * touch / (raw.size - 1)
                    drawLine(Color.White.copy(alpha = 0.5f), Offset(x, 0f), Offset(x, h), 1.dp.toPx())
                    drawCircle(acc, 4.dp.toPx(), Offset(x, h - (raw[touch].coerceAtLeast(0f) / maxV) * h))
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                txt("0:00", 11.sp, muted()); txt(dur2(f.secs), 11.sp, muted())
            }
        }
        // strip momen lambat: tiap kotak = potongan waktu; terang = ada stutter
        if (f.fpsS.size >= 10) {
            val buckets = 60.coerceAtMost(f.fpsS.size)
            val thr = (f.median * 0.7).toFloat()
            Row(Modifier.fillMaxWidth().padding(top = 12.dp).height(8.dp), horizontalArrangement = Arrangement.spacedBy(1.dp)) {
                for (b in 0 until buckets) {
                    val a = b * f.fpsS.size / buckets; val z = maxOf(a + 1, (b + 1) * f.fpsS.size / buckets)
                    var slow = false
                    for (i in a until z) if (f.fpsS[i] < thr) { slow = true; break }
                    Box(Modifier.weight(1f).fillMaxSize().background(if (slow) acc else Color.White.copy(alpha = 0.12f)))
                }
            }
            txt("Warna aksen = momen lambat", 11.sp, muted(), modifier = Modifier.padding(top = 6.dp))
        }
    }

    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        statTile("1% terendah", "%.1f".format(f.low1), Modifier.weight(1f))
        statTile("5% terendah", "%.1f".format(f.low5), Modifier.weight(1f))
        statTile("Stutter", "${f.stutters}x", Modifier.weight(1f))
    }
    Spacer(Modifier.height(8.dp))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        statTile("Maks", Math.round(f.fpsS.maxOrNull() ?: 0f).toString(), Modifier.weight(1f))
        statTile("Min", Math.round(f.fpsS.minOrNull() ?: 0f).toString(), Modifier.weight(1f))
        statTile("Durasi", dur2(f.secs), Modifier.weight(1f))
    }
    Spacer(Modifier.height(10.dp))
}

private fun dur2(secs: Int): String = "${secs / 60}:${(secs % 60).toString().padStart(2, '0')}"

@Composable
private fun statTile(k: String, v: String, modifier: Modifier) {
    Column(
        modifier.clip(RoundedCornerShape(16.dp)).background(Ink.copy(alpha = LocalUi.current.cardAlpha))
            .border(BorderStroke(0.6.dp, Color.White.copy(alpha = 0.14f)), RoundedCornerShape(16.dp)).padding(12.dp),
    ) {
        txt(k, 11.sp, muted(), maxLines = 1)
        txt(v, 20.sp, weight = FontWeight.Medium, maxLines = 1, modifier = Modifier.padding(top = 4.dp))
    }
}
