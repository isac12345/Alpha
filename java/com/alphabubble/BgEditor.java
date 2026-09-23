package com.alphabubble;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Typeface;
import android.net.Uri;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

// Fix5: editor crop background — zoom, geser, rasio layar, Fill/Fit,
// simpan privat + inSampleSize. Dibuka dari onActivityResult galeri.
public final class BgEditor {
    private static final String TAG = "BgEditor";
    private static final String PREFS = "alpha_bubble";
    // Dashboard theme constants — consistent with ToolsKit.styleDialog + activity_main.xml
    private static final String CLR_INK = "#f4f2ee";
    private static final String CLR_BG_DARK = "#1e1e1e";
    private static final String CLR_DARK = "#232325";
    private static final float PILL_RADIUS = 24f;

    private BgEditor() {}

    // Hook dari MainActivity.onActivityResult (uri galeri). Return true bila
    // ditangani (editor dibuka), false bila flow asli dilanjutkan.
    public static boolean handlePick(Activity a, Uri uri) {
        final boolean[] done = {false};
        HelperGuard.run(a, "bgPick", () -> {
            done[0] = openEditor(a, uri);
        });
        return done[0];
    }

    private static boolean openEditor(final Activity a, final Uri uri) throws Throwable {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        InputStream is = a.getContentResolver().openInputStream(uri);
        if (is == null) return false;
        try { BitmapFactory.decodeStream(is, null, o); } catch (Throwable t) {
            Log.w(TAG, "bounds gagal: " + t);
            return false;
        } finally {
            try { is.close(); } catch (Throwable t) {
                Log.w(TAG, "close gagal: " + t);
            }
        }
        if (o.outWidth <= 0 || o.outHeight <= 0) return false;
        int maxSide = 1600;
        int sample = 1;
        while (Math.max(o.outWidth, o.outHeight) / sample > maxSide) sample *= 2;
        BitmapFactory.Options o2 = new BitmapFactory.Options();
        o2.inSampleSize = sample;
        InputStream is2 = a.getContentResolver().openInputStream(uri);
        if (is2 == null) return false;
        final Bitmap src;
        try {
            src = BitmapFactory.decodeStream(is2, null, o2);
        } catch (Throwable t) {
            Log.w(TAG, "decode gagal: " + t);
            return false;
        } finally {
            try { is2.close(); } catch (Throwable t) {
                Log.w(TAG, "close gagal: " + t);
            }
        }
        if (src == null) return false;

        int sw = a.getResources().getDisplayMetrics().widthPixels;
        int sh = a.getResources().getDisplayMetrics().heightPixels;
        final float targetRatio = (float) sw / sh;

        LinearLayout root = new LinearLayout(a);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor(CLR_BG_DARK));
        int pad = (int) (12 * a.getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(a);
        title.setText("Atur latar (cubit untuk zoom, geser untuk posisi)");
        title.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        title.setTextColor(Color.parseColor(CLR_INK));
        title.setTextSize(14);
        root.addView(title);

        final ZoomView zv = new ZoomView(a, src, targetRatio);
        LinearLayout.LayoutParams zlp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1.0f);
        root.addView(zv, zlp);

        final RadioGroup rg = new RadioGroup(a);
        rg.setOrientation(RadioGroup.HORIZONTAL);
        final RadioButton rbFill = new RadioButton(a);
        rbFill.setId(View.generateViewId());
        rbFill.setText("Fill");
        rbFill.setTypeface(Typeface.MONOSPACE);
        rbFill.setTextColor(Color.parseColor(CLR_INK));
        final RadioButton rbFit = new RadioButton(a);
        rbFit.setId(View.generateViewId());
        rbFit.setText("Fit");
        rbFit.setTypeface(Typeface.MONOSPACE);
        rbFit.setTextColor(Color.parseColor(CLR_INK));
        rg.addView(rbFill);
        rg.addView(rbFit);
        rg.check(rbFill.getId());
        root.addView(rg);

