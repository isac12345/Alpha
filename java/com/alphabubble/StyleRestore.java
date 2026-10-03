package com.alphabubble;

import android.app.Activity;
import android.util.Log;
import android.view.View;

// Kembalikan gaya tombol bawaan APK yang hilang saat overlay layout dihapus.
// Dulu gaya ini tertulis inline di activity_main.xml overlay (sekarang dibuang
// agar layout 4-page asli utuh). Daftar = salinan persis pasangan id->drawable
// dari overlay lama. Hanya tombol STATIS (tidak diubah smali saat runtime).
// Resolve via getIdentifier (tanpa R, pola CardAlpha/HomeCards). Aman: skip bila 0.
public final class StyleRestore {
    private static final String TAG = "StyleRestore";
    private StyleRestore() {}

    // {id, drawable}
    private static final String[][] MAP = {
        {"btnApplyResolution", "pill_outline"},
        {"btnResetResolution", "pill_outline"},
        {"btnDexopt", "pill_outline"},
        {"btnAppBackground", "pill_outline"},
        {"btnAppBackgroundDefault", "pill_outline"},
        {"btnRedetect", "pill_outline"},
        {"btnLogAll", "pill_outline"},
        {"res60", "chip_res"},
        {"res70", "chip_res"},
        {"res80", "chip_res"},
        {"res90", "chip_res"},
        {"res100", "chip_res"},
    };

    public static void apply(Activity a) {
        if (a == null) return;
        try {
            String pkg = a.getPackageName();
            for (String[] m : MAP) {
                int vid = a.getResources().getIdentifier(m[0], "id", pkg);
                int did = a.getResources().getIdentifier(m[1], "drawable", pkg);
                if (vid == 0 || did == 0) continue;
                View v = a.findViewById(vid);
                if (v != null) v.setBackgroundResource(did);
            }
        } catch (Throwable t) { Log.w(TAG, "style gagal: " + t); }
    }
}
