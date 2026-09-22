package com.alphabubble;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.Rect;
import android.graphics.RectF;
import android.net.Uri;
import android.util.Log;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.Toast;

// Batch 3: C1 kustom bubble, crop background. Semua via HelperGuard.
public final class BubbleStyle {
    private static final String TAG = "BubbleStyle";
    private static final String PREFS = "alpha_bubble";

    private static final String KEY_SCALE = "bubble_scale";
    private static final float SCALE_MIN = 0.6f;
    private static final float SCALE_MAX = 1.4f;
    private static final float SCALE_DEF = 1.0f;

    private BubbleStyle() {}

    public static void resetDefaults(Context c) {
        HelperGuard.run(c, "resetDef", () -> {
            try {
                c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .putFloat(KEY_SCALE, SCALE_DEF)
                        .apply();
            } catch (Throwable t) {
                Log.w(TAG, "resetDefaults gagal: " + t);
            }
        });
    }

    // C1: terapkan gaya dari prefs. Dipanggil di akhir applyLook().
    // service = BubbleService (punya field bg/root/params/wm via reflection-free?
    // Tidak — pakai view lookup: root FrameLayout child(0), bg ImageView child.
    public static void apply(Object svc) {
        HelperGuard.run(null, "style", () -> applyInner(svc));
    }

    private static void applyInner(Object svc) throws Throwable {
        if (!(svc instanceof android.content.Context)) return;
        Context c = (Context) svc;
        SharedPreferences sp = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (sp.getBoolean("helper_disabled", false)) return;
        float scale = sp.getFloat(KEY_SCALE, SCALE_DEF);
        if (scale < SCALE_MIN || scale > SCALE_MAX) scale = SCALE_DEF;
        try {
            java.lang.reflect.Field fRoot = svc.getClass().getDeclaredField("root");
            fRoot.setAccessible(true);
            FrameLayout root = (FrameLayout) fRoot.get(svc);
            java.lang.reflect.Field fBg = svc.getClass().getDeclaredField("bg");
            fBg.setAccessible(true);
            ImageView bg = (ImageView) fBg.get(svc);
            java.lang.reflect.Field fParams = svc.getClass().getDeclaredField("params");
            fParams.setAccessible(true);
            WindowManager.LayoutParams params =
                    (WindowManager.LayoutParams) fParams.get(svc);
            if (root == null || bg == null || params == null) return;
            // JANGAN paksa width==height: LayoutParams asli WRAP_CONTENT.
            // Skala proporsional via setScaleX/Y supaya isi ikut, tidak terpotong.
            try {
                root.setScaleX(scale);
                root.setScaleY(scale);
            } catch (Throwable t) {
                Log.w(TAG, "apply: scale gagal: " + t);
            }
            try {
                java.lang.reflect.Field fWm = svc.getClass().getDeclaredField("wm");
                fWm.setAccessible(true);
                WindowManager wm = (WindowManager) fWm.get(svc);
                if (wm != null) {
                    try { wm.updateViewLayout(root, params); }
                    catch (Throwable t) { Log.w(TAG, "apply: updateLayout gagal: " + t); }
                }
            } catch (Throwable t) {
                Log.w(TAG, "apply: wm gagal: " + t);
            }
            // alpha + corner diabaikan (bawaan sistem). Hanya skala yang diterapkan.
        } catch (Throwable t) {
            Log.w(TAG, "apply gagal: " + t);
        }
    }

    // Mode crop: Fill = isi penuh (crop tengah sesuai rasio layar), Fit = tampil utuh tanpa terpotong (letterbox bila perlu).
    public enum CropMode { FILL, FIT }

