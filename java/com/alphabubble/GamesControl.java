package com.alphabubble;

import android.app.Activity;
import android.content.SharedPreferences;
import android.util.Log;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

// F2 (GAMES): kontrol flags 18, mode fas-rs 20, profil uperf 21.
// Tidak pakai import baru selain android.* + repo.
public final class GamesControl {
    private static final String TAG = "GamesControl";
    private static final String PREFS = "alpha_games";
    private static final String KEY_MODE = "fasrs_mode"; // fast/performance/balance
    public static final String[] FLAGS18 = {
        "/data/adb/alpha/GB_COOLDOWN_EXTREME",
        "/data/adb/alpha/GB_FASRS_FORCE_ALPHA",
        "/data/adb/alpha/GB_FASRS_FORCE_OWNS"
    };
    private GamesControl() {}

    // Fitur 18: toggle flag via RootShell (touch/rm). Baca kondisi awal, tulis balik.
    public static void toggleFlag(final Activity a, final int idx, final String label) {
        if (a == null || idx < 0 || idx >= FLAGS18.length) return;
        final String f = FLAGS18[idx];
        new Thread(() -> {
            try {
                boolean exists = RootExecutor.exec("test -f " + f);
                String cmd = exists ? ("rm -f " + f) : ("touch " + f);
                boolean ok = RootExecutor.exec(cmd);
                final boolean now = !exists;
                a.runOnUiThread(() -> {
                    try {
                        Toast.makeText(a, label + ": " + (now ? "ON" : "OFF"), Toast.LENGTH_SHORT).show();
                    } catch (Throwable t) { Log.w(TAG, "toast gagal: "+t); }
                });
            } catch (Throwable t) {
                Log.w(TAG, "toggleFlag "+label+" gagal: "+t);
            }
        }).start();
    }

    // Fitur 20: mode fas-rs per game disimpan di SharedPreferences, diterapkan via root /dev/fas_rs/mode
    public static void setFasMode(final Activity a, final String pkg, final String mode) {
        if (a == null) return;
        SharedPreferences sp = a.getSharedPreferences(PREFS, Activity.MODE_PRIVATE);
        sp.edit().putString(KEY_MODE + "_" + pkg, mode).apply();
        new Thread(() -> {
            try {
                RootExecutor.exec("echo '" + mode + "' > /dev/fas_rs/mode 2>/dev/null");
            } catch (Throwable t) { Log.w(TAG, "fas mode root gagal: "+t); }
        }).start();
    }

    // Fitur 21: profil uperf (mekanisme modul: profiles.sh + active_profile + apply_now.sh)
    public static void setUperfProfile(final Activity a, final String profile) {
        if (a == null) return;
        new Thread(() -> {
            try {
                // Tulis ke file yang modul baca (service.sh menggunakan ACTIVE_PROFILE_FILE)
                RootExecutor.exec("echo '" + profile + "' > /data/adb/alpha/active_profile");
                RootExecutor.exec("sh /data/adb/modules/alpha_uperf_fasrs_fusion/common/apply_now.sh " + profile + " 2>/dev/null");
            } catch (Throwable t) { Log.w(TAG, "uperf profile root gagal: "+t); }
        }).start();
    }

    // Hook refresh (pola HomeCards): jika ada card control, update tampilan.
    public static void refresh(final Activity a) {
        // Untuk ini hanya pastikan SharedPreferences konsisten di UI; root sudah di thread sendiri.
    }
}