        final AlertDialog[] box = new AlertDialog[1];
        Button ok = new Button(a);
        ok.setText("SIMPAN");
        // Pill-solid style: dark fill, light text, radius 24
        float density = a.getResources().getDisplayMetrics().density;
        android.graphics.drawable.GradientDrawable okBg =
                new android.graphics.drawable.GradientDrawable();
        okBg.setCornerRadius(PILL_RADIUS * density);
        okBg.setColor(Color.parseColor(CLR_DARK));
        ok.setBackground(okBg);
        ok.setTextColor(Color.parseColor(CLR_INK));
        ok.setTypeface(Typeface.MONOSPACE);
        ok.setTextSize(11);
        ok.setElevation(0);
        ok.setStateListAnimator(null);
        ok.setOnClickListener(v -> HelperGuard.run(a, "bgSave", () -> {
            try {
                boolean fill = rg.getCheckedRadioButtonId() == rbFill.getId();
                Bitmap out = zv.render(fill);
                if (out == null) return;
                File f = new File(a.getFilesDir(), "app_bg_crop.png");
                try (FileOutputStream fos = new FileOutputStream(f)) {
                    out.compress(Bitmap.CompressFormat.PNG, 90, fos);
                }
                SharedPreferences sp = a.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
                try {
                    a.getContentResolver().takePersistableUriPermission(uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION);
                } catch (Throwable t) {
                    Log.w(TAG, "persist perm gagal: " + t);
                }
                sp.edit().putString("app_bg_crop",
                        Uri.fromFile(f).toString())
                        .putString("app_bg_mode", fill ? "fill" : "fit").apply();
                try { box[0].dismiss(); } catch (Throwable t) {
                    Log.w(TAG, "dismiss gagal: " + t);
                }
                Toast.makeText(a, "Latar disimpan", Toast.LENGTH_SHORT).show();
                // b26: refresh instan tanpa force-close (dialog = window
                // terpisah; Activity utama tak lewat onCreate lagi).
                BgFull.apply(a);
            } catch (Throwable t) {
                Log.w(TAG, "save gagal: " + t);
            }
        }));
        root.addView(ok);

