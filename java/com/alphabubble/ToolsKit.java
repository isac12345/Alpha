package com.alphabubble;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.ProgressDialog;
import android.content.Context;
import android.os.CountDownTimer;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.Toast;

// Batch 2: C3 dexopt progres+hasil, C2 countdown revert.
// Render confirm DITUNDA (lihat PLAN). Semua entry via HelperGuard.
// CATATAN: hook smali mewarisi register bertipe Context (check-cast),
// jadi signature publik memakai Context + cast aman ke Activity di dalam.
// Semua sentuh UI dipost ke main looper (hook jalan di worker thread).
public final class ToolsKit {
    private static final String TAG = "ToolsKit";
    private static ProgressDialog prog;
    private static long t0;

    private ToolsKit() {}

    private static Activity asActivity(Context c) throws Throwable {
        if (!(c instanceof Activity)) {
            throw new IllegalStateException("context bukan Activity");
        }
        return (Activity) c;
    }

    private static void main(Runnable r) {
        try {
            new Handler(Looper.getMainLooper()).post(() -> {
                try {
                    r.run();
                } catch (Throwable t) {
                    Log.w(TAG, "main gagal: " + t);
                }
            });
        } catch (Throwable t) {
            Log.w(TAG, "main post gagal: " + t);
        }
    }

    // C3a: dexopt mulai (hook tombol Dexopt). Progres + catat waktu.
    public static void dexoptStart(Activity a) {
        HelperGuard.run(a, "dexoptStart", () -> {
            t0 = System.currentTimeMillis();
            try {
                if (prog != null) {
                    try { prog.dismiss(); } catch (Throwable t) {
                        Log.w(TAG, "dexoptStart: dismiss lama gagal: " + t);
                    }
                }
                prog = new ProgressDialog(a);
                prog.setTitle("Dexopt");
                prog.setMessage("Mengompilasi...");
                prog.setCancelable(false);
                prog.show();
            } catch (Throwable t) {
                Log.w(TAG, "dexoptStart: show gagal: " + t);
            }
        });
    }

    // C3b: dexopt selesai (hook Toast hasil, v1=Context). Tutup progres, dialog hasil.
    public static void dexoptDone(Context c, CharSequence result) {
        final String res = result != null ? result.toString() : "-";
        HelperGuard.run(c, "dexoptDone", () -> {
            final long ms = System.currentTimeMillis() - t0;
            try {
                if (prog != null) {
                    try { prog.dismiss(); } catch (Throwable t) {
                        Log.w(TAG, "dexoptDone: dismiss gagal: " + t);
                    }
                    prog = null;
                }
            } catch (Throwable t) {
                Log.w(TAG, "dexoptDone: prog gagal: " + t);
            }
            final Activity a = asActivity(c);
            final boolean ok = res.startsWith("Compile selesai:");
            final String mode = ok ? res.replaceFirst(".*:\\s*", "") : "?";
            final String after = compileStatus(ok, mode);
            main(() -> {
                try {
                    AlertDialog d = new AlertDialog.Builder(a)
                            .setTitle("Hasil dexopt")
                            .setMessage(res + "\nDurasi: " + (ms / 1000.0) + " dtk\nStatus: " + after)
                            .setPositiveButton("OK", null)
                            .show();
                    styleDialog(d);
                } catch (Throwable t) {
                    Log.w(TAG, "dexoptDone: dialog gagal: " + t);
                }
            });
        });
    }

    private static void styleDialog(AlertDialog d) {
        try {
            if (d == null || d.getWindow() == null) return;
            android.graphics.drawable.GradientDrawable gd =
                    new android.graphics.drawable.GradientDrawable();
            gd.setColor(android.graphics.Color.parseColor("#1e1e1e"));
            gd.setCornerRadius(24);
            d.getWindow().setBackgroundDrawable(gd);
        } catch (Throwable t) {
            Log.w(TAG, "styleDialog gagal: " + t);
        }
    }

    // C2: setelah APPLY RES sukses (hook Toast hasil, v1=Context).
    // Countdown 15 dtk, revert bila tak konfirmasi.
    public static void confirmKeep(Context c) {
        HelperGuard.run(c, "confirmKeep", () -> {
            final Activity a = asActivity(c);
            final CountDownTimer[] timer = new CountDownTimer[1];
            try {
                AlertDialog d = new AlertDialog.Builder(a)
                        .setTitle("Pertahankan resolusi?")
                        .setMessage("Resolusi baru diterapkan.\n\nKembali otomatis dalam 15 detik bila tidak dikonfirmasi.")
                        .setPositiveButton("Pertahankan", (di, w) -> {
                            try { timer[0].cancel(); } catch (Throwable t) {
                                Log.w(TAG, "confirmKeep: cancel gagal: " + t);
                            }
                        })
                        .setNegativeButton("Kembalikan", (di, w) -> {
                            try { timer[0].cancel(); } catch (Throwable t) {
                                Log.w(TAG, "confirmKeep: cancel gagal: " + t);
                            }
                            revert(a);
                        })
                        .setCancelable(false)
                        .show();
                styleDialog(d);
                timer[0] = new CountDownTimer(15000, 1000) {
                    @Override
                    public void onTick(long left) {
                        try {
                            d.setMessage("Resolusi baru diterapkan.\n\nKembali otomatis dalam "
                                    + (left / 1000) + " detik bila tidak dikonfirmasi.");
                        } catch (Throwable t) {
                            Log.w(TAG, "confirmKeep: tick gagal: " + t);
                        }
                    }

                    @Override
                    public void onFinish() {
                        try { d.dismiss(); } catch (Throwable t) {
                            Log.w(TAG, "confirmKeep: dismiss gagal: " + t);
                        }
                        revert(a);
                    }
                };
                timer[0].start();
            } catch (Throwable t) {
                Log.w(TAG, "confirmKeep: dialog gagal: " + t);
            }
        });
    }

    // Render confirm DITUNDA (Batch 2): applyRender() private tak bisa dipanggil
    // balik dari Java tanpa reflection rapuh. Lihat PLAN Batch 2.

    private static void revert(final Activity a) {
        HelperGuard.run(a, "revert", () -> {
            try {
                Process p = Runtime.getRuntime().exec(
                        new String[]{"su", "-c", "wm size reset; wm density reset"});
                p.waitFor();
                Toast.makeText(a, "Resolusi dikembalikan", Toast.LENGTH_LONG).show();
            } catch (Throwable t) {
                Log.w(TAG, "revert gagal: " + t);
            }
        });
    }


    // Android 14 tak punya query status compile bawaan (get-compile-mode =
    // "Unknown command"). Kembalikan mode yang diminta bila sukses, "?" bila gagal.
    private static String compileStatus(boolean ok, String mode) {
        return ok ? mode : "?";
    }

    private static String compileStatus() {
        return "?";
    }

    public static void toast(Context c, String msg) {
        try {
            Toast.makeText(c, msg, Toast.LENGTH_LONG).show();
        } catch (Throwable t) {
            Log.w(TAG, "toast gagal: " + t);
        }
    }
}
