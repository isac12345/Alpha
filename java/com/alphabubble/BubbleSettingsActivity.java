package com.alphabubble;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.util.Log;
import android.widget.LinearLayout;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

public final class BubbleSettingsActivity extends Activity {
    private static final String TAG = "BubbleSettings";
    private static final String PREFS = "alpha_bubble";
    private static final String KEY_HIDDEN = "hidden";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (16 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("Pengaturan Bubble");
        title.setTextSize(20);
        root.addView(title);

        TextView desc = new TextView(this);
        desc.setText("Saklar di bawah mengontrol apakah bubble tampil. Perubahan tersimpan dan berlaku segera bila service hidup.");
        root.addView(desc);

        Switch sw = new Switch(this);
        sw.setText("Tampilkan bubble");
        boolean hidden = prefs().getBoolean(KEY_HIDDEN, false);
        sw.setChecked(!hidden);
        root.addView(sw);

        sw.setOnCheckedChangeListener((buttonView, show) -> applyShow(show));
        setContentView(root);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (!Settings.canDrawOverlays(this)) {
            try {
                Toast.makeText(this, "Izin tampil di atas aplikasi lain belum diberikan", Toast.LENGTH_LONG).show();
                Intent i = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + getPackageName()));
                startActivity(i);
            } catch (Exception e) {
                Log.w(TAG, "onResume: buka overlay permission gagal: " + e);
            }
        }
    }

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private void applyShow(boolean show) {
        boolean wantHidden = !show;
        SharedPreferences sp = prefs();
        boolean curHidden;
        try {
            curHidden = sp.getBoolean(KEY_HIDDEN, false);
        } catch (Exception e) {
            Log.w(TAG, "applyShow: baca prefs gagal: " + e);
            return;
        }
        if (curHidden == wantHidden) {
            return;
        }
        try {
            if (isServiceRunning(BubbleServiceName())) {
                // Service hidup: biarkan service yang menulis prefs via toggle
                // (xor di onStartCommand) supaya applyVisibility sinkron.
                Intent t = new Intent(this, Class.forName(BubbleServiceName()));
                t.setAction("com.alphabubble.BUBBLE_TOGGLE");
                startForegroundService(t);
            } else {
                try {
                    sp.edit().putBoolean(KEY_HIDDEN, wantHidden).apply();
                } catch (Exception e) {
                    Log.w(TAG, "applyShow: tulis prefs gagal: " + e);
                    return;
                }
                Intent s = new Intent(this, Class.forName(BubbleServiceName()));
                startForegroundService(s);
            }
        } catch (Exception e) {
            Log.w(TAG, "applyShow: kirim ke service gagal: " + e);
        }
    }

    private static String BubbleServiceName() {
        return "com.alphabubble.BubbleService";
    }

    private boolean isServiceRunning(String className) {
        try {
            ActivityManager am = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
            if (am == null) return false;
            for (ActivityManager.RunningServiceInfo s : am.getRunningServices(64)) {
                if (s != null && s.service != null && className.equals(s.service.getClassName())) {
                    return true;
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "isServiceRunning gagal: " + e);
        }
        return false;
    }
}
