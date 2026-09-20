package com.alphabubble;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
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

    private Switch swShow;
    private TextView tvPermStatus;
    private android.widget.SeekBar sbSize;
    private TextView tvSizeValue;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#232325"));
        int pad = (int) (16 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("Pengaturan Bubble");
        title.setTextSize(20);
        title.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        title.setTextColor(Color.parseColor("#f4f2ee"));
        root.addView(title);

        tvPermStatus = new TextView(this);
        tvPermStatus.setTypeface(Typeface.MONOSPACE);
        tvPermStatus.setTextColor(Color.parseColor("#87878a"));
        tvPermStatus.setTextSize(12);
        root.addView(tvPermStatus);

        TextView desc = new TextView(this);
        desc.setText("Saklar di bawah mengontrol apakah bubble tampil. Perubahan tersimpan dan berlaku segera bila service hidup.");
        desc.setTypeface(Typeface.MONOSPACE);
        desc.setTextColor(Color.parseColor("#87878a"));
        root.addView(desc);

        swShow = new Switch(this);
        swShow.setText("Tampilkan bubble");
        swShow.setTypeface(Typeface.MONOSPACE);
        swShow.setTextColor(Color.parseColor("#f4f2ee"));
        root.addView(swShow);

        swShow.setOnCheckedChangeListener((buttonView, show) -> applyShow(show));
        setContentView(root);

        try {
            android.widget.Button bBg = new android.widget.Button(this);
            bBg.setText("Pilih latar bubble");
            bBg.setTypeface(Typeface.MONOSPACE);
            bBg.setOnClickListener(v -> BubbleStyle.pickBackground(this, 8001));
            root.addView(bBg);
        } catch (Throwable t) {
            Log.w(TAG, "onCreate: tombol latar gagal: " + t);
        }
        try {
            TextView lbSize = new TextView(this);
            lbSize.setText("Ukuran bubble");
            lbSize.setTypeface(Typeface.MONOSPACE);
            lbSize.setTextColor(Color.parseColor("#87878a"));
            root.addView(lbSize);
            tvSizeValue = new TextView(this);
            tvSizeValue.setTypeface(Typeface.MONOSPACE);
            tvSizeValue.setTextColor(Color.parseColor("#f4f2ee"));
            tvSizeValue.setTextSize(14);
            root.addView(tvSizeValue);
            sbSize = new android.widget.SeekBar(this);
            sbSize.setMax(80);
            sbSize.setOnSeekBarChangeListener(new android.widget.SeekBar.OnSeekBarChangeListener() {
                @Override public void onProgressChanged(android.widget.SeekBar s, int v, boolean f) {
                    try {
                        float sc = 0.6f + v / 100.0f;
                        prefs().edit().putFloat("bubble_scale", sc).apply();
                        tvSizeValue.setText(String.format("%.0f%%", sc * 100));
                    }
                    catch (Throwable t) { Log.w(TAG, "size gagal: " + t); }
                }
                @Override public void onStartTrackingTouch(android.widget.SeekBar s) {}
                @Override public void onStopTrackingTouch(android.widget.SeekBar s) {
                    try {
                        Toast.makeText(BubbleSettingsActivity.this,
                                "Berlaku saat bubble dibuka ulang", Toast.LENGTH_SHORT).show();
                    } catch (Throwable t) { Log.w(TAG, "size toast gagal: " + t); }
                }
            });
            root.addView(sbSize);
            refreshSlider();
            android.widget.Button bReset = new android.widget.Button(this);
            bReset.setText("Reset ke bawaan");
            bReset.setTypeface(Typeface.MONOSPACE);
            bReset.setOnClickListener(v -> {
                BubbleStyle.resetDefaults(this);
                refreshSlider();
                try {
                    Toast.makeText(this, "Kembali bawaan", Toast.LENGTH_SHORT).show();
                } catch (Throwable t) { Log.w(TAG, "reset toast gagal: " + t); }
            });
            root.addView(bReset);
        } catch (Throwable t) {
            Log.w(TAG, "onCreate: slider gagal: " + t);
        }
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req != 8001 || res != RESULT_OK || data == null || data.getData() == null) return;
        HelperGuard.run(this, "cropBg", () -> {
            try {
                android.graphics.Bitmap bmp = BubbleStyle.cropSquare(this, data.getData(), 256);
                if (bmp == null) return;
                String path = new java.io.File(getCacheDir(), "bubble_bg.png").getAbsolutePath();
                try (java.io.FileOutputStream fos = new java.io.FileOutputStream(path)) {
                    bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, fos);
                }
                prefs().edit().putString("app_bg_uri", android.net.Uri.fromFile(new java.io.File(path)).toString()).apply();
                Toast.makeText(this, "Latar bubble diganti", Toast.LENGTH_SHORT).show();
            } catch (Throwable t) {
                Log.w(TAG, "cropBg gagal: " + t);
            }
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshPermStatus();
        resyncSwitch();
    }

    private void refreshPermStatus() {
        boolean granted;
        try {
            granted = Settings.canDrawOverlays(this);
        } catch (Throwable t) {
            Log.w(TAG, "refreshPermStatus: canDrawOverlays gagal: " + t);
            granted = false;
        }
        try {
            tvPermStatus.setText(granted
                    ? "Izin overlay: aktif"
                    : "Izin overlay: belum diberikan");
        } catch (Throwable t) {
            Log.w(TAG, "refreshPermStatus: set teks gagal: " + t);
        }
    }

    private void resyncSwitch() {
        boolean hidden;
        try {
            hidden = prefs().getBoolean(KEY_HIDDEN, false);
        } catch (Throwable t) {
            Log.w(TAG, "resyncSwitch: baca prefs gagal: " + t);
            return;
        }
        try {
            swShow.setOnCheckedChangeListener(null);
            swShow.setChecked(!hidden);
        } catch (Throwable t) {
            Log.w(TAG, "resyncSwitch: set switch gagal: " + t);
        } finally {
            try {
                swShow.setOnCheckedChangeListener((buttonView, show) -> applyShow(show));
            } catch (Throwable t) {
                Log.w(TAG, "resyncSwitch: pasang listener gagal: " + t);
            }
        }
    }

    private void refreshSlider() {
        if (sbSize == null) return;
        try {
            float sc = prefs().getFloat("bubble_scale", 1.0f);
            if (sc < 0.6f || sc > 1.4f) sc = 1.0f;
            sbSize.setProgress(Math.round((sc - 0.6f) * 100));
            if (tvSizeValue != null) tvSizeValue.setText(String.format("%.0f%%", sc * 100));
        } catch (Throwable t) {
            Log.w(TAG, "refreshSlider gagal: " + t);
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
        } catch (Throwable t) {
            Log.w(TAG, "applyShow: baca prefs gagal: " + t);
            return;
        }
        if (curHidden == wantHidden) {
            return;
        }
        if (show) {
            boolean granted;
            try {
                granted = Settings.canDrawOverlays(this);
            } catch (Throwable t) {
                Log.w(TAG, "applyShow: canDrawOverlays gagal: " + t);
                granted = false;
            }
            if (!granted) {
                try {
                    Toast.makeText(this, "Berikan izin tampil di atas aplikasi lain dulu", Toast.LENGTH_LONG).show();
                    Intent i = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:" + getPackageName()));
                    startActivity(i);
                } catch (Throwable t) {
                    Log.w(TAG, "applyShow: buka overlay permission gagal: " + t);
                }
                refreshPermStatus();
                resyncSwitch();
                return;
            }
        }
        try {
            if (isServiceRunning(BubbleServiceName())) {
                // Service hidup: biarkan service yang menulis prefs via toggle
                // (xor di onStartCommand, BubbleService.smali:2085-2097) supaya
                // applyVisibility sinkron. Intent sama persis dengan aksi
                // notifikasi: konstruktor (ctx, BubbleService.class) +
                // setAction BUBBLE_TOGGLE, tanpa extras
                // (BubbleService.smali:1608-1632).
                Intent t = new Intent(this, Class.forName(BubbleServiceName()));
                t.setAction("com.alphabubble.BUBBLE_TOGGLE");
                startForegroundService(t);
            } else {
                try {
                    sp.edit().putBoolean(KEY_HIDDEN, wantHidden).apply();
                } catch (Throwable t) {
                    Log.w(TAG, "applyShow: tulis prefs gagal: " + t);
                    return;
                }
                Intent s = new Intent(this, Class.forName(BubbleServiceName()));
                startForegroundService(s);
            }
        } catch (Throwable t) {
            Log.w(TAG, "applyShow: kirim ke service gagal: " + t);
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
        } catch (Throwable t) {
            Log.w(TAG, "isServiceRunning gagal: " + t);
        }
        return false;
    }
}
