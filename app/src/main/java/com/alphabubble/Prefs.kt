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
}
