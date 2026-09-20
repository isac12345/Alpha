package com.alphabubble;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
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
    // Dashboard theme constants — consistent with activity_main.xml
    private static final String CLR_INK = "#f4f2ee";
    private static final String CLR_DIM = "#87878a";
    private static final float PILL_RADIUS = 24f;

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
            // Hitung batas skala dinamis: min 48dp sentuh, maks 50% lebar layar, default 100%
            final float density = getResources().getDisplayMetrics().density;
            final int screenWidthPx = getResources().getDisplayMetrics().widthPixels;
            final float screenWidthDp = screenWidthPx / density;
            // Asumsi bubble bawaan (skala 1.0) ~28% lebar layar (umum untuk bubble overlay)
            final float defaultBubbleWidthDp = screenWidthDp * 0.28f;
            final float minScale = Math.max(0.3f, Math.min(48f / defaultBubbleWidthDp, 0.8f));
            final float maxScale = Math.max(1.2f, Math.min((screenWidthDp * 0.5f) / defaultBubbleWidthDp, 2.0f));
            final int MAX_PROGRESS = 1000; // resolusi tinggi untuk presisi
            sbSize.setMax(MAX_PROGRESS);
            sbSize.setOnSeekBarChangeListener(new android.widget.SeekBar.OnSeekBarChangeListener() {
                @Override public void onProgressChanged(android.widget.SeekBar s, int v, boolean f) {
                    HelperGuard.run(BubbleSettingsActivity.this, "sizeSlider", () -> {
                        float sc = minScale + (maxScale - minScale) * v / (float) MAX_PROGRESS;
                        prefs().edit().putFloat("bubble_scale", sc).apply();
                        tvSizeValue.setText(String.format("%.0f%%", sc * 100));
                        // Kirim refresh ke service hidup supaya applyLook dipanggil
                        // (butuh hook smali di BubbleService utk handle BUBBLE_STYLE_REFRESH).
                        if (isServiceRunning(BubbleServiceName())) {
                            try {
                                Intent t = new Intent(BubbleSettingsActivity.this,
                                        Class.forName(BubbleServiceName()));
                                t.setAction("com.alphabubble.BUBBLE_STYLE_REFRESH");
                                startForegroundService(t);
                            } catch (Throwable t2) {
                                Log.w(TAG, "style refresh intent gagal: " + t2);
                            }
                        }
                    });
                }
                @Override public void onStartTrackingTouch(android.widget.SeekBar s) {}
                @Override public void onStopTrackingTouch(android.widget.SeekBar s) {
                    HelperGuard.run(BubbleSettingsActivity.this, "sizeToast", () -> {
                        Toast.makeText(BubbleSettingsActivity.this,
                                "Tersimpan & berlaku", Toast.LENGTH_SHORT).show();
                    });
                }
            });
            root.addView(sbSize);
            refreshSlider(minScale, maxScale, MAX_PROGRESS);
            android.widget.Button bReset = new android.widget.Button(this);
            bReset.setText("Reset ke bawaan");
            stylePillOutline(bReset);
            bReset.setOnClickListener(v -> {
                BubbleStyle.resetDefaults(this);
                refreshSlider(minScale, maxScale, MAX_PROGRESS);
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

    private void refreshSlider(float minScale, float maxScale, int maxProgress) {
        if (sbSize == null) return;
        try {
            float sc = prefs().getFloat("bubble_scale", 1.0f);
            if (sc < minScale || sc > maxScale) sc = 1.0f;
            int progress = Math.round((sc - minScale) * maxProgress / (maxScale - minScale));
            sbSize.setProgress(progress);
            if (tvSizeValue != null) tvSizeValue.setText(String.format("%.0f%%", sc * 100));
        } catch (Throwable t) {
            Log.w(TAG, "refreshSlider gagal: " + t);
        }
    }

    private void refreshSlider() {
        // Default fallback (should not be called after onCreate)
        refreshSlider(0.6f, 1.4f, 1000);
    }

    /** Pill-outline button: transparent fill, dim stroke, monospace, theme colors. */
    private static void stylePillOutline(android.widget.Button b) {
        try {
            float d = b.getResources().getDisplayMetrics().density;
            GradientDrawable gd = new GradientDrawable();
            gd.setCornerRadius(PILL_RADIUS * d);
            gd.setColor(Color.TRANSPARENT);
            gd.setStroke((int) (1 * d), Color.parseColor(CLR_DIM));
            b.setBackground(gd);
            b.setTextColor(Color.parseColor(CLR_INK));
            b.setTypeface(Typeface.MONOSPACE);
            b.setTextSize(11);
            int ph = (int) (16 * d), pv = (int) (8 * d);
            b.setPadding(ph, pv, ph, pv);
            b.setElevation(0);
            b.setStateListAnimator(null);
        } catch (Throwable t) {
            Log.w(TAG, "stylePillOutline: " + t);
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
