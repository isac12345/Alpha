package com.alphabubble

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader

class SuExecutor private constructor() {

    companion object {
        @Volatile private var INSTANCE: SuExecutor? = null
        fun getInstance(): SuExecutor = INSTANCE ?: synchronized(this) {
            INSTANCE ?: SuExecutor().also { INSTANCE = it }
        }
    }

    private val shell: String = resolveSu()

    private fun resolveSu(): String {
        val candidates = listOf(
            "/system/bin/su",
            "/system/xbin/su",
            "/sbin/su",
            "/system/sbin/su",
            "/vendor/bin/su",
            "/su/bin/su",
            "/magisk/.core/bin/su"
        )
        return candidates.firstOrNull { java.io.File(it).exists() && java.io.File(it).canExecute() }
            ?: "su"
    }

    data class ExecResult(
        val success: Boolean,
        val exitCode: Int,
        val out: List<String>,
        val err: List<String>
    )

    suspend fun exec(command: String): ExecResult = withContext(Dispatchers.IO) {
        try {
            val pb = ProcessBuilder(shell, "-c", command)
            pb.redirectErrorStream(false)
            val process = pb.start()

            val outLines = mutableListOf<String>()
            val errLines = mutableListOf<String>()

            BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                reader.forEachLine { outLines.add(it) }
            }
            BufferedReader(InputStreamReader(process.errorStream)).use { reader ->
                reader.forEachLine { errLines.add(it) }
            }

            val exitCode = process.waitFor()
            ExecResult(exitCode == 0, exitCode, outLines, errLines)
        } catch (e: Exception) {
            ExecResult(false, -1, emptyList(), listOf(e.message ?: "exec failed"))
        }
    }

    suspend fun execMulti(commands: List<String>): List<ExecResult> = withContext(Dispatchers.IO) {
        commands.map { exec(it) }
    }
}