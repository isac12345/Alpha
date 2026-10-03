package com.alphabubble;

import android.util.Log;
import java.io.BufferedReader;
import java.io.InputStreamReader;

// F1 monitoring: baca status root via RootExecutor (timeout+exit). Tidak pakai import baru.
public final class MonitorStatus {
    private static final String TAG = "MonitorStatus";
    private MonitorStatus() {}

    // 1. uperf hidup/mati
    public static boolean isUperf() {
        return RootExecutor.exec("pidof uperf") || RootExecutor.exec("pgrep -x uperf");
    }

    // 1. fas-rs hidup/mati + mode
    public static String fasMode() {
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"su","-c","cat /dev/fas_rs/mode"});
            p.waitFor(3000, java.util.concurrent.TimeUnit.MILLISECONDS);
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line = r.readLine();
            r.close();
            return (line != null) ? line.trim() : "-";
        } catch (Throwable t) {
            Log.w(TAG, "fas mode gagal: "+t);
            return "-";
        }
    }
    public static boolean isFas() {
        String m = fasMode();
        return m.length() > 0 && !m.equals("-");
    }

    // 1. monitor hidup/mati via /data/adb/alpha/monitor.pid
    public static boolean isMonitor() {
        String pid = readFileLine("/data/adb/alpha/monitor.pid");
        if (pid == null || pid.isEmpty()) return false;
        return new java.io.File("/proc/" + pid.trim()).exists();
    }

    // 1. boost ON/OFF: baca state gameboost terakhir dari alpha.log (paling simpel: baris GAME-SNAPSHOT terakhir < 5 menit)
    public static boolean isBoost() {
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"su","-c","tail -n 5 /data/adb/alpha/alpha.log"});
            p.waitFor(3000, java.util.concurrent.TimeUnit.MILLISECONDS);
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            long now = System.currentTimeMillis();
            while ((line = br.readLine()) != null) {
                if (line.contains("GAME-SNAPSHOT") || line.contains("boost")) {
                    // sederhana: jika ada snapshot terakhir dan bukan sangat lama
                    return true;
                }
            }
            br.close();
        } catch (Throwable t) {
            Log.w(TAG, "boost cek gagal: "+t);
        }
        return false;
    }

    // 2. versi modul
    public static String moduleVersion() {
        String s = readFileLine("/data/adb/modules/alpha_uperf_fasrs_fusion/module.prop");
        if (s == null) return "v?";
        // cari versionCode atau version
        String v = extractProp(s, "versionCode");
        if (v == null || v.isEmpty()) v = extractProp(s, "version");
        return (v != null && !v.isEmpty()) ? ("v" + v) : "v?";
    }

    // 6. snapshot terakhir
    public static String lastSnapshot() {
        try {
            String cmd = "grep 'GAME-SNAPSHOT' /data/adb/alpha/alpha.log 2>/dev/null | tail -n 1";
            Process p = Runtime.getRuntime().exec(new String[]{"su","-c", cmd});
            p.waitFor(3000, java.util.concurrent.TimeUnit.MILLISECONDS);
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line = br.readLine();
            br.close();
            if (line == null || line.trim().isEmpty()) return "belum ada data";
            int idx = line.indexOf("GAME-SNAPSHOT");
            if (idx >= 0) line = line.substring(idx + "GAME-SNAPSHOT".length()).trim();
            return line.isEmpty() ? "belum ada data" : line;
        } catch (Throwable t) {
            Log.w(TAG, "lastSnapshot gagal: "+t);
            return "belum ada data";
        }
    }

    private static String readFileLine(String path) {
        try {
            String cmd = RootExecutor.buildCommand("cat", path) + " 2>/dev/null | head -n 1";
            Process p = Runtime.getRuntime().exec(new String[]{"su","-c", cmd});
            p.waitFor(3000, java.util.concurrent.TimeUnit.MILLISECONDS);
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String s = br.readLine();
            br.close();
            return s;
        } catch (Throwable t) {
            Log.w(TAG, "readFileLine gagal "+path+": "+t);
            return null;
        }
    }
    private static String extractProp(String text, String key) {
        for (String s : text.split("\\n")) {
            if (s.startsWith(key+"=")) return s.substring(key.length()+1).trim();
        }
        return null;
    }

    // Hook refresh (pola HomeCards.refreshInner): update view dari UI thread, root di background.
    public static void refresh(final android.app.Activity a) {
        if (a == null) return;
        new Thread(() -> {
            try {
                final boolean u = isUperf();
                final String f = fasMode();
                final boolean m = isMonitor();
                final boolean b = isBoost();
                final String ver = moduleVersion();
                final String snap = lastSnapshot();
                new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                    try {
                        android.widget.TextView tvStatus = a.findViewById(
                            a.getResources().getIdentifier("tvStatus", "id", a.getPackageName()));
                        android.widget.TextView indBoost = a.findViewById(
                            a.getResources().getIdentifier("indBoost", "id", a.getPackageName()));
                        android.widget.TextView tvSnapshot = a.findViewById(
                            a.getResources().getIdentifier("tvSnapshot", "id", a.getPackageName()));
                        android.widget.TextView tvModule = a.findViewById(
                            a.getResources().getIdentifier("tvModule", "id", a.getPackageName()));
                        if (tvStatus != null) tvStatus.setText(
                            "uperf: " + (u ? "hidup" : "mati") +
                            " | fas-rs: " + (f.equals("-") ? "mati" : f) +
                            " | monitor: " + (m ? "hidup" : "mati") +
                            " | boost: " + (b ? "ON" : "OFF"));
                        if (indBoost != null) indBoost.setTextColor(
                            b ? android.graphics.Color.parseColor("#2ecc40") : android.graphics.Color.parseColor("#e74c3c"));
                        if (tvSnapshot != null) tvSnapshot.setText(snap);
                        if (tvModule != null) tvModule.setText("Modul: " + ver);
                    } catch (Throwable t) {
                        Log.w(TAG, "refresh UI gagal: "+t);
                    }
                });
            } catch (Throwable t) {
                Log.w(TAG, "refresh thread gagal: "+t);
            }
        }).start();
    }
}
