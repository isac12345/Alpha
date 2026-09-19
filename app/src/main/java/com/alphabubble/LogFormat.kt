package com.alphabubble

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.text.Regex
import kotlin.text.trim

object LogFormat {
    private val lineRe = Regex("^\\[(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\] \\[([A-Z_]+)\\] \\[([A-Z_]+)\\] (.*)$")
    private val pathValRe = Regex("path=(\\S+)\\s+value=(\\S+)")
    private val pathRe = Regex("path=(\\S+)")
    private val tsFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
    private val hmFmt = SimpleDateFormat("HH:mm", Locale.US)

    data class Compact(
        val time: String,
        val status: String,
        val message: String
    )

    data class Entry(
        val timestamp: String,
        val category: String,
        val status: String,
        val detail: String
    )

    fun compact(raw: String, now: Long = System.currentTimeMillis()): Compact {
        val trimmed = raw.trim()
        val m = lineRe.matchEntire(trimmed)
        if (m == null) {
            return Compact("--:--", "LOG", trimmed.take(64))
        }
        var ts: Long = 0
        try {
            val dt = tsFmt.parse(m.groupValues[1])
            if (dt != null) ts = dt.time
        } catch (e: Exception) {
            // ignore
        }
        val rel = relTime(ts, now)
        val status = m.groupValues[2]
        val detail = m.groupValues[3]
        val msg = shortMsg(status, detail)
        return Compact(rel, status, msg)
    }

    private fun relTime(ts: Long, now: Long): String {
        if (ts <= 0) {
            val d = Date(now)
            return hmFmt.format(d)
        }
        if (now < ts) {
            val d = Date(ts)
            return hmFmt.format(d)
        }
        val diffMin = TimeUnit.MILLISECONDS.toMinutes(now - ts)
        return when {
            diffMin < 1 -> "baru saja"
            diffMin < 60 -> "${diffMin} mnt lalu"
            diffMin < 1440 -> "${TimeUnit.MILLISECONDS.toHours(now - ts)} jam lalu"
            else -> {
                val d = Date(ts)
                hmFmt.format(d)
            }
        }
    }

    private fun shortMsg(status: String, detail: String): String {
        val m = pathValRe.find(detail)
        if (m != null) {
            val path = m.groupValues[1]
            val value = m.groupValues[2]
            val name = path.substringAfterLast("/")
            return "$status $name=$value"
        }
        val m2 = pathRe.find(detail)
        if (m2 != null) {
            val path = m2.groupValues[1]
            val name = path.substringAfterLast("/")
            return "$status $name"
        }
        return "$status ${detail.take(48)}"
    }
}