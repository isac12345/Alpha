package com.alphabubble

import android.content.Context
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

private fun sq(s: String): String = "'${s.replace("'", "'\\''")}'"

object RootShell {
    const val STATE_DIR = "/data/adb/alpha"
    const val CURRENT_STATE_FILE = "/data/adb/alpha/current_state"
    const val LOG_FILE = "/data/adb/alpha/alpha.log"
    const val DETECT_CONF = "/data/adb/alpha/detected.conf"
    const val PID_FILE = "/data/adb/alpha/monitor.pid"
    const val MODULE_ID = "alpha_uperf_fasrs_fusion"
    private val MODULE_BASES = listOf(
        "/data/adb/modules",
        "/data/adb/ksu/modules",
        "/data/adb/ap/modules"
    )

    data class ExecResult(
        val success: Boolean,
        val exitCode: Int,
        val out: List<String>,
        val err: List<String>
    )

    data class DisplayInfo(
        val width: Int,
        val height: Int,
        val density: Int,
        val refreshRates: List<Int>
    )

    data class RenderInfo(
        val backend: String,
        val backends: List<String>
    )

    data class MonitorStatus(
        val running: Boolean,
        val pid: Int?
    )

    data class GameEntry(
        val packageName: String,
        val label: String,
        val profile: String?
    )

    data class LogEntry(
        val category: String,
        val status: String,
        val detail: String
    )

    private val suExecutor = SuExecutor.getInstance()

    private suspend fun suExec(cmd: String): ExecResult = withContext(Dispatchers.IO) {
        suExecutor.exec(cmd).let { ExecResult(it.success, it.exitCode, it.out, it.err) }
    }

    suspend fun hasRoot(): Boolean = withContext(Dispatchers.IO) {
        suExec("id").success
    }

    suspend fun exec(cmd: String): ExecResult = suExec(cmd)

    private fun moduleScriptPath(modulePath: String, script: String): String =
        "$modulePath/common/$script"

    private fun findModuleDirInternal(): String? {
        for (base in MODULE_BASES) {
            val candidate = File(base, MODULE_ID)
            if (candidate.exists() && candidate.isDirectory) {
                return candidate.absolutePath
            }
        }
        return null
    }

    suspend fun findModulePath(ctx: Context): String? = withContext(Dispatchers.IO) {
        val cached = Prefs.getModulePath(ctx)
        if (cached != null && File(cached).exists()) return@withContext cached
        val found = findModuleDirInternal()
        found?.let { Prefs.setModulePath(ctx, it) }
        found
    }

    suspend fun redetect(ctx: Context, autoDetect: Boolean = false): ExecResult = withContext(Dispatchers.IO) {
        val modulePath = findModulePath(ctx) ?: return@withContext ExecResult(false, -1, emptyList(), listOf("Module not found"))
        val script = moduleScriptPath(modulePath, "detect.sh")
        val force = if (autoDetect) "ALPHA_FORCE_DETECT=1 " else ""
        suExec("$force sh $script")
    }

    suspend fun applyProfile(ctx: Context, profile: String): ExecResult = withContext(Dispatchers.IO) {
        val modulePath = findModulePath(ctx) ?: return@withContext ExecResult(false, -1, emptyList(), listOf("Module not found"))
        val script = moduleScriptPath(modulePath, "apply_now.sh")
        suExec("sh $script ${sq(profile)}")
    }

    suspend fun readCurrentState(): String? = withContext(Dispatchers.IO) {
        val f = File(CURRENT_STATE_FILE)
        if (f.exists()) f.readText().trim().takeIf { it.isNotEmpty() } else null
    }

    suspend fun deviceInfo(ctx: Context, autoDetect: Boolean = false): ExecResult = withContext(Dispatchers.IO) {
        val r = redetect(ctx, autoDetect)
        if (!r.success) return@withContext r
        val f = File(DETECT_CONF)
        if (f.exists()) ExecResult(true, 0, f.readLines(), emptyList())
        else ExecResult(false, -1, emptyList(), listOf("detected.conf not found"))
    }

    suspend fun displayInfo(): DisplayInfo? = withContext(Dispatchers.IO) {
        val r = suExec("dumpsys display 2>/dev/null | grep -m1 'mDisplayWidth\\|mDisplayHeight\\|mDensity\\|mRefreshRate'")
        if (!r.success) return@withContext null
        var w = 0, h = 0, dens = 0
        val rates = mutableListOf<Int>()
        for (line in r.out) {
            if (line.contains("mDisplayWidth")) w = line.substringAfterLast("=").trim().toIntOrNull() ?: 0
            else if (line.contains("mDisplayHeight")) h = line.substringAfterLast("=").trim().toIntOrNull() ?: 0
            else if (line.contains("mDensity")) dens = line.substringAfterLast("=").trim().toIntOrNull() ?: 0
            else if (line.contains("mRefreshRate")) {
                val rate = line.substringAfterLast("=").trim().toFloatOrNull()
                if (rate != null) rates.add((rate + 0.5f).toInt())
            }
        }
        if (w > 0 && h > 0) DisplayInfo(w, h, dens, rates.distinct()) else null
    }

    suspend fun renderGet(): RenderInfo? = withContext(Dispatchers.IO) {
        val r = suExec("cat /data/adb/alpha/render_backend 2>/dev/null")
        if (!r.success || r.out.isEmpty()) return@withContext null
        val active = r.out[0].trim()
        val r2 = suExec("ls /data/adb/alpha/render_backends/ 2>/dev/null")
        val backends = if (r2.success) r2.out.map { it.trim() }.filter { it.isNotEmpty() } else listOf(active)
        RenderInfo(active, backends)
    }

