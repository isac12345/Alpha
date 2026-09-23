package com.alphabubble;

import android.app.Activity;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;

// Animasi ringan satu-shot (<200ms) untuk seluruh interaksi: sentuh semua
// tombol, pop tab aktif, fade-in grup. Tanpa library, tanpa loop.
// Menghormati animator_duration_scale=0 (aksesibilitas/hemat baterai).
public final class UiAnim {
    private static final String TAG = "UiAnim";

    private UiAnim() {}

    public static boolean animOff(Activity a) {
        try {
            float s = Settings.Global.getFloat(a.getContentResolver(),
                    Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
            return s == 0f;
        } catch (Throwable t) {
            Log.w(TAG, "scale gagal: " + t);
            return false;
        }
    }

    // Pasang feedback sentuh ke SEMUA Button di bawah root (sekali di attach).
    public static void pressAll(Activity a, View root) {
        HelperGuard.run(a, "animPress", () -> {
            if (root == null || animOff(a)) return;
            wireTouch(a, root);
        });
    }

    private static void wireTouch(final Activity a, View v) throws Throwable {
        if (v instanceof Button) {
            final Button b = (Button) v;
            b.setOnTouchListener((view, e) -> {
                try {
                    if (animOff(a)) return false;
                    if (Build.VERSION.SDK_INT < 21) return false;
                    int act = e.getActionMasked();
                    if (act == MotionEvent.ACTION_DOWN) {
                        view.animate().cancel();
                        view.animate().scaleX(0.96f).scaleY(0.96f)
                                .setDuration(80).start();
                    } else if (act == MotionEvent.ACTION_UP
                            || act == MotionEvent.ACTION_CANCEL) {
                        view.animate().cancel();
                        view.animate().scaleX(1f).scaleY(1f)
                                .setDuration(100).start();
                    }
                } catch (Throwable t) {
                    Log.w(TAG, "touch gagal: " + t);
                }
                // FALSE agar onClick tetap jalan (listener lama tak diganggu).
                return false;
            });
        } else if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) {
                wireTouch(a, g.getChildAt(i));
            }
        }
    }

    // Pop tab yang baru aktif (dipanggil setelah paint).
    public static void tabPop(Activity a, View v) {
        HelperGuard.run(a, "animPop", () -> {
            if (v == null || animOff(a)) return;
            if (Build.VERSION.SDK_INT < 21) return;
            v.animate().cancel();
            v.setScaleX(0.95f);
            v.setScaleY(0.95f);
            v.animate().scaleX(1f).scaleY(1f).setDuration(120).start();
        });
    }

    // Fade-in grup yang baru ditampilkan.
    public static void fadeIn(Activity a, View v) {
        HelperGuard.run(a, "animFade", () -> {
            if (v == null || animOff(a)) return;
            if (Build.VERSION.SDK_INT < 21) return;
            v.animate().cancel();
            v.setAlpha(0f);
            v.animate().alpha(1f).setDuration(150).start();
        });
    }
}
