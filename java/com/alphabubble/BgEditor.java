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
import android.os.Build;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.Pair;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
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

    /** Return real device screen size (width, height) using priority fallback chain.
     *  1) API 30+: WindowManager.getCurrentWindowMetrics().getBounds() (native, no androidx)
     *  2) decorView.getDisplay().getRealMetrics() (API 17+)
     *  3) WindowManager.getDefaultDisplay().getMetrics()
     *  4) Resources.getDisplayMetrics() (context)
     *  5) Resources.getSystem().getDisplayMetrics() — last resort
     *  Each failure logs warning. Returns null if all fail. */
    private static Pair<Integer, Integer> getRealScreenSize(Activity a) {
        // 1) API 30+: getCurrentWindowMetrics (NATIVE android.app, tanpa library)
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                android.graphics.Rect b = a.getWindowManager().getCurrentWindowMetrics().getBounds();
                if (b.width() > 0 && b.height() > 0) return Pair.create(b.width(), b.height());
            } catch (Throwable ignore) {
                Log.w(TAG, "getRealScreenSize: getCurrentWindowMetrics gagal");
            }
        }
        // 2) decorView.getRealMetrics (API 17+)
        try {
            View decor = a.getWindow().getDecorView();
            DisplayMetrics dm = new DisplayMetrics();
            decor.getDisplay().getRealMetrics(dm);
            if (dm.widthPixels > 0 && dm.heightPixels > 0)
                return Pair.create(dm.widthPixels, dm.heightPixels);
        } catch (Throwable ignore) {
            Log.w(TAG, "getRealScreenSize: decorView getRealMetrics gagal");
        }
        // 3) WindowManager defaultDisplay
        try {
            WindowManager wms = (WindowManager) a.getSystemService(Context.WINDOW_SERVICE);
            DisplayMetrics dm = new DisplayMetrics();
            wms.getDefaultDisplay().getMetrics(dm);
            if (dm.widthPixels > 0 && dm.heightPixels > 0)
                return Pair.create(dm.widthPixels, dm.heightPixels);
        } catch (Throwable ignore) {
            Log.w(TAG, "getRealScreenSize: WindowManager getMetrics gagal");
        }
        // 4) Resources context
        try {
            DisplayMetrics dm = a.getResources().getDisplayMetrics();
            if (dm.widthPixels > 0 && dm.heightPixels > 0)
                return Pair.create(dm.widthPixels, dm.heightPixels);
        } catch (Throwable ignore) {
            Log.w(TAG, "getRealScreenSize: Resources context gagal");
        }
        // 5) Resources.getSystem() — terakhir
        try {
            DisplayMetrics dm = Resources.getSystem().getDisplayMetrics();
            if (dm.widthPixels > 0 && dm.heightPixels > 0) {
                Log.w(TAG, "getRealScreenSize: metrics ctx 0, pakai system " + dm.widthPixels + "x" + dm.heightPixels);
                return Pair.create(dm.widthPixels, dm.heightPixels);
            }
        } catch (Throwable ignore) {
            Log.w(TAG, "getRealScreenSize: Resources.getSystem gagal");
        }
        return null;
    }

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

        Pair<Integer, Integer> screen = getRealScreenSize(a);
        if (screen == null) return false;
        int screenW = screen.first;
        int screenH = screen.second;

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

        final ZoomView zv = new ZoomView(a, src, screenW, screenH);
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
        zv.setFill(true);
        rg.setOnCheckedChangeListener((g, id) -> zv.setFill(id == rbFill.getId()));
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
                        Uri.fromFile(f).toString()).apply();
                try { box[0].dismiss(); } catch (Throwable t) {
                    Log.w(TAG, "dismiss gagal: " + t);
                }
                Toast.makeText(a, "Latar disimpan", Toast.LENGTH_SHORT).show();
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
        private final int screenW;
        private final int screenH;
        private float scale = 1.0f;
        private float dx, dy;
        private float lastD = -1;
        private float lastX, lastY;
        private boolean fill = true;

        ZoomView(Context c, Bitmap src, int screenW, int screenH) {
            super(c);
            this.src = src;
            this.screenW = screenW;
            this.screenH = screenH;
        }

        void setFill(boolean fill) {
            this.fill = fill;
            invalidate();
        }

        @Override
        protected void onDraw(android.graphics.Canvas canvas) {
            super.onDraw(canvas);
            if (src == null || src.isRecycled()) return;
            int vw = getWidth(), vh = getHeight();
            if (vw <= 0 || vh <= 0) return;
            float base = fill
                    ? Math.max((float) screenW / src.getWidth(), (float) screenH / src.getHeight())
                    : Math.min((float) screenW / src.getWidth(), (float) screenH / src.getHeight());
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
                if (src == null || screenW <= 0 || screenH <= 0) return null;
                float base = fill
                        ? Math.max((float) screenW / src.getWidth(), (float) screenH / src.getHeight())
                        : Math.min((float) screenW / src.getWidth(), (float) screenH / src.getHeight());
                float s = base * scale;
                Bitmap out = Bitmap.createBitmap(screenW, screenH, Bitmap.Config.ARGB_8888);
                android.graphics.Canvas cv = new android.graphics.Canvas(out);
                if (!fill) {
                    cv.drawColor(0xFF000000);
                }
                Matrix m = new Matrix();
                m.postTranslate(-src.getWidth() / 2f, -src.getHeight() / 2f);
                m.postScale(s, s);
                float maxDx = Math.max(0, (src.getWidth() * s - screenW) / 2f);
                float maxDy = Math.max(0, (src.getHeight() * s - screenH) / 2f);
                float cx = Math.max(-maxDx, Math.min(maxDx, dx));
                float cy = Math.max(-maxDy, Math.min(maxDy, dy));
                m.postTranslate(screenW / 2f + cx, screenH / 2f + cy);
                cv.drawBitmap(src, m, null);
                return out;
            } catch (Throwable t) {
                Log.w(TAG, "render gagal: " + t);
                return null;
            }
        }
    }
}
