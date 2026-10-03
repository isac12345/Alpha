package com.alphabubble
import kotlinx.coroutines.*
import java.io.*
class RootShell {
    private fun findSu(): String = listOf("su","/system/bin/su","/system/xbin/su","/sbin/su","/su/bin/su").firstOrNull { File(it).exists() } ?: "su"
    suspend fun run(cmd: String, timeout: Long = 10000): RootResult = withContext(Dispatchers.IO) {
        try { val p = ProcessBuilder(findSu(), "-c", cmd).redirectErrorStream(true).start(); p.waitFor(timeout, java.util.concurrent.TimeUnit.MILLISECONDS); val out = p.inputStream.bufferedReader().readText(); RootResult(p.exitValue(), out, "") } catch (e: Exception) { RootResult(-1, "", e.message ?: "") }
    }
    data class RootResult(val exit: Int, val stdout: String, val stderr: String)
}
