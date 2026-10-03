package com.alphabubble;

import android.app.Activity;
import android.content.SharedPreferences;
import android.util.Log;

// F4-13 posisi bubble: simpan prefs (kiri/kanan). Penerapan ke FloatingBubbleService bergantung implementasi service yang belum diedit.
public final class BubblePos {
    private static final String PREFS = "alpha_bubble_pos";
    private static final String KEY = "pos";
    private BubblePos() {}

    public static void set(Activity a, String pos) {
        if (a == null) return;
        a.getSharedPreferences(PREFS, Activity.MODE_PRIVATE).edit().putString(KEY, pos).apply();
        Log.i("BubblePos", "pos=" + pos);
    }
}
