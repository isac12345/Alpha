package com.alphabubble

import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Eksekusi shell root. Semua pemanggilan blocking: panggil dari thread background (Sh.bg). */
object Sh {
    private val pool = Executors.newFixedThreadPool(3)
    val ui = Handler(Looper.getMainLooper())

    class Res(val out: String, val err: String, val code: Int) {
        val ok: Boolean get() = code == 0
    }

    fun bg(block: () -> Unit) {
        pool.execute {
            try { block() } catch (_: Throwable) { }
        }
    }

    fun q(s: String): String = "'" + s.replace("'", "'\\''") + "'"

    fun run(cmd: String, timeoutMs: Long = 30000L): Res {
        return try {
            val p = ProcessBuilder("su").start()
            val outB = StringBuilder()
            val errB = StringBuilder()
            val t1 = Thread {
                try { p.inputStream.bufferedReader().forEachLine { outB.append(it).append('\n') } } catch (_: Exception) { }
            }
            val t2 = Thread {
                try { p.errorStream.bufferedReader().forEachLine { errB.append(it).append('\n') } } catch (_: Exception) { }
            }
            t1.start(); t2.start()
            p.outputStream.use { it.write((cmd + "\nexit\n").toByteArray()) }
            val done = p.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            if (!done) p.destroy()
            t1.join(1000); t2.join(1000)
            Res(outB.toString().trim(), errB.toString().trim(), if (done) p.exitValue() else -1)
        } catch (e: Exception) {
            Res("", e.message ?: "su error", -2)
        }
    }
}

/** Jembatan ke skrip modul Alpha Fusion (path & argumen sesuai modul v50). */
object Alpha {
    const val STATE = "/data/adb/alpha"
    const val MOD_ID = "alpha_uperf_fasrs_fusion"

    @Volatile var mod: String = ""
    @Volatile var rootOk: Boolean = false

    val ready: Boolean get() = rootOk && mod.isNotEmpty()

    @Synchronized
    fun ensure() {
        if (ready) return
        rootOk = Sh.run("id").out.contains("uid=0")
        if (rootOk) findModule()
    }

    fun findModule(): String {
        val r = Sh.run(
            "for d in /data/adb/modules /data/adb/ksu/modules /data/adb/ap/modules; do " +
                "[ -f \"\$d/$MOD_ID/module.prop\" ] && echo \"\$d/$MOD_ID\" && break; done"
        )
        mod = r.out.lines().firstOrNull { it.startsWith("/") } ?: ""
        return mod
    }

    private fun sc(name: String): String = "sh " + Sh.q("$mod/common/$name")

    // ---------- profil ----------
    fun applyProfile(p: String): Sh.Res = Sh.run("${sc("apply_now.sh")} $p manual", 60000L)

    fun currentProfile(): String {
        val s = Sh.run("cat $STATE/current_state 2>/dev/null").out.lowercase()
        return when {
            s.contains("battery") -> "battery"
            s.contains("performance") -> "performance"
            s.contains("balanced") -> "balanced"
            else -> ""
        }
    }

    fun profileTitle(p: String): String = when (p) {
        "battery" -> "BATTERY"
        "balanced" -> "BALANCED"
        "performance" -> "PERFORMANCE"
        else -> "—"
    }

    // ---------- game ----------
    class Game(val pkg: String, val profile: String, val fps: String, val fasrs: Boolean)

    fun games(): List<Game> {
        val r = Sh.run(
            "${sc("game_manager.sh")} list; echo '@@SEP@@'; ${sc("engine_manager.sh")} list"
        ).out
        val parts = r.split("@@SEP@@")
        val map = LinkedHashMap<String, String>()
        val fps = HashMap<String, String>()
        try {
            val a = JSONArray(parts.getOrElse(0) { "[]" }.trim().ifEmpty { "[]" })
            for (i in 0 until a.length()) {
                val o: JSONObject = a.getJSONObject(i)
                map[o.getString("package")] = o.getString("profile")
            }
        } catch (_: Exception) { }
        try {
            val b = JSONArray(parts.getOrElse(1) { "[]" }.trim().ifEmpty { "[]" })
            for (i in 0 until b.length()) {
                val o: JSONObject = b.getJSONObject(i)
                fps[o.getString("package")] = o.optString("fps")
            }
        } catch (_: Exception) { }
        val all = LinkedHashSet<String>()
        all.addAll(map.keys)
        all.addAll(fps.keys)
        return all.map { Game(it, map[it] ?: "balanced", fps[it] ?: "", fps.containsKey(it)) }
    }

    fun addGame(pkg: String, profile: String, fpsCsv: String): Sh.Res {
        val fps = if (fpsCsv.isBlank()) "30,60" else fpsCsv.trim()
        return Sh.run("${sc("game_add.sh")} add ${Sh.q(pkg)} $profile ${Sh.q(fps)}", 90000L)
    }

    fun removeGame(pkg: String): Sh.Res =
        Sh.run("${sc("game_add.sh")} remove ${Sh.q(pkg)}; ${sc("game_manager.sh")} remove ${Sh.q(pkg)}", 90000L)

    // ---------- render ----------
    class RenderInfo(val current: String, val available: List<String>)

    fun renderLabel(v: String): String = when (v) {
        "skiavk" -> "Vulkan (Skia)"
        "skiagl" -> "OpenGL (Skia)"
        else -> "Default"
    }

    fun renderGet(): RenderInfo? {
        val r = Sh.run("${sc("render_manager.sh")} get").out
        return try {
            val o = JSONObject(r.lines().last { it.startsWith("{") })
            val a = o.getJSONArray("available")
            RenderInfo(o.getString("current"), (0 until a.length()).map { a.getString(it) })
        } catch (_: Exception) { null }
    }

    fun renderSet(v: String): Sh.Res = Sh.run("${sc("render_manager.sh")} set $v", 60000L)

    // ---------- resolusi ----------
    class Disp(val nw: Int, val nh: Int, val cw: Int, val ch: Int, val nd: Int, val cd: Int)

    fun display(): Disp? {
        val s = Sh.run("wm size; wm density").out
        val size = Regex("Physical size: (\\d+)x(\\d+)").find(s) ?: return null
        val over = Regex("Override size: (\\d+)x(\\d+)").find(s)
        val dens = Regex("Physical density: (\\d+)").find(s) ?: return null
        val dov = Regex("Override density: (\\d+)").find(s)
        val nw = size.groupValues[1].toInt()
        val nh = size.groupValues[2].toInt()
        val nd = dens.groupValues[1].toInt()
        return Disp(
            nw, nh,
            over?.groupValues?.get(1)?.toInt() ?: nw,
            over?.groupValues?.get(2)?.toInt() ?: nh,
            nd, dov?.groupValues?.get(1)?.toInt() ?: nd
        )
    }

    fun applyRes(d: Disp, percent: Int): Sh.Res {
        if (percent >= 100) return resetRes()
        val w = (d.nw * percent / 100) / 2 * 2
        val h = (d.nh * percent / 100) / 2 * 2
        val dpi = d.nd * percent / 100
        return Sh.run("wm size ${w}x$h; wm density $dpi")
    }

    fun resetRes(): Sh.Res = Sh.run("wm size reset; wm density reset")

    // ---------- tools ----------
    fun dexopt(pkg: String): Sh.Res =
        Sh.run("cmd package compile -m speed-profile -f ${Sh.q(pkg)}", 600000L)

    fun closeAll(self: String): Sh.Res = Sh.run(
        "for p in \$(pm list packages -3 | cut -d: -f2); do [ \"\$p\" != ${Sh.q(self)} ] && am force-stop \"\$p\"; done; am kill-all"
    )

    // ---------- log ----------
    class LogLine(val ts: String, val cat: String, val st: String, val msg: String)

    private val logRe = Regex("^\\[(.*?)\\] \\[(.*?)\\] \\[(.*?)\\] (.*)$")

    fun logs(limit: Int): List<LogLine> {
        val raw = Sh.run("tail -n 500 $STATE/alpha.log 2>/dev/null").out
        val list = raw.lines().mapNotNull { l ->
            val m = logRe.find(l)
            if (m == null) null else LogLine(m.groupValues[1], m.groupValues[2], m.groupValues[3], m.groupValues[4])
        }
        return list.takeLast(limit).reversed()
    }

