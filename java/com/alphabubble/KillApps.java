package com.alphabubble;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.util.Log;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

// Tutup SEMUA aplikasi pihak-ketiga yang berjalan (dipakai sesudah ganti
// render backend agar render baru berlaku tanpa reboot). System app +
// APK sendiri dilewati. Jalan di thread latar (force-stop massal bisa
// belasan detik); hasil via Toast + Log. Tiap perintah su: timeout,
// cek exit code, tanpa input user (nama paket dari PackageManager).
public final class KillApps {
    private static final String TAG = "KillApps";

    private KillApps() {}

    public static void killAll(final Activity a) {
        HelperGuard.run(a, "killAll", () -> {
            Toast.makeText(a, "Menutup aplikasi berjalan…", Toast.LENGTH_SHORT).show();
            new Thread(() -> {
                try {
                    List<String> pkgs = runningThirdParty(a);
                    if (pkgs.size() < 2) pkgs = allThirdParty(a);
                    int ok = 0;
                    for (String p : pkgs) {
                        if (runSu("am force-stop " + p, 8)) ok++;
                    }
                    final int done = ok, total = pkgs.size();
                    Log.w(TAG, "killAll: " + done + "/" + total);
                    try {
                        a.runOnUiThread(() -> {
                            try {
                                Toast.makeText(a,
                                        "Ditutup " + done + "/" + total + " aplikasi",
                                        Toast.LENGTH_LONG).show();
                            } catch (Throwable t) {
                                Log.w(TAG, "toast gagal: " + t);
                            }
                        });
                    } catch (Throwable t) {
                        Log.w(TAG, "ui gagal: " + t);
                    }
                } catch (Throwable t) {
                    Log.w(TAG, "killAll gagal: " + t);
                }
            }).start();
        });
    }

    private static List<String> runningThirdParty(Context c) {
        List<String> out = new ArrayList<>();
        try {
            ActivityManager am = (ActivityManager) c.getSystemService(Context.ACTIVITY_SERVICE);
            if (am == null) return out;
            String self = c.getPackageName();
            for (ActivityManager.RunningAppProcessInfo p : am.getRunningAppProcesses()) {
                if (p == null || p.pkgList == null) continue;
                for (String pkg : p.pkgList) {
                    if (pkg == null || pkg.equals(self) || out.contains(pkg)) continue;
                    if (isThirdParty(c, pkg)) out.add(pkg);
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "running gagal: " + t);
        }
        return out;
    }

    private static List<String> allThirdParty(Context c) {
        List<String> out = new ArrayList<>();
        try {
            PackageManager pm = c.getPackageManager();
            String self = c.getPackageName();
            for (ApplicationInfo ai : pm.getInstalledApplications(0)) {
                if (ai == null || ai.packageName == null) continue;
                if (ai.packageName.equals(self)) continue;
                if ((ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0) continue;
                out.add(ai.packageName);
            }
        } catch (Throwable t) {
            Log.w(TAG, "list gagal: " + t);
        }
        return out;
    }

    private static boolean isThirdParty(Context c, String pkg) {
        try {
            ApplicationInfo ai = c.getPackageManager().getApplicationInfo(pkg, 0);
            return ai != null && (ai.flags & ApplicationInfo.FLAG_SYSTEM) == 0;
        } catch (Throwable t) {
            return false;
        }
    }

    // Jalankan perintah via su dengan timeout + cek exit code.
    private static boolean runSu(String cmd, long timeoutSec) {
        Process proc = null;
        try {
            proc = new ProcessBuilder("su", "-c", cmd).start();
            boolean done = proc.waitFor(timeoutSec, TimeUnit.SECONDS);
            if (!done) {
                try { proc.destroy(); } catch (Throwable t) {
                    Log.w(TAG, "destroy gagal: " + t);
                }
                return false;
            }
            return proc.exitValue() == 0;
        } catch (Throwable t) {
            Log.w(TAG, "su gagal: " + t);
            return false;
        } finally {
            if (proc != null) {
                try { proc.getInputStream().close(); } catch (Throwable t) {
                    Log.w(TAG, "close gagal: " + t);
                }
                try { proc.getErrorStream().close(); } catch (Throwable t) {
                    Log.w(TAG, "close gagal: " + t);
                }
            }
        }
    }
}
