package com.alphabubble

import android.content.Context
import android.content.SharedPreferences

object Prefs {
    private const val FILE = "alpha_bubble"
    const val KEY_AUTOSTART = "autostart"
    const val KEY_HUD_MODE = "hud_mode"
    const val KEY_MODULE_PATH = "module_path"
    const val KEY_BG_MODE = "bg_mode"
    const val KEY_BG_ALPHA = "bg_alpha"
    const val KEY_BG_IMAGE_PATH = "bg_image_path"
    const val KEY_FLOATING_SIZE = "floating_size"
    const val KEY_FLOATING_VISIBLE = "floating_visible"
    const val KEY_NOTIF_ENABLED = "notif_enabled"

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun isAutostart(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_AUTOSTART, false)

    fun setAutostart(ctx: Context, on: Boolean) =
        prefs(ctx).edit().putBoolean(KEY_AUTOSTART, on).apply()

    fun hudMode(ctx: Context): String =
        prefs(ctx).getString(KEY_HUD_MODE, "detail") ?: "detail"

    fun setHudMode(ctx: Context, mode: String) =
        prefs(ctx).edit().putString(KEY_HUD_MODE, mode).apply()

    fun getModulePath(ctx: Context): String? =
        prefs(ctx).getString(KEY_MODULE_PATH, null)

    fun setModulePath(ctx: Context, path: String) =
        prefs(ctx).edit().putString(KEY_MODULE_PATH, path).apply()

    fun clearModulePath(ctx: Context) =
        prefs(ctx).edit().remove(KEY_MODULE_PATH).apply()

    fun bgMode(ctx: Context): String =
        prefs(ctx).getString(KEY_BG_MODE, "fill") ?: "fill"

    fun setBgMode(ctx: Context, mode: String) =
        prefs(ctx).edit().putString(KEY_BG_MODE, mode).apply()

    fun bgAlpha(ctx: Context): Int =
        prefs(ctx).getInt(KEY_BG_ALPHA, 255)

    fun setBgAlpha(ctx: Context, alpha: Int) =
        prefs(ctx).edit().putInt(KEY_BG_ALPHA, alpha.coerceIn(0, 255)).apply()

    fun bgImagePath(ctx: Context): String? =
        prefs(ctx).getString(KEY_BG_IMAGE_PATH, null)

    fun setBgImagePath(ctx: Context, path: String?) =
        prefs(ctx).edit().putString(KEY_BG_IMAGE_PATH, path).apply()

    fun floatingSize(ctx: Context): Float =
        prefs(ctx).getFloat(KEY_FLOATING_SIZE, 1.0f)

    fun setFloatingSize(ctx: Context, scale: Float) =
        prefs(ctx).edit().putFloat(KEY_FLOATING_SIZE, scale.coerceIn(0.6f, 1.5f)).apply()

    fun isFloatingVisible(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_FLOATING_VISIBLE, true)

    fun setFloatingVisible(ctx: Context, visible: Boolean) =
        prefs(ctx).edit().putBoolean(KEY_FLOATING_VISIBLE, visible).apply()

    fun isNotifEnabled(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_NOTIF_ENABLED, true)

    fun setNotifEnabled(ctx: Context, enabled: Boolean) =
        prefs(ctx).edit().putBoolean(KEY_NOTIF_ENABLED, enabled).apply()
}