    fun rawLog(n: Int): String = Sh.run("tail -n $n $STATE/alpha.log 2>/dev/null").out

    fun ago(ts: String): String {
        return try {
            val d = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).parse(ts) ?: return ts
            val s = (System.currentTimeMillis() - d.time) / 1000
            when {
                s < 60 -> "baru saja"
                s < 3600 -> "${s / 60}m"
                s < 86400 -> "${s / 3600}j"
                else -> "${s / 86400}h"
            }
        } catch (_: Exception) { ts.takeLast(8) }
    }

    // ---------- device ----------
    fun detected(): Map<String, String> {
        val out = HashMap<String, String>()
        val raw = Sh.run("cat $STATE/detected.conf 2>/dev/null").out
        for (l in raw.lines()) {
            val m = Regex("^([A-Z_]+)=\"?(.*?)\"?$").find(l.trim()) ?: continue
            out[m.groupValues[1]] = m.groupValues[2]
        }
        return out
    }

    fun redetect(): Sh.Res =
        Sh.run("rm -f $STATE/detected.conf; ALPHA_FORCE_DETECT=1 ${sc("detect.sh")}", 90000L)

    // ---------- mesin (flag file di /data/adb/alpha) ----------
    class Flags(val fasrsOwnsCpu: Boolean, val cooldownFull: Boolean, val cpusetNarrow: Boolean)

    fun flags(): Flags {
        val s = Sh.run(
            "for f in GB_FASRS_FORCE_ALPHA GB_COOLDOWN_EXTREME NO_CPUSET; do [ -e $STATE/\$f ] && echo \$f; done"
        ).out
        return Flags(
            !s.contains("GB_FASRS_FORCE_ALPHA"),
            s.contains("GB_COOLDOWN_EXTREME"),
            !s.contains("NO_CPUSET")
        )
    }

    fun setFlag(name: String, present: Boolean): Sh.Res =
        Sh.run(if (present) "touch $STATE/$name" else "rm -f $STATE/$name")

    // ---------- status game ----------
    class Status(val temp: String, val fasMode: String, val session: String)

    fun status(): Status {
        val s = Sh.run(
            "for z in /sys/class/thermal/thermal_zone*; do echo \"T \$(cat \$z/type 2>/dev/null) \$(cat \$z/temp 2>/dev/null)\"; done; " +
                "echo \"M \$(cat /dev/fas_rs/mode 2>/dev/null)\"; " +
                "echo \"U \$(cut -d. -f1 /proc/uptime)\"; " +
                "echo \"G \$(cat $STATE/.game_t0 2>/dev/null)\""
        ).out
        var temp = "—"
        var best = -1
        var fas = "—"
        var up = 0L
        var t0 = -1L
        for (l in s.lines()) {
            val p = l.trim().split(" ").filter { it.isNotEmpty() }
            if (p.isEmpty()) continue
            when (p[0]) {
                "T" -> if (p.size >= 3) {
                    val v = p.last().toLongOrNull() ?: continue
                    val type = p[1].lowercase()
                    val score = when {
                        type.contains("soc") -> 3
                        type.contains("cpu") -> 2
                        type.contains("ap") || type.contains("tsens") -> 1
                        else -> 0
                    }
                    if (score > best) {
                        best = score
                        val c = if (v > 1000) v / 1000.0 else v.toDouble()
                        temp = String.format(Locale.US, "%.1f°C", c)
                    }
                }
                "M" -> if (p.size >= 2) fas = p[1]
                "U" -> if (p.size >= 2) up = p[1].toLongOrNull() ?: 0L
                "G" -> if (p.size >= 2) t0 = p[1].toLongOrNull() ?: -1L
            }
        }
        val sess = if (t0 >= 0 && up >= t0) {
            val m = (up - t0) / 60
            if (m >= 60) "${m / 60}j ${m % 60}m" else "${m}m"
        } else "—"
        return Status(temp, fas, sess)
    }
}
