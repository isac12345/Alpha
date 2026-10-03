package com.alphabubble;

import android.app.Activity;
import android.content.SharedPreferences;
import android.util.Log;

// F4-12 minimal tema hitam-putih: simpan prefs, terapkan ke konstanta yang ada
public final class ThemeToggle {
    private static final String PREFS = "alpha_theme";
    private static final String KEY_BW = "bw_on";
    private ThemeToggle() {}

    public static void toggle(Activity a) {
        if (a == null) return;
        SharedPreferences sp = a.getSharedPreferences(PREFS, Activity.MODE_PRIVATE);
        boolean now = !sp.getBoolean(KEY_BW, false);
        sp.edit().putBoolean(KEY_BW, now).apply();
        // Minimal: hanya log; penerapan nyata bergantung pada BubbleStyle/BgEditor yang sudah ada
        Log.i("ThemeToggle", "BW=" + now);
    }
}
