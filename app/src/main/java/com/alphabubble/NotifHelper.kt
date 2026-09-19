package com.alphabubble

import android.content.Context
import android.graphics.drawable.Icon
import android.service.quicksettings.Tile
import androidx.core.content.ContextCompat

object NotifHelper {
    val PROFILES = listOf("battery", "balanced", "performance")

    fun isValidProfile(p: String): Boolean = p in PROFILES

    fun labelFor(profile: String): String = when (profile) {
        "battery" -> "Battery"
        "performance" -> "Performance"
        else -> "Balanced"
    }

    fun titleFor(profile: String): String = "Alpha: ${labelFor(profile)}"

    fun iconForProfile(context: Context, profile: String): Icon =
        Icon.createWithResource(context, when (profile) {
            "battery" -> R.drawable.ic_profile_battery
            "performance" -> R.drawable.ic_profile_perf
            else -> R.drawable.ic_profile_balanced
        })

    fun sq(v: String): String = "'${v.replace("'", "'\\''")}'"

    fun isValidPackage(pkg: String): Boolean =
        "^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+$".toRegex().matches(pkg)

    fun isValidFps(fps: String): Boolean {
        if (fps.isEmpty()) return false
        return fps.split(",").all { it.toIntOrNull() != null }
    }
}