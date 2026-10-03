package com.alphabubble
import android.os.Handler
import android.os.Looper
class RootShell {
    private fun findSu(): String = listOf("su","/system/bin/su","/system/xbin/su","/sbin/su","/su/bin/su").firstOrNull { java.io.File(it).exists() } ?: "su"
    fun run(cmd: String, onDone: (String)->Unit) {
        Thread { try { val p = ProcessBuilder(findSu(),"-c",cmd).redirectErrorStream(true).start(); p.waitFor(10000, java.util.concurrent.TimeUnit.MILLISECONDS); val out = p.inputStream.bufferedReader().readText(); Handler(Looper.getMainLooper()).post { onDone(out) } } catch (e:Exception) { Handler(Looper.getMainLooper()).post { onDone("Gagal: $cmd") } } }.start()
    }
}
