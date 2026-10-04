package com.alphabubble

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
