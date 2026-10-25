package com.alphabubble

import android.content.Context
import android.content.SharedPreferences

/** Pengaturan tampilan/bubble milik aplikasi (bukan milik modul). */
class Prefs(ctx: Context) {
    val sp: SharedPreferences = ctx.applicationContext.getSharedPreferences("alpha_ui", Context.MODE_PRIVATE)

    var bubbleOn: Boolean
        get() = sp.getBoolean("bubble_on", false)
        set(v) { sp.edit().putBoolean("bubble_on", v).apply() }
    var bubbleHidden: Boolean
        get() = sp.getBoolean("bubble_hidden", false)
        set(v) { sp.edit().putBoolean("bubble_hidden", v).apply() }
    var bubbleSize: Int
        get() = sp.getInt("bubble_size", 52)
        set(v) { sp.edit().putInt("bubble_size", v).apply() }
    var bubbleShape: Int
        get() = sp.getInt("bubble_shape", 0)
        set(v) { sp.edit().putInt("bubble_shape", v).apply() }
    var bubbleOpacity: Int
        get() = sp.getInt("bubble_opacity", 100)
        set(v) { sp.edit().putInt("bubble_opacity", v).apply() }
    var bubbleX: Int
        get() = sp.getInt("bubble_x", 0)
        set(v) { sp.edit().putInt("bubble_x", v).apply() }
    var bubbleY: Int
        get() = sp.getInt("bubble_y", 400)
        set(v) { sp.edit().putInt("bubble_y", v).apply() }
    var hudOn: Boolean
        get() = sp.getBoolean("hud_on", false)
        set(v) { sp.edit().putBoolean("hud_on", v).apply() }
    var hudX: Int
        get() = sp.getInt("hud_x", 24)
        set(v) { sp.edit().putInt("hud_x", v).apply() }
    var hudY: Int
        get() = sp.getInt("hud_y", 120)
        set(v) { sp.edit().putInt("hud_y", v).apply() }
    var autostart: Boolean
        get() = sp.getBoolean("autostart", true)
        set(v) { sp.edit().putBoolean("autostart", v).apply() }
    var cardAlpha: Float
        get() = sp.getFloat("card_alpha", 0.72f)
        set(v) { sp.edit().putFloat("card_alpha", v).apply() }
    var fit: Int
        get() = sp.getInt("fit", 0)
        set(v) { sp.edit().putInt("fit", v).apply() }
    var accent: Int
        get() = sp.getInt("accent", 0xFFE8E6E1.toInt())
        set(v) { sp.edit().putInt("accent", v).apply() }
    var blur: Int
        get() = sp.getInt("blur", 0)
        set(v) { sp.edit().putInt("blur", v).apply() }
    var contrast: Int
        get() = sp.getInt("contrast", 85)
        set(v) { sp.edit().putInt("contrast", v).apply() }
    var saver: Boolean
        get() = sp.getBoolean("saver", false)
        set(v) { sp.edit().putBoolean("saver", v).apply() }
    var bgVer: Int
        get() = sp.getInt("bg_ver", 0)
        set(v) { sp.edit().putInt("bg_ver", v).apply() }
    var bannerVer: Int
        get() = sp.getInt("banner_ver", 0)
        set(v) { sp.edit().putInt("banner_ver", v).apply() }
    var permAsked: Boolean
        get() = sp.getBoolean("perm_asked", false)
        set(v) { sp.edit().putBoolean("perm_asked", v).apply() }

    // ---------- floating overlay (tahap 2) ----------
    var flScale: Int
        get() = sp.getInt("fl_scale", 100).coerceIn(70, 140)
        set(v) { sp.edit().putInt("fl_scale", v.coerceIn(70, 140)).apply() }
    var flAlpha: Int
        get() = sp.getInt("fl_alpha", 88).coerceIn(40, 100)
        set(v) { sp.edit().putInt("fl_alpha", v.coerceIn(40, 100)).apply() }
    var flStartThin: Boolean
        get() = sp.getBoolean("fl_start_thin", false)
        set(v) { sp.edit().putBoolean("fl_start_thin", v).apply() }
    var flMFps: Boolean
        get() = sp.getBoolean("fl_m_fps", true)
        set(v) { sp.edit().putBoolean("fl_m_fps", v).apply() }
    var flMCpu: Boolean
        get() = sp.getBoolean("fl_m_cpu", true)
        set(v) { sp.edit().putBoolean("fl_m_cpu", v).apply() }
    var flMGpu: Boolean
        get() = sp.getBoolean("fl_m_gpu", true)
        set(v) { sp.edit().putBoolean("fl_m_gpu", v).apply() }
    var flMRam: Boolean
        get() = sp.getBoolean("fl_m_ram", true)
        set(v) { sp.edit().putBoolean("fl_m_ram", v).apply() }
    var flMTemp: Boolean
        get() = sp.getBoolean("fl_m_temp", true)
        set(v) { sp.edit().putBoolean("fl_m_temp", v).apply() }
    var flGraph: Boolean
        get() = sp.getBoolean("fl_graph", true)
        set(v) { sp.edit().putBoolean("fl_graph", v).apply() }
    var flAccentFixed: Boolean
        get() = sp.getBoolean("fl_accent_fixed", false)
        set(v) { sp.edit().putBoolean("fl_accent_fixed", v).apply() }
    var flAccentColor: Int
        get() = sp.getInt("fl_accent_color", 0xFFF5A524.toInt())
        set(v) { sp.edit().putInt("fl_accent_color", v).apply() }
    var flXp: Int
        get() = sp.getInt("fl_x_p", 24)
        set(v) { sp.edit().putInt("fl_x_p", v).apply() }
    var flYp: Int
        get() = sp.getInt("fl_y_p", 20)
        set(v) { sp.edit().putInt("fl_y_p", v).apply() }
    var flXl: Int
        get() = sp.getInt("fl_x_l", 24)
        set(v) { sp.edit().putInt("fl_x_l", v).apply() }
    var flYl: Int
        get() = sp.getInt("fl_y_l", 20)
        set(v) { sp.edit().putInt("fl_y_l", v).apply() }
    var flPosVer: Int
        get() = sp.getInt("fl_pos_ver", 0)
        set(v) { sp.edit().putInt("fl_pos_ver", v).apply() }
}
