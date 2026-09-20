package com.alphabubble;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.ProgressDialog;
import android.content.Context;
import android.os.CountDownTimer;
import android.util.Log;
import android.widget.Toast;

// Batch 2: C3 dexopt progres+hasil, C2 countdown revert.
// Render confirm DITUNDA (lihat PLAN). Semua entry via HelperGuard.
public final class ToolsKit {
    private static final String TAG = "ToolsKit";
    private static ProgressDialog prog;
    private static long t0;

    private ToolsKit() {}

    // C3a: dexopt mulai (hook tombol Dexopt). Progres + catat waktu + status awal.
    public static void dexoptStart(Activity a) {
        HelperGuard.run(a, "dexoptStart", () -> {
            t0 = System.currentTimeMillis();
            String before = compileStatus();
            try {
                if (prog != null) {
                    try { prog.dismiss(); } catch (Throwable t) {
                        Log.w(TAG, "dexoptStart: dismiss lama gagal: " + t);
                    }
                }
                prog = new ProgressDialog(a);
                prog.setTitle("Dexopt");
                prog.setMessage("Mengompilasi...\nStatus awal: " + before);
                prog.setCancelable(false);
                prog.show();
            } catch (Throwable t) {
                Log.w(TAG, "dexoptStart: show gagal: " + t);
            }
        });
    }

    // C3b: dexopt selesai (hook Toast hasil). Tutup progres, dialog hasil.
    public static void dexoptDone(Activity a, CharSequence result) {
        final String res = result != null ? result.toString() : "-";
        HelperGuard.run(a, "dexoptDone", () -> {
            long ms = System.currentTimeMillis() - t0;
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
            try {
                String after = compileStatus();
                new AlertDialog.Builder(a)
                        .setTitle("Hasil dexopt")
                        .setMessage(res + "\nDurasi: " + (ms / 1000.0) + " dtk\nStatus: " + after)
                        .setPositiveButton("OK", null)
                        .show();
            } catch (Throwable t) {
                Log.w(TAG, "dexoptDone: dialog gagal: " + t);
            }
        });
    }

    // C2: setelah APPLY RES sukses. Countdown 15 dtk, revert bila tak konfirmasi.
    public static void confirmKeep(Activity a) {
        HelperGuard.run(a, "confirmKeep", () -> {
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


    private static String compileStatus() {
        try {
            Process p = Runtime.getRuntime().exec(
                    new String[]{"su", "-c", "cmd package get-compile-mode com.alphabubble"});
            java.util.Scanner s = new java.util.Scanner(p.getInputStream()).useDelimiter("\\A");
            String out = s.hasNext() ? s.next().trim() : "?";
            p.waitFor();
            return out.isEmpty() ? "?" : out;
        } catch (Throwable t) {
            Log.w(TAG, "compileStatus gagal: " + t);
            return "?";
        }
    }

    public static void toast(Context c, String msg) {
        try {
            Toast.makeText(c, msg, Toast.LENGTH_LONG).show();
        } catch (Throwable t) {
            Log.w(TAG, "toast gagal: " + t);
        }
    }
}
