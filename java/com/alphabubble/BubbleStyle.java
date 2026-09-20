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

    private BubbleStyle() {}

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
        float scale = sp.getFloat("bubble_scale", 1.0f);
        int alpha = sp.getInt("bubble_alpha", 255);
        int corner = sp.getInt("bubble_corner", 31);
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
            float d = c.getResources().getDisplayMetrics().density;
            int base = (int) (62 * d + 0.5f);
            int size = Math.max(32, (int) (base * scale));
            params.width = size;
            params.height = size;
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
            bg.setImageAlpha(alpha);
            try {
                bg.setClipToOutline(corner >= 31);
            } catch (Throwable t) {
                Log.w(TAG, "apply: clip gagal: " + t);
            }
        } catch (Throwable t) {
            Log.w(TAG, "apply gagal: " + t);
        }
    }

    // Crop: center-crop bitmap dari galeri ke persegi + simpan preferensi URI.
    public static Bitmap cropSquare(Context c, Uri uri, int sizePx) {
        final Bitmap[] out = {null};
        HelperGuard.run(c, "crop", () -> {
            try {
                Bitmap src = BitmapFactory.decodeStream(
                        c.getContentResolver().openInputStream(uri));
                if (src == null) {
                    Log.w(TAG, "crop: decode null");
                    return;
                }
                int w = src.getWidth(), h = src.getHeight();
                int side = Math.min(w, h);
                int x = (w - side) / 2, y = (h - side) / 2;
                Bitmap sq = Bitmap.createBitmap(src, x, y, side, side);
                out[0] = Bitmap.createScaledBitmap(sq, sizePx, sizePx, true);
                if (sq != src) { try { src.recycle(); } catch (Throwable t) {
                    Log.w(TAG, "crop: recycle gagal: " + t); } }
            } catch (Throwable t) {
                Log.w(TAG, "crop gagal: " + t);
            }
        });
        return out[0];
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