        AlertDialog d = new AlertDialog.Builder(a)
                .setView(root)
                .setCancelable(true)
                .show();
        box[0] = d;
        styleDialog(d);
        return true;
    }

    /** Apply dashboard dialog style: bg #1e1e1e, radius 24 — matches ToolsKit.styleDialog. */
    private static void styleDialog(AlertDialog d) {
        try {
            if (d == null || d.getWindow() == null) return;
            float dens = 1f;
            try { dens = d.getContext().getResources().getDisplayMetrics().density; }
            catch (Throwable t) { Log.w(TAG, "styleDialog: density gagal: " + t); }
            android.graphics.drawable.GradientDrawable gd =
                    new android.graphics.drawable.GradientDrawable();
            gd.setColor(Color.parseColor(CLR_BG_DARK));
            gd.setCornerRadius(PILL_RADIUS * dens);
            d.getWindow().setBackgroundDrawable(gd);
        } catch (Throwable t) {
            Log.w(TAG, "styleDialog: " + t);
        }
    }

    // Terapkan crop tersimpan ke view latar (dipanggil setelah applyAppBackground).
    // Juga set gravity CENTER agar bitmap tidak di-stretch dari kiri-atas.
    public static void applyCrop(View bgView) {
        HelperGuard.run(bgView != null ? bgView.getContext() : null, "bgApply", () -> {
            try {
                android.graphics.drawable.Drawable d =
                        (android.graphics.drawable.Drawable) bgView.getBackground();
                if (d instanceof android.graphics.drawable.BitmapDrawable) {
                    ((android.graphics.drawable.BitmapDrawable) d)
                            .setGravity(android.view.Gravity.CENTER);
                }
            } catch (Throwable t) {
                Log.w(TAG, "gravity gagal: " + t);
            }
            Context c = bgView.getContext();
            String u = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getString("app_bg_crop", null);
            if (u == null) return;
            Bitmap bmp = BitmapFactory.decodeFile(new File(Uri.parse(u).getPath()).getAbsolutePath());
            if (bmp == null) {
                Log.w(TAG, "apply: decode crop null");
                return;
            }
            android.graphics.drawable.BitmapDrawable dw =
                    new android.graphics.drawable.BitmapDrawable(c.getResources(), bmp);
            dw.setGravity(android.view.Gravity.CENTER);
            bgView.setBackground(dw);
        });
    }

    private static final class ZoomView extends View {
        private final Bitmap src;
        private final float targetRatio;
        private float scale = 1.0f;
        private float dx, dy;
        private float lastD = -1;
        private float lastX, lastY;

        ZoomView(Context c, Bitmap src, float ratio) {
            super(c);
            this.src = src;
            this.targetRatio = ratio;
        }

        @Override
        protected void onDraw(android.graphics.Canvas canvas) {
            super.onDraw(canvas);
            if (src == null || src.isRecycled()) return;
            int vw = getWidth(), vh = getHeight();
            if (vw <= 0 || vh <= 0) return;
            float base = Math.max((float) vw / src.getWidth(), (float) vh / src.getHeight());
            float s = base * scale;
            float dw = src.getWidth() * s, dh = src.getHeight() * s;
            float maxDx = Math.max(0, (dw - vw) / 2), maxDy = Math.max(0, (dh - vh) / 2);
            dx = Math.max(-maxDx, Math.min(maxDx, dx));
            dy = Math.max(-maxDy, Math.min(maxDy, dy));
            Matrix m = new Matrix();
            m.postTranslate(-src.getWidth() / 2f, -src.getHeight() / 2f);
            m.postScale(s, s);
            m.postTranslate(vw / 2f + dx, vh / 2f + dy);
            try {
                canvas.drawBitmap(src, m, null);
            } catch (Throwable t) {
                Log.w(TAG, "draw gagal: " + t);
            }
        }

        @Override
        public boolean onTouchEvent(MotionEvent e) {
            try {
                int n = e.getPointerCount();
                if (n == 2) {
                    float d = (float) Math.hypot(
                            e.getX(0) - e.getX(1), e.getY(0) - e.getY(1));
                    if (lastD > 0) {
                        scale = Math.max(1.0f, Math.min(4.0f, scale * d / lastD));
                        invalidate();
                    }
                    lastD = d;
                    return true;
                }
                lastD = -1;
                if (e.getAction() == MotionEvent.ACTION_DOWN) {
                    lastX = e.getX();
                    lastY = e.getY();
                } else if (e.getAction() == MotionEvent.ACTION_MOVE && n == 1) {
                    dx += e.getX() - lastX;
                    dy += e.getY() - lastY;
                    lastX = e.getX();
                    lastY = e.getY();
                    invalidate();
                }
                return true;
            } catch (Throwable t) {
                Log.w(TAG, "touch gagal: " + t);
                return false;
            }
        }

        Bitmap render(boolean fill) {
            try {
                int vw = getWidth(), vh = getHeight();
                if (vw <= 0 || vh <= 0 || src == null) return null;
                float base = fill
                        ? Math.max((float) vw / src.getWidth(), (float) vh / src.getHeight())
                        : Math.min((float) vw / src.getWidth(), (float) vh / src.getHeight());
                float s = base * scale;
                Bitmap out = Bitmap.createBitmap(vw, vh, Bitmap.Config.ARGB_8888);
                android.graphics.Canvas cv = new android.graphics.Canvas(out);
                // b26: Fit = letterbox HITAM solid (0xFF000000, sama konvensi
                // BubbleStyle FIT). Tanpa ini kanvas transparan -> tembus ke
                // abu tema dan dikira bug lama belum kelar.
                if (!fill) cv.drawColor(0xFF000000);
                Matrix m = new Matrix();
                m.postTranslate(-src.getWidth() / 2f, -src.getHeight() / 2f);
                m.postScale(s, s);
                m.postTranslate(vw / 2f + dx, vh / 2f + dy);
                cv.drawBitmap(src, m, null);
                return out;
            } catch (Throwable t) {
                Log.w(TAG, "render gagal: " + t);
                return null;
            }
        }
    }
}
