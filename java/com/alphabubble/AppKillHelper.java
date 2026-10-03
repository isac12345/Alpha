package com.alphabubble;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.util.Log;
import java.util.ArrayList;
import java.util.List;

// F3-22: tutup app lengkap (termasuk system) via root, blocklist kritis.
public final class AppKillHelper {
    private static final String TAG = "AppKillHelper";
    private static final String[] BLOCK = {"android", "system_server", "com.android.systemui"};
    private AppKillHelper() {}

    public static boolean isBlocked(String pkg) {
        for (String b : BLOCK) if (b.equals(pkg)) return true;
        return false;
    }

    // Daftar semua app (termasuk system) via PackageManager
    public static List<String> listAll(Activity a) {
        List<String> out = new ArrayList<>();
        try {
            PackageManager pm = a.getPackageManager();
            for (android.content.pm.ApplicationInfo info : pm.getInstalledApplications(0)) {
                out.add(info.packageName);
            }
        } catch (Throwable t) { Log.w(TAG, "listAll gagal: "+t); }
        return out;
    }

    // Kill via root am force-stop (lebih aman dari kill -9 untuk app non-sistem)
    public static boolean killApp(String pkg) {
        if (isBlocked(pkg)) return false;
        return RootExecutor.exec("am force-stop " + pkg);
    }
}
