package com.alphabubble

import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale

/** Jembatan ke modul: semua perintah lewat common/alphactl.sh (root). */
object Alpha {
    const val STATE = "/data/adb/alpha"

    private suspend fun ctl(args: String, timeout: Long = 20_000L): Root.Res {
        val m = Root.modPath()
        if (m.isEmpty()) return Root.Res(-3, "modul tidak ditemukan")
        return Root.exec("sh $m/common/alphactl.sh $args 2>/dev/null", timeout)
    }

    fun kv(s: String): Map<String, String> {
        val m = LinkedHashMap<String, String>()
        for (line in s.lines()) {
            val i = line.indexOf('=')
            if (i <= 0) continue
            m[line.substring(0, i).trim()] = line.substring(i + 1).trim()
        }
        return m
    }

    private fun jsonArr(s: String): JSONArray? {
        val a = s.indexOf('[')
        val b = s.lastIndexOf(']')
        if (a < 0 || b < a) return null
        return try { JSONArray(s.substring(a, b + 1)) } catch (_: Exception) { null }
    }

    private fun b(m: Map<String, String>, k: String) = m[k] == "1"

    suspend fun status(): Status? {
        val r = ctl("status")
        val m = kv(r.out)
        if (m.isEmpty() || !m.containsKey("profile")) return null
        return Status(
            profile = m["profile"] ?: "none",
            active = m["active"] ?: "none",
            monitor = b(m, "monitor"),
            watchdog = b(m, "watchdog"),
            auto = b(m, "auto"),
            fasrsNode = b(m, "fasrs_node"),
            fasrsMode = m["fasrs_mode"].orEmpty(),
            cpuOwner = m["cpu_owner"].orEmpty(),
            tempC = (m["temp_mc"]?.toLongOrNull() ?: 0L) / 1000f,
            batt = m["batt"]?.toIntOrNull() ?: -1,
            battStatus = m["batt_status"].orEmpty(),
            gamePkg = m["game_pkg"].orEmpty(),
            gameSecs = m["game_secs"]?.toLongOrNull() ?: 0L,
            thermalWarmC = m["thermal_warm_c"]?.toIntOrNull() ?: 75,
            ver = m["ver"]?.toIntOrNull() ?: 0,
        )
    }

    suspend fun setProfile(p: String): Root.Res = ctl("profile $p", 45_000L)

    suspend fun conf(): Map<String, String> = kv(ctl("conf all").out)

    suspend fun setConf(k: String, v: String): Boolean = ctl("conf set $k $v").out.startsWith("OK")

    suspend fun flags(): Map<String, Boolean> = kv(ctl("flags").out).mapValues { it.value == "1" }

    suspend fun setFlag(name: String, on: Boolean): Boolean =
        ctl("flag ${if (on) "set" else "clear"} $name").out.startsWith("OK")

    suspend fun setThermalWarm(c: Int): Boolean = ctl("thermal set $c").out.startsWith("OK")

    suspend fun games(): List<GameEntry> {
        val arr = jsonArr(ctl("games").out) ?: return emptyList()
        val out = ArrayList<GameEntry>()
        for (i in 0 until arr.length()) {
            val o: JSONObject = arr.optJSONObject(i) ?: continue
            out.add(GameEntry(o.optString("package"), o.optString("profile", "balanced"), o.optString("fps")))
        }
        return out
    }

    private val PKG_RE = Regex("^[A-Za-z0-9._]+\\.[A-Za-z0-9._]+$")
    private val FPS_RE = Regex("^[0-9]{1,4}(,[0-9]{1,4})*$")

    suspend fun addGame(pkg: String, fps: String, profile: String): Root.Res {
        if (!PKG_RE.matches(pkg)) return Root.Res(1, "ERROR: package tidak valid")
        val f = fps.replace(" ", "").ifEmpty { "30,60" }
        if (!FPS_RE.matches(f)) return Root.Res(1, "ERROR: FPS tidak valid (contoh 30,60)")
        if (profile !in PROFILE_KEYS) return Root.Res(1, "ERROR: profil tidak valid")
        return ctl("game add $pkg $f $profile", 60_000L)
    }

    suspend fun removeGame(pkg: String): Root.Res {
        if (!PKG_RE.matches(pkg)) return Root.Res(1, "ERROR: package tidak valid")
        return ctl("game remove $pkg", 60_000L)
    }

