package com.alphabubble;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.BitmapDrawable;
import android.net.Uri;
import android.os.Build;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.View;

import java.io.File;
import java.io.InputStream;

// b25: background custom full-height. applyAppBackground() asli set bitmap
// ke scrollRoot (ROOT ScrollView, sudah benar) tapi gravity CENTER (b11b)
// bikin bitmap tampil ukuran intrinsic di tengah -> area tak tertutup
// transparan dan tembus ke window background abu tema. Helper ini: pakai
// file crop tersimpan bila ada (else URI asli), scale FILL ke ukuran
// layar, gravity FILL, set ke scrollRoot DAN decorView (root window)
// agar full layar di Dashboard maupun Games (satu Activity, satu root).
public final class BgFull {
    private static final String TAG = "BgFull";
    private static final String PREFS = "alpha_bubble";

    private BgFull() {}

    public static void apply(Activity a) {
        HelperGuard.run(a, "bgFull", () -> applyInner(a));
    }

    private static void applyInner(Activity a) throws Throwable {
        if (a == null) return;
        SharedPreferences sp = a.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        Bitmap bmp = loadCrop(a, sp);
        if (bmp == null) bmp = loadUri(a, sp);
        if (bmp == null) return; // tanpa gambar: fallback warna asli tetap jalan
        int[] wh = screenSize(a);
        int dw = wh != null ? wh[0] : bmp.getWidth();
        int dh = wh != null ? wh[1] : bmp.getHeight();
        Bitmap full = scaleFill(bmp, dw, dh);
        if (full != bmp) {
            try { bmp.recycle(); } catch (Throwable t) { Log.w(TAG, "recycle: " + t); }
        }
        // Dua instance drawable (satu bitmap) agar callback/invalidate
        // tiap View independen; tanpa state sharing antar View.
        BitmapDrawable dwRoot = new BitmapDrawable(a.getResources(), full);
        dwRoot.setGravity(Gravity.FILL);
        BitmapDrawable dwDecor = new BitmapDrawable(a.getResources(), full);
        dwDecor.setGravity(Gravity.FILL);
        try {
            int id = a.getResources().getIdentifier("scrollRoot", "id", a.getPackageName());
            View root = id != 0 ? a.findViewById(id) : null;
            if (root != null) root.setBackground(dwRoot);
        } catch (Throwable t) {
            Log.w(TAG, "bg root gagal: " + t);
        }
        try {
            if (a.getWindow() != null && a.getWindow().getDecorView() != null) {
                a.getWindow().getDecorView().setBackground(dwDecor);
            }
        } catch (Throwable t) {
            Log.w(TAG, "bg decor gagal: " + t);
        }
    }

    // File crop dari BgEditor (app_bg_crop), bila ada dan valid.
    private static Bitmap loadCrop(Context c, SharedPreferences sp) {
        try {
            String u = sp.getString("app_bg_crop", null);
            if (u == null) return null;
            String path = Uri.parse(u).getPath();
            if (path == null) return null;
            Bitmap bmp = BitmapFactory.decodeFile(new File(path).getAbsolutePath());
            if (bmp == null) Log.w(TAG, "crop decode null");
            return bmp;
        } catch (Throwable t) {
            Log.w(TAG, "loadCrop gagal: " + t);
            return null;
        }
    }

    // URI galeri asli, decode hemat memori (inSampleSize, pola openEditor).
    private static Bitmap loadUri(Context c, SharedPreferences sp) {
        try {
            String s = sp.getString("app_bg_uri", null);
            if (s == null) return null;
            Uri uri = Uri.parse(s);
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inJustDecodeBounds = true;
            InputStream is = c.getContentResolver().openInputStream(uri);
            if (is == null) return null;
            try { BitmapFactory.decodeStream(is, null, o); } finally {
                try { is.close(); } catch (Throwable t) { Log.w(TAG, "close: " + t); }
            }
            if (o.outWidth <= 0 || o.outHeight <= 0) return null;
            int sample = 1;
            while (Math.max(o.outWidth, o.outHeight) / sample > 1600) sample *= 2;
            BitmapFactory.Options o2 = new BitmapFactory.Options();
            o2.inSampleSize = sample;
            InputStream is2 = c.getContentResolver().openInputStream(uri);
            if (is2 == null) return null;
            try { return BitmapFactory.decodeStream(is2, null, o2); } finally {
                try { is2.close(); } catch (Throwable t) { Log.w(TAG, "close: " + t); }
            }
        } catch (Throwable t) {
            Log.w(TAG, "loadUri gagal: " + t);
            return null;
        }
    }

    // Ukuran layar: API30+ window metrics -> decorView realMetrics -> system.
    // null = tak terbaca (caller pakai ukuran bitmap; FILL tetap cover).
    private static int[] screenSize(Activity a) {
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                android.graphics.Rect b = a.getWindowManager()
                        .getCurrentWindowMetrics().getBounds();
                if (b.width() > 0 && b.height() > 0) {
                    return new int[]{b.width(), b.height()};
                }
            } catch (Throwable t) {
                Log.w(TAG, "windowMetrics gagal: " + t);
            }
        }
        try {
            View decor = a.getWindow() != null ? a.getWindow().getDecorView() : null;
            if (decor != null) {
                DisplayMetrics dm = new DisplayMetrics();
                decor.getDisplay().getRealMetrics(dm);
                if (dm.widthPixels > 0 && dm.heightPixels > 0) {
                    return new int[]{dm.widthPixels, dm.heightPixels};
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "realMetrics gagal: " + t);
        }
        try {
            DisplayMetrics dm = android.content.res.Resources.getSystem().getDisplayMetrics();
            if (dm.widthPixels > 0 && dm.heightPixels > 0) {
                return new int[]{dm.widthPixels, dm.heightPixels};
            }
        } catch (Throwable t) {
            Log.w(TAG, "system metrics gagal: " + t);
        }
        return null;
    }

    // Scale proporsional isi penuh (FILL): crop tengah + scale ke dw x dh.
    private static Bitmap scaleFill(Bitmap src, int dw, int dh) {
        try {
            if (dw <= 0 || dh <= 0) return src;
            int sw = src.getWidth(), sh = src.getHeight();
            if (sw <= 0 || sh <= 0) return src;
            if (sw == dw && sh == dh) return src;
            float target = (float) dw / dh;
            float ratio = (float) sw / sh;
            int cw, ch;
            if (ratio > target) { ch = sh; cw = Math.round(sh * target); }
            else { cw = sw; ch = Math.round(sw / target); }
            if (cw <= 0 || ch <= 0) return src;
            int cx = (sw - cw) / 2, cy = (sh - ch) / 2;
            Bitmap cropped = Bitmap.createBitmap(src, cx, cy, cw, ch);
            Bitmap out = Bitmap.createScaledBitmap(cropped, dw, dh, true);
            if (cropped != src) {
                try { cropped.recycle(); } catch (Throwable t) { Log.w(TAG, "recycle: " + t); }
            }
            return out;
        } catch (Throwable t) {
            Log.w(TAG, "scaleFill gagal: " + t);
            return src;
        }
    }
}
