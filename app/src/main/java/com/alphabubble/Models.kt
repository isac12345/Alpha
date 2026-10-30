package com.alphabubble

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

data class Status(
    val profile: String = "none",
    val active: String = "none",
    val monitor: Boolean = false,
    val watchdog: Boolean = false,
    val auto: Boolean = false,
    val fasrsNode: Boolean = false,
    val fasrsMode: String = "",
    val cpuOwner: String = "",
    val tempC: Float = 0f,
    val socTempC: Float = 0f,
    val batt: Int = -1,
    val battStatus: String = "",
    val gamePkg: String = "",
    val gameSecs: Long = 0L,
    val hudPkg: String = "",
    val rec: Boolean = false,
    val ovd: Boolean = false,
    val ovdLevel: String = "",
    val ovdLast: String = "",
    val thermalWarmC: Int = 75,
    val ver: Int = 0,
)

data class GameEntry(val pkg: String, val profile: String, val fps: String)

data class SessionEntry(
    val epoch: Long,
    val pkg: String,
    val durSecs: Long,
    val peakC: Float,
    val battStart: Int,
    val battEnd: Int,
    val profile: String,
)

data class Health(
    val uperf: Boolean = false,
    val fasrs: Boolean = false,
    val monitor: Boolean = false,
    val watchdog: Boolean = false,
    val auto: Boolean = false,
    val bootGuard: Boolean = true,
    val bootFail: Int = 0,
)

data class RenderInfo(
    val current: String = "default",
    val available: List<String> = listOf("default", "skiagl"),
    val api: Int = 0,
)

data class LogLine(
    val timeMs: Long?,
    val cat: String,
    val status: String,
    val msg: String,
    val raw: String,
)

data class BatteryInfo(
    val level: Int = -1,
    val status: String = "",
    val health: String = "",
    val tempC: Float = 0f,
    val voltageMv: Int = 0,
    val currentMa: Int = 0,
    val cycles: Int = -1,
    val healthPct: Int = -1,
    val tech: String = "",
)

data class AppItem(val pkg: String, val label: String, val isGame: Boolean)

sealed class Dlg {
    data class Confirm(
        val title: String,
        val text: String,
        val okLabel: String,
        val checkLabel: String? = null,
        val checkDefault: Boolean = false,
        val onOk: (Boolean) -> Unit,
    ) : Dlg()

    data class Info(
        val title: String,
        val text: String,
        val actionLabel: String? = null,
        val action: (() -> Unit)? = null,
    ) : Dlg()
}

fun profileLabel(p: String): String = when (p) {
    "battery" -> "DAILY"
    "balanced" -> "BALANCED"
    "performance" -> "PERF"
    "overdrive" -> "OVERDRIVE"
    else -> "—"
}

fun profileShort(p: String): String = when (p) {
    "battery" -> "DAY"
    "balanced" -> "BAL"
    "performance" -> "PERF"
    else -> "…"
}

val PROFILE_KEYS = listOf("battery", "balanced", "performance")
val PROFILE_LABELS = listOf("DAILY", "BALANCED", "PERF")

/** Ringkasan FPS satu sesi game. low1 = rata-rata 1% sampel terburuk (sampel 1 per detik). */
data class FpsSession(
    val epoch: Long,
    val pkg: String,
    val avg: Int,
    val low1: Int,
    val samples: Int,
    val secs: Int,
    val ovdPct: Int,
    val profile: String,
) {
    fun encode(): String = "$epoch|$pkg|$avg|$low1|$samples|$secs|$ovdPct|$profile"

    companion object {
        fun decode(l: String): FpsSession? {
            val p = l.split('|')
            if (p.size < 8) return null
            return FpsSession(
                p[0].toLongOrNull() ?: return null, p[1],
                p[2].toIntOrNull() ?: return null, p[3].toIntOrNull() ?: return null,
                p[4].toIntOrNull() ?: 0, p[5].toIntOrNull() ?: 0, p[6].toIntOrNull() ?: 0, p[7],
            )
        }

        /** (rata-rata, 1% terendah) dari daftar FPS; null bila terlalu sedikit sampel. */
        fun stats(v: List<Float>): Pair<Int, Int>? {
            if (v.size < 10) return null
            val sorted = v.sorted()
            val n = maxOf(1, Math.ceil(v.size * 0.01).toInt())
            var low = 0.0
            for (i in 0 until n) low += sorted[i]
            return Pair(Math.round(v.average()).toInt(), Math.round(low / n).toInt())
        }
    }
}


/** Status rekam data FPS yang bisa dilihat layar app (diisi FloatingOverlay). */
object FpsLog {
    var on by mutableStateOf(false)
    var rows by mutableStateOf(0)
    var saved by mutableStateOf(0)   // naik tiap berkas tersimpan -> daftar dimuat ulang
}

