package com.alphabubble;

import android.app.Activity;
import android.content.SharedPreferences;
import android.util.Log;
import android.widget.TextView;
import android.widget.Toast;
import java.util.Date;
import java.text.SimpleDateFormat;
import java.util.Locale;

// F3-11: logbook FPS manual (JUJUR: tidak bisa baca FPS meter app lain karena uid beda).
public final class FpsLogbook {
    private static final String TAG = "FpsLogbook";
    private static final String PREFS = "alpha_fps_log";
    private FpsLogbook() {}

    public static void addEntry(Activity a, String pkg, int avgFps, int stutter, String note) {
        if (a == null || pkg == null || pkg.isEmpty()) return;
        SharedPreferences sp = a.getSharedPreferences(PREFS, Activity.MODE_PRIVATE);
        String key = "fps_" + pkg;
        String existing = sp.getString(key, "");
        String ts = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(new Date());
        String entry = ts + " | avg=" + avgFps + " stutter=" + stutter + "% | " + (note == null ? "" : note) + "\n";
        sp.edit().putString(key, existing + entry).apply();
        Toast.makeText(a, "FP S dicatat untuk " + pkg, Toast.LENGTH_SHORT).show();
    }

    public static void show(Activity a, String pkg, TextView tv) {
        if (a == null || tv == null) return;
        SharedPreferences sp = a.getSharedPreferences(PREFS, Activity.MODE_PRIVATE);
        String val = sp.getString("fps_" + pkg, "(belum ada data — input manual)");
        tv.setText(val);
    }
}
