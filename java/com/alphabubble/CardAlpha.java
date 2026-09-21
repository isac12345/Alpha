package com.alphabubble;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;

public final class CardAlpha {
    private static final String TAG = "CardAlpha";
    private static final String PREFS = "alpha_bubble";
    private static final String KEY_CARD_ALPHA = "card_alpha_pct";
    // Warna background kartu gelap membulat: card_bg.xml solid @color/alpha_dark
    // (#0a0a0a, decode res/values/colors.xml:6) + kartu BUBBLE HomeCards (#1e1e1e,
    // HomeCards.java:238). Hanya dua ini yang diubah alphanya; teks tak disentuh.

    private CardAlpha() {}

    /** Apply card alpha from seekbar progress (0-100 -> 30%-100% alpha). */
    public static void applyFromProgress(Activity a, int progress) {
        HelperGuard.run(a, "cardAlphaProgress", () -> {
            try {
                // Map progress 0-100 to alpha 30%-100%
                int pct = 30 + (progress * 70 / 100);
                // Save preference
                a.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .putInt(KEY_CARD_ALPHA, pct).apply();

                // Apply to all card backgrounds
                View root = a.findViewById(android.R.id.content);
                applyRecursive(root, pct);
            } catch (Throwable t) {
                Log.w(TAG, "applyFromProgress gagal: " + t);
            }
        });
    }

    /** Apply card alpha from saved preference (called on activity resume). */
    public static void applyFromPrefs(Activity a) {
        HelperGuard.run(a, "cardAlphaPrefs", () -> {
            try {
                int pct = a.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .getInt(KEY_CARD_ALPHA, 100);
                View root = a.findViewById(android.R.id.content);
                applyRecursive(root, pct);
            } catch (Throwable t) {
                Log.w(TAG, "applyFromPrefs gagal: " + t);
            }
        });
    }

    /** Setup seekbar listener for card alpha. Called from smali hook in MainActivity.onCreate. */
    public static void setupSeekBar(Activity a) {
        HelperGuard.run(a, "cardAlphaSetup", () -> {
            try {
                android.widget.SeekBar sb = a.findViewById(
                        a.getResources().getIdentifier("seekAppBackgroundAlpha", "id", a.getPackageName()));
                if (sb == null) return;
                // Load saved value (default 100)
                int pct = a.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .getInt(KEY_CARD_ALPHA, 100);
                // Convert 30-100% to progress 0-100
                int progress = (pct - 30) * 100 / 70;
                if (progress < 0) progress = 0;
                if (progress > 100) progress = 100;
                sb.setProgress(progress);
                sb.setOnSeekBarChangeListener(new android.widget.SeekBar.OnSeekBarChangeListener() {
                    @Override public void onProgressChanged(android.widget.SeekBar s, int v, boolean f) {
                        applyFromProgress(a, v);
                    }
                    @Override public void onStartTrackingTouch(android.widget.SeekBar s) {}
                    @Override public void onStopTrackingTouch(android.widget.SeekBar s) {}
                });
            } catch (Throwable t) {
                Log.w(TAG, "setupSeekBar gagal: " + t);
            }
        });
    }

    private static void applyRecursive(View v, int pct) {
        if (v == null) return;

        Drawable bg = v.getBackground();
        if (bg instanceof GradientDrawable) {
            GradientDrawable gd = (GradientDrawable) bg;
            // getColor() = ColorStateList (bukan int) — bandingkan defaultColor.
            // setAlpha pada drawable SAJA (bukan View.setAlpha) agar teks tetap terbaca.
            android.content.res.ColorStateList cs = gd.getColor();
            if (cs != null && isCardColor(cs.getDefaultColor())) {
                gd.setAlpha(pct * 255 / 100);
            }
        }

        if (v instanceof ViewGroup) {
            ViewGroup vg = (ViewGroup) v;
            for (int i = 0; i < vg.getChildCount(); i++) {
                applyRecursive(vg.getChildAt(i), pct);
            }
        }
    }

    private static boolean isCardColor(int c) {
        return c == 0xFF0A0A0A || c == 0xFF1E1E1E;
    }
}