    suspend fun renderSet(value: String): ExecResult = withContext(Dispatchers.IO) {
        suExec("echo ${sq(value)} > /data/adb/alpha/render_backend && sh /data/adb/alpha/common/render_manager.sh apply")
    }

    suspend fun applyDisplay(info: DisplayInfo, percent: Int): ExecResult = withContext(Dispatchers.IO) {
        val w = (info.width * percent / 100).coerceAtLeast(1)
        val h = (info.height * percent / 100).coerceAtLeast(1)
        suExec("wm size ${w}x${h}")
    }

    suspend fun resetDisplay(): ExecResult = withContext(Dispatchers.IO) {
        suExec("wm size reset")
    }

    suspend fun dexopt(mode: String, pkg: String): ExecResult = withContext(Dispatchers.IO) {
        suExec("cmd package compile -m $mode -f $pkg")
    }

    suspend fun gameList(ctx: Context): List<GameEntry> = withContext(Dispatchers.IO) {
        val modulePath = findModulePath(ctx) ?: return@withContext emptyList()
        val mapFile = File(modulePath, "game_profile_map.conf")
        if (!mapFile.exists()) return@withContext emptyList()
        val lines = mapFile.readLines()
        val pkgMgr = ctx.packageManager
        return@withContext lines.mapNotNull { line ->
            val parts = line.split("=")
            if (parts.size != 2) return@mapNotNull null
            val pkg = parts[0].trim()
            val profile = parts[1].trim()
            try {
                val appInfo = pkgMgr.getApplicationInfo(pkg, 0)
                val label = pkgMgr.getApplicationLabel(appInfo).toString()
                GameEntry(pkg, label, if (profile.isEmpty()) null else profile)
            } catch (e: Exception) {
                GameEntry(pkg, pkg, if (profile.isEmpty()) null else profile)
            }
        }
    }

    suspend fun addGameFlow(ctx: Context, pkg: String, profile: String): ExecResult = withContext(Dispatchers.IO) {
        val modulePath = findModulePath(ctx) ?: return@withContext ExecResult(false, -1, emptyList(), listOf("Module not found"))
        val script = moduleScriptPath(modulePath, "game_add.sh")
        suExec("sh $script ${sq(pkg)} ${sq(profile)}")
    }

    suspend fun removeGameFlow(ctx: Context, pkg: String): ExecResult = withContext(Dispatchers.IO) {
        val modulePath = findModulePath(ctx) ?: return@withContext ExecResult(false, -1, emptyList(), listOf("Module not found"))
        val mapFile = File(modulePath, "game_profile_map.conf")
        val lines = mapFile.readLines().filter { !it.startsWith("$pkg=") }
        mapFile.writeText(lines.joinToString("\n") + "\n")
        ExecResult(true, 0, listOf("removed"), emptyList())
    }

    suspend fun monitorStatus(): MonitorStatus = withContext(Dispatchers.IO) {
        val pidFile = File(PID_FILE)
        if (!pidFile.exists()) return@withContext MonitorStatus(false, null)
        val pid = pidFile.readText().trim().toIntOrNull()
        if (pid == null) return@withContext MonitorStatus(false, null)
        val r = suExec("kill -0 $pid 2>/dev/null && echo alive || echo dead")
        MonitorStatus(r.success && r.out.firstOrNull() == "alive", pid)
    }

    suspend fun setMonitor(start: Boolean): ExecResult = withContext(Dispatchers.IO) {
        val modulePath = findModuleDirInternal() ?: return@withContext ExecResult(false, -1, emptyList(), listOf("Module not found"))
        val script = moduleScriptPath(modulePath, "monitor.sh")
        val action = if (start) "start" else "stop"
        suExec("sh $script $action")
    }

    suspend fun fullLog(limit: Int = 200): List<LogEntry> = withContext(Dispatchers.IO) {
        val r = suExec("grep -E '\\[(CPU_GOV|CPU_FREQ|KERNEL_BOOST|DEVFREQ|IO|VM|THERMAL|NET|GPU|APPLY|MONITOR)\\]' '$LOG_FILE' 2>/dev/null | tail -$limit")
        if (!r.success) return@withContext emptyList()
        return@withContext r.out.reversed().mapNotNull { line ->
            val m = Regex("\\[([A-Z_]+)\\]\\s+\\[([A-Z_]+)\\]\\s+(.*)").matchEntire(line.trim())
            if (m != null) LogEntry(m.groupValues[1], m.groupValues[2], m.groupValues[3])
            else LogEntry("", "", line.trim())
        }
    }

    suspend fun tailLog(limit: Int = 30): List<LogEntry> = withContext(Dispatchers.IO) {
        val r = suExec("grep -E '\\[(CPU_GOV|CPU_FREQ|KERNEL_BOOST|DEVFREQ|IO|VM|THERMAL|NET|GPU|APPLY|MONITOR)\\]' '$LOG_FILE' 2>/dev/null | tail -$limit")
        if (!r.success) return@withContext emptyList()
        return@withContext r.out.reversed().mapNotNull { line ->
            val m = Regex("\\[([A-Z_]+)\\]\\s+\\[([A-Z_]+)\\]\\s+(.*)").matchEntire(line.trim())
            if (m != null) LogEntry(m.groupValues[1], m.groupValues[2], m.groupValues[3])
            else LogEntry("", "", line.trim())
        }
    }

    suspend fun activeDisplayInfo(): DisplayInfo? = displayInfo()
}