    /** Crop bitmap dari URI mengikuti rasio layar device (bukan paksa 1:1).
     *  @param mode FILL = crop tengah mengisi penuh, FIT = tampil utuh (letterbox).
     *  @param outWidth lebar output target (biasanya widthPixels layar).
     *  @param outHeight tinggi output target (biasanya heightPixels layar). */
    public static Bitmap cropRatio(Context c, Uri uri, CropMode mode, int outWidth, int outHeight) {
        final Bitmap[] out = {null};
        HelperGuard.run(c, "cropRatio", () -> {
            try {
                Bitmap src = BitmapFactory.decodeStream(
                        c.getContentResolver().openInputStream(uri));
                if (src == null) {
                    Log.w(TAG, "cropRatio: decode null");
                    return;
                }
                int sw = src.getWidth(), sh = src.getHeight();
                if (sw <= 0 || sh <= 0) {
                    Log.w(TAG, "cropRatio: src size invalid " + sw + "x" + sh);
                    return;
                }
                // Rasio layar device — berlapis: Activity decorView -> WindowManager -> Resources.getSystem()
                android.util.DisplayMetrics dm = null;
                int dw = 0, dh = 0;
                boolean gotMetrics = false;
                // 1) Coba dari Activity yang sedang tampil (decorView)
                if (c instanceof Activity) {
                    try {
                        Activity act = (Activity) c;
                        android.view.View decor = act.getWindow().getDecorView();
                        if (decor != null) {
                            dm = new android.util.DisplayMetrics();
                            decor.getDisplay().getRealMetrics(dm);
                            dw = dm.widthPixels;
                            dh = dm.heightPixels;
                            if (dw > 0 && dh > 0) gotMetrics = true;
                        }
                    } catch (Throwable t) {
                        Log.w(TAG, "cropRatio: decorView metrics gagal: " + t);
                    }
                }
                // 2) Coba WindowManager defaultDisplay
                if (!gotMetrics) {
                    try {
                        WindowManager wm = (WindowManager) c.getSystemService(Context.WINDOW_SERVICE);
                        if (wm != null) {
                            dm = new android.util.DisplayMetrics();
                            wm.getDefaultDisplay().getMetrics(dm);
                            dw = dm.widthPixels;
                            dh = dm.heightPixels;
                            if (dw > 0 && dh > 0) gotMetrics = true;
                        }
                    } catch (Throwable t) {
                        Log.w(TAG, "cropRatio: WindowManager metrics gagal: " + t);
                    }
                }
                // 3) Coba Resources context
                if (!gotMetrics) {
                    try {
                        dm = c.getResources().getDisplayMetrics();
                        dw = dm.widthPixels;
                        dh = dm.heightPixels;
                        if (dw > 0 && dh > 0) gotMetrics = true;
                    } catch (Throwable t) {
                        Log.w(TAG, "cropRatio: Resources metrics gagal: " + t);
                    }
                }
                // 4) Cadangan terakhir: Resources.getSystem() — rasio device sebenarnya
                if (!gotMetrics) {
                    try {
                        dm = android.content.res.Resources.getSystem().getDisplayMetrics();
                        dw = dm.widthPixels;
                        dh = dm.heightPixels;
                        if (dw > 0 && dh > 0) {
                            gotMetrics = true;
                            Log.w(TAG, "cropRatio: metrics ctx 0, pakai system " + dw + "x" + dh);
                        }
                    } catch (Throwable t) {
                        Log.w(TAG, "cropRatio: system metrics gagal: " + t);
                    }
                }
                // 5) Total gagal: pakai outWidth/outHeight hanya sebagai ukuran OUTPUT (bukan rasio target)
                if (!gotMetrics) {
                    dw = outWidth > 0 ? outWidth : sw;
                    dh = outHeight > 0 ? outHeight : sh;
                    Log.w(TAG, "cropRatio: metrics TOTAL 0, output paksa " + dw + "x" + dh);
                    try {
                        android.widget.Toast.makeText(c, "Ukuran layar tak terbaca, pakai rasio sistem", android.widget.Toast.LENGTH_LONG).show();
                    } catch (Throwable t) {
                        Log.w(TAG, "cropRatio: toast gagal: " + t);
                    }
                }
                float targetRatio = (float) dw / dh;
                float srcRatio = (float) sw / sh;

                int cropW, cropH, cropX, cropY;
                if (mode == CropMode.FILL) {
                    // FILL: crop sumber agar rasio = targetRatio, lalu scale ke output penuh
                    if (srcRatio > targetRatio) {
                        // sumber lebih lebar -> crop lebar
                        cropH = sh;
                        cropW = Math.round(sh * targetRatio);
                    } else {
                        // sumber lebih tinggi -> crop tinggi
                        cropW = sw;
                        cropH = Math.round(sw / targetRatio);
                    }
                } else { // FIT
                    // FIT: gunakan seluruh sumber, nanti di-scale dengan letterbox
                    cropW = sw;
                    cropH = sh;
                }
                cropX = (sw - cropW) / 2;
                cropY = (sh - cropH) / 2;

                Bitmap cropped = Bitmap.createBitmap(src, cropX, cropY, cropW, cropH);
                // Scale ke output size (Fill = penuh, Fit = mempertahankan rasio dengan letterbox)
                Bitmap result;
                if (mode == CropMode.FILL) {
                    result = Bitmap.createScaledBitmap(cropped, outWidth > 0 ? outWidth : dw, outHeight > 0 ? outHeight : dh, true);
                } else {
                    // FIT: scale dengan mempertahankan rasio, letakkan di tengah canvas output
                    float scale = Math.min(
                            (float) (outWidth > 0 ? outWidth : dw) / cropW,
                            (float) (outHeight > 0 ? outHeight : dh) / cropH);
                    int dstW = Math.round(cropW * scale);
                    int dstH = Math.round(cropH * scale);
                    Bitmap scaled = Bitmap.createScaledBitmap(cropped, dstW, dstH, true);
                    result = Bitmap.createBitmap(outWidth > 0 ? outWidth : dw, outHeight > 0 ? outHeight : dh, Bitmap.Config.ARGB_8888);
                    android.graphics.Canvas cv = new android.graphics.Canvas(result);
                    cv.drawColor(0xFF000000); // hitam untuk letterbox
                    int dx = ((outWidth > 0 ? outWidth : dw) - dstW) / 2;
                    int dy = ((outHeight > 0 ? outHeight : dh) - dstH) / 2;
                    cv.drawBitmap(scaled, dx, dy, null);
                    if (scaled != cropped) { try { scaled.recycle(); } catch (Throwable t) {
                        Log.w(TAG, "cropRatio: recycle scaled gagal: " + t); } }
                }
                if (cropped != src) { try { src.recycle(); } catch (Throwable t) {
                    Log.w(TAG, "cropRatio: recycle src gagal: " + t); } }
                out[0] = result;
            } catch (Throwable t) {
                Log.w(TAG, "cropRatio gagal: " + t);
            }
        });
        return out[0];
    }

    /** Wrapper kompatibilitas: crop lama (dijalankan sebagai FILL dengan ukuran sama).
     *  @deprecated gunakan cropRatio dengan CropMode.FILL/FIT dan ukuran layar asli. */
    @Deprecated
    public static Bitmap cropSquare(Context c, Uri uri, int sizePx) {
        int w = sizePx, h = sizePx;
        return cropRatio(c, uri, CropMode.FILL, w, h);
    }

    // Simpan URI latar pilihan + minta service refresh.
    public static void pickBackground(Activity a, int requestCode) {
        HelperGuard.run(a, "pickBg", () -> {
            try {
                Intent i = new Intent(Intent.ACTION_PICK);
                i.setType("image/*");
                a.startActivityForResult(i, requestCode);
            } catch (Throwable t) {
                Log.w(TAG, "pickBg gagal: " + t);
            }
        });
    }
}