/** Ringkasan satu berkas CSV rekaman FPS (Download/Alpha_fps_*.csv). */
data class FpsFile(
    val name: String,
    val pkg: String,
    val secs: Int,
    val avg: Double,
    val low1: Double,
    val pctOk: Int,      // % sampel >= 27 FPS
    val pctBad: Int,     // % sampel < 15 FPS
    val tMin: Int,
    val tMax: Int,
    val mode: String,
    val fpsS: FloatArray = FloatArray(0),   // deret per-detik untuk grafik (sejajar dengan fpsS)
    val cpuS: FloatArray = FloatArray(0),
    val gpuS: FloatArray = FloatArray(0),
    val tempS: FloatArray = FloatArray(0),
) {
    /** Stutter = sampel di bawah 70% dari median FPS. */
    val median: Double get() = if (fpsS.isEmpty()) 0.0 else fpsS.sorted()[fpsS.size / 2].toDouble()
    val stutters: Int get() { val m = median * 0.7; return fpsS.count { it < m } }
    val smoothPct: Int get() = if (fpsS.isEmpty()) 0 else 100 - stutters * 100 / fpsS.size
    val low5: Double get() {
        if (fpsS.isEmpty()) return 0.0
        val v = fpsS.sorted(); val k = maxOf(1, Math.ceil(v.size * 0.05).toInt())
        return v.take(k).average()
    }

    companion object {
        fun parse(name: String, text: String): FpsFile? {
            val lines = text.lines().filter { it.isNotBlank() }
            if (lines.size < 11) return null
            val h = lines[0].split(',')
            val iT = h.indexOf("t_detik"); val iP = h.indexOf("paket"); val iF = h.indexOf("fps")
            if (iT < 0 || iF < 0) return null
            val iBat = h.indexOf("suhu_baterai").let { if (it >= 0) it else h.indexOf("suhu_c") }
            val iPr = h.indexOf("profil"); val iOv = h.indexOf("overdrive")
            val fps = ArrayList<Double>(); val temps = ArrayList<Int>()
            val iCpu = h.indexOf("cpu_persen"); val iGpu = h.indexOf("gpu_persen")
            val cpuL = ArrayList<Float>(); val gpuL = ArrayList<Float>(); val tL = ArrayList<Float>()
            var last = 0.0; var pkg = ""; var ov = 0; var n = 0
            val prof = HashMap<String, Int>()
            for (i in 1 until lines.size) {
                val c = lines[i].split(',')
                if (c.size <= iF) continue
                last = c[iT].toDoubleOrNull() ?: last
                if (iP >= 0 && pkg.isEmpty()) pkg = c[iP]
                val f = c[iF].toDoubleOrNull()
                if (f != null && f <= 480.0) {
                    fps.add(f)
                    cpuL.add(if (iCpu >= 0 && c.size > iCpu) c[iCpu].toFloatOrNull() ?: -1f else -1f)
                    gpuL.add(if (iGpu >= 0 && c.size > iGpu) c[iGpu].toFloatOrNull() ?: -1f else -1f)
                    tL.add(if (iBat >= 0 && c.size > iBat) (c[iBat].toFloatOrNull()?.takeIf { it in 1f..105f } ?: -1f) else -1f)
                }
                if (iBat >= 0 && c.size > iBat) c[iBat].toDoubleOrNull()?.toInt()?.takeIf { it in 1..105 }?.let { temps.add(it) }
                n++
                if (iOv >= 0 && c.size > iOv && c[iOv].trim() == "1") ov++
                if (iPr >= 0 && c.size > iPr) prof[c[iPr]] = (prof[c[iPr]] ?: 0) + 1
            }
            if (fps.size < 10) return null
            val sorted = fps.sorted()
            val k = maxOf(1, Math.ceil(fps.size * 0.01).toInt())
            val low = sorted.take(k).average()
            val mode = when {
                iOv < 0 -> "?"
                ov * 2 >= n -> "OVERDRIVE"
                else -> profileLabel(prof.maxByOrNull { it.value }?.key ?: "").uppercase()
            }
            return FpsFile(
                name, pkg, last.toInt(), fps.average(), low,
                fps.count { it >= 27.0 } * 100 / fps.size, fps.count { it < 15.0 } * 100 / fps.size,
                temps.minOrNull() ?: 0, temps.maxOrNull() ?: 0, mode,
                fps.map { it.toFloat() }.toFloatArray(), cpuL.toFloatArray(), gpuL.toFloatArray(), tL.toFloatArray(),
            )
        }
    }
}