    suspend fun sessions(): List<SessionEntry> {
        val out = ArrayList<SessionEntry>()
        for (line in ctl("sessions 30").out.lines()) {
            val p = line.trim().split('|')
            if (p.size < 7) continue
            out.add(
                SessionEntry(
                    epoch = p[0].toLongOrNull() ?: continue,
                    pkg = p[1],
                    durSecs = p[2].toLongOrNull() ?: 0L,
                    peakC = (p[3].toLongOrNull() ?: 0L) / 1000f,
                    battStart = p[4].toIntOrNull() ?: 0,
                    battEnd = p[5].toIntOrNull() ?: 0,
                    profile = p[6],
                )
            )
        }
        return out.reversed()
    }

    suspend fun health(): Health? {
        val r = ctl("health")
        val m = kv(r.out)
        if (m.isEmpty()) return null
        return Health(
            uperf = b(m, "uperf"), fasrs = b(m, "fasrs"), monitor = b(m, "monitor"),
            watchdog = b(m, "watchdog"), auto = b(m, "auto"), bootGuard = b(m, "bootguard"),
            bootFail = m["boot_fail"]?.toIntOrNull() ?: 0,
        )
    }

    suspend fun device(redetect: Boolean = false): Map<String, String> {
        val r = ctl(if (redetect) "redetect" else "device", 60_000L)
        val m = LinkedHashMap<String, String>()
        for (line in r.out.lines()) {
            val i = line.indexOf('=')
            if (i <= 0 || line.startsWith("#")) continue
            m[line.substring(0, i).trim()] = line.substring(i + 1).trim().trim('"')
        }
        return m
    }

    suspend fun render(): RenderInfo? {
        val r = ctl("render get")
        val a = r.out.indexOf('{')
        val z = r.out.lastIndexOf('}')
        if (a < 0 || z < a) return null
        return try {
            val o = JSONObject(r.out.substring(a, z + 1))
            val av = o.optJSONArray("available")
            val list = ArrayList<String>()
            if (av != null) for (i in 0 until av.length()) list.add(av.optString(i))
            RenderInfo(o.optString("current", "default"), list.ifEmpty { listOf("default") }, o.optInt("api"))
        } catch (_: Exception) { null }
    }

    suspend fun setRender(v: String): Root.Res = ctl("render set $v", 30_000L)

    suspend fun autoStart(): Root.Res = ctl("autoctl start")

    suspend fun logRaw(n: Int): String = ctl("log $n").out

    private val LOG_FULL = Regex("^\\[(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\] \\[([^\\]]+)\\] (?:\\[([^\\]]+)\\] )?(.*)$")
    private val LOG_SHORT = Regex("^\\[([^\\]]+)\\] (?:\\[([^\\]]+)\\] )?(.*)$")

    fun parseLog(raw: String): List<LogLine> {
        val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        val out = ArrayList<LogLine>()
        for (line in raw.lines()) {
            if (line.isBlank()) continue
            val m = LOG_FULL.matchEntire(line)
            if (m != null) {
                val t = try { fmt.parse(m.groupValues[1])?.time } catch (_: Exception) { null }
                out.add(LogLine(t, m.groupValues[2], m.groupValues[3], m.groupValues[4], line))
                continue
            }
            val s = LOG_SHORT.matchEntire(line)
            if (s != null) out.add(LogLine(null, s.groupValues[1], s.groupValues[2], s.groupValues[3], line))
            else out.add(LogLine(null, "LOG", "", line, line))
        }
        return out
    }

    fun logMatches(l: LogLine, f: String): Boolean = when (f) {
        "ERROR" -> l.status.uppercase() in setOf("ERROR", "FAILED", "WARN", "WARNING") || l.msg.contains("ERROR")
        "CPU" -> l.cat.uppercase().startsWith("CPU")
        "GAME" -> l.cat.uppercase().let { it.startsWith("GAME") || it == "SESSION" }
        "INPUT" -> l.cat.uppercase().startsWith("INPUT")
        else -> true
    }

