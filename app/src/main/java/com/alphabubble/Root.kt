package com.alphabubble

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Eksekusi perintah root lewat `su -c`. Semua panggilan berjalan di thread IO. */
object Root {
    data class Res(val code: Int, val out: String) {
        val ok: Boolean get() = code == 0
    }

    suspend fun exec(cmd: String, timeoutMs: Long = 20_000L): Res =
        runInterruptible(Dispatchers.IO) { execBlocking(cmd, timeoutMs) }

    fun execBlocking(cmd: String, timeoutMs: Long = 20_000L): Res {
        var p: Process? = null
        try {
            p = ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start()
            val proc: Process = p
            val sb = StringBuilder()
            val reader = thread(isDaemon = true) {
                try {
                    proc.inputStream.bufferedReader().use { sb.append(it.readText()) }
                } catch (_: Exception) {
                }
            }
            val done = proc.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            if (!done) {
                proc.destroyForcibly()
                reader.join(1000)
                return Res(-1, sb.toString().trim())
            }
            reader.join(2000)
            return Res(proc.exitValue(), sb.toString().trim())
        } catch (e: InterruptedException) {
            p?.destroyForcibly()
            throw e
        } catch (e: Exception) {
            return Res(-2, e.message ?: "")
        }
    }

    @Volatile
    private var modCache: String = ""

    /** Path modul Alpha Fusion (Magisk / KernelSU / APatch), kosong bila tidak ada. */
    suspend fun modPath(force: Boolean = false): String {
        if (!force && modCache.isNotEmpty()) return modCache
        val r = exec(
            "for d in /data/adb/modules /data/adb/ksu/modules /data/adb/ap/modules; do " +
                "[ -f \"\$d/alpha_uperf_fasrs_fusion/module.prop\" ] && echo \"\$d/alpha_uperf_fasrs_fusion\" && break; done"
        )
        modCache = r.out.lines().lastOrNull { it.startsWith("/") }.orEmpty().trim()
        return modCache
    }

    suspend fun hasRoot(): Boolean = exec("id -u", 8_000L).out.trim().endsWith("0")
}
