package com.alphabubble;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.util.Log;
import android.widget.Toast;

// Pengaman helper Java: bila pemuatan/eksekusi helper crash 2x beruntun
// dalam 10 detik, helper dimatikan (aplikasi jalan seperti build lama)
// + toast singkat. Semua hook WAJIB lewat sini via HelperGuard.run().
public final class HelperGuard {
    private static final String TAG = "HelperGuard";
    private static final String PREFS = "alpha_bubble";
    private static final String KEY_DISABLED = "helper_disabled";
    private static final String KEY_CRASH1 = "helper_crash1_at";
    private static final long WINDOW_MS = 10000L;

    private HelperGuard() {}

    public interface Body {
        void run() throws Throwable;
    }

    public static boolean isDisabled(Context c) {
        try {
            return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getBoolean(KEY_DISABLED, false);
        } catch (Throwable t) {
            Log.w(TAG, "isDisabled gagal: " + t);
            return false;
        }
    }

    public static void run(Context c, String name, Body b) {
        if (c != null && isDisabled(c)) {
            return;
        }
        try {
            b.run();
        } catch (Throwable t) {
            Log.w(TAG, name + " gagal: " + t);
            recordCrash(c, name);
        }
    }

    private static void recordCrash(Context c, String name) {
        if (c == null) return;
        try {
            SharedPreferences sp = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            long now = SystemClock.uptimeMillis();
            long prev = sp.getLong(KEY_CRASH1, 0);
            if (prev != 0 && now - prev < WINDOW_MS) {
                sp.edit().putBoolean(KEY_DISABLED, true).remove(KEY_CRASH1).apply();
                Log.w(TAG, name + ": crash 2x beruntun, helper dimatikan");
                try {
                    Toast.makeText(c, "Fitur tambahan nonaktif (mode aman)", Toast.LENGTH_SHORT).show();
                } catch (Throwable t2) {
                    Log.w(TAG, "toast mode aman gagal: " + t2);
                }
            } else {
                sp.edit().putLong(KEY_CRASH1, now).apply();
            }
        } catch (Throwable t) {
            Log.w(TAG, "recordCrash gagal: " + t);
        }
    }
}