    suspend fun battery(): BatteryInfo {
        val r = Root.exec(
            "b=/sys/class/power_supply/battery; for k in capacity status health temp voltage_now current_now " +
                "cycle_count charge_full charge_full_design technology; do echo \"\$k=\$(cat \$b/\$k 2>/dev/null)\"; done",
            10_000L
        )
        val m = kv(r.out)
        val temp = (m["temp"]?.toIntOrNull() ?: 0) / 10f
        val vRaw = m["voltage_now"]?.toLongOrNull() ?: 0L
        val iRaw = m["current_now"]?.toLongOrNull() ?: 0L
        val vMv = if (vRaw > 100000) (vRaw / 1000).toInt() else vRaw.toInt()
        val iMa = if (kotlin.math.abs(iRaw) > 20000) (iRaw / 1000).toInt() else iRaw.toInt()
        val full = m["charge_full"]?.toLongOrNull() ?: 0L
        val design = m["charge_full_design"]?.toLongOrNull() ?: 0L
        val hp = if (full > 0 && design > 0) ((full * 100) / design).toInt().coerceIn(0, 120) else -1
        return BatteryInfo(
            level = m["capacity"]?.toIntOrNull() ?: -1,
            status = m["status"].orEmpty(),
            health = m["health"].orEmpty(),
            tempC = temp,
            voltageMv = vMv,
            currentMa = iMa,
            cycles = m["cycle_count"]?.toIntOrNull() ?: -1,
            healthPct = hp,
            tech = m["technology"].orEmpty(),
        )
    }

    // ---------- resolusi ----------
    data class Res3(val w: Int, val h: Int, val d: Int)
    data class ResInfo(val nat: Res3, val act: Res3, val hasOverride: Boolean)

    suspend fun resolution(): ResInfo? {
        val r = Root.exec("wm size; wm density", 10_000L)
        var pw = 0; var ph = 0; var ow = 0; var oh = 0; var pd = 0; var od = 0
        val sizeRe = Regex("(\\d+)x(\\d+)")
        for (line in r.out.lines()) {
            val l = line.lowercase()
            if (l.startsWith("physical size")) sizeRe.find(l)?.let { pw = it.groupValues[1].toInt(); ph = it.groupValues[2].toInt() }
            else if (l.startsWith("override size")) sizeRe.find(l)?.let { ow = it.groupValues[1].toInt(); oh = it.groupValues[2].toInt() }
            else if (l.startsWith("physical density")) pd = l.filter { it.isDigit() }.toIntOrNull() ?: 0
            else if (l.startsWith("override density")) od = l.filter { it.isDigit() }.toIntOrNull() ?: 0
        }
        if (pw == 0 || ph == 0) return null
        val nat = Res3(pw, ph, pd)
        val act = Res3(if (ow > 0) ow else pw, if (oh > 0) oh else ph, if (od > 0) od else pd)
        return ResInfo(nat, act, ow > 0 || od > 0)
    }

    private fun even(v: Double): Int { val i = Math.round(v).toInt(); return if (i % 2 == 0) i else i + 1 }

    fun resCommand(nat: Res3, pct: Int): String {
        if (pct >= 100) return "wm size reset; wm density reset"
        val w = even(nat.w * pct / 100.0)
        val h = even(nat.h * pct / 100.0)
        val d = Math.round(nat.d * pct / 100.0).toInt()
        return "wm size ${w}x${h}; wm density $d"
    }

    fun restoreCommand(info: ResInfo): String =
        if (!info.hasOverride) "wm size reset; wm density reset"
        else "wm size ${info.act.w}x${info.act.h}; wm density ${info.act.d}"

    /** Terapkan resolusi dengan pengaman: kalau tidak dikonfirmasi, perangkat sendiri mengembalikannya. */
    suspend fun applyResWithGuard(cmd: String, restore: String, guardSecs: Int) {
        Root.exec("rm -f $STATE/.res_keep; nohup sh -c 'sleep $guardSecs; [ -f $STATE/.res_keep ] || { $restore; }' >/dev/null 2>&1 &", 8_000L)
        Root.exec(cmd, 15_000L)
    }

    suspend fun keepRes() { Root.exec("touch $STATE/.res_keep", 5_000L) }

    suspend fun revertRes(restore: String) {
        Root.exec("touch $STATE/.res_keep; $restore", 15_000L)
    }

    suspend fun resetRes() { Root.exec("touch $STATE/.res_keep; wm size reset; wm density reset", 15_000L) }

    // ---------- dexopt & tutup app ----------
    suspend fun dexopt(pkg: String, mode: String): Boolean {
        val cmd = if (mode == "reset") "cmd package compile --reset $pkg" else "cmd package compile -m $mode -f $pkg"
        val r = Root.exec(cmd, 900_000L)
        return r.out.contains("Success", ignoreCase = true)
    }

    suspend fun forceStop(pkgs: List<String>): Root.Res {
        val list = pkgs.filter { PKG_RE.matches(it) }
        val sb = StringBuilder()
        if (list.isNotEmpty()) sb.append("for p in ${list.joinToString(" ")}; do am force-stop \"\$p\"; done; ")
        sb.append("am kill-all; echo done")
        return Root.exec(sb.toString(), 120_000L)
    }
}
