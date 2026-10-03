package com.alphabubble;

import android.app.Activity;
import android.util.Log;
import android.widget.Toast;
import java.io.*;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

// F3-24: kirim log 1 ketuk (ambil 10 baris terakhir GAME-SNAPSHOT dari alpha.log, tulis /sdcard/alpha/)
public final class LogSender {
    private static final String TAG = "LogSender";
    private LogSender() {}

    public static void send(final Activity a) {
        new Thread(() -> {
            try {
                Process p = Runtime.getRuntime().exec(new String[]{"su","-c","grep 'GAME-SNAPSHOT' /data/adb/alpha/alpha.log 2>/dev/null | tail -n 10"});
                p.waitFor(3000, java.util.concurrent.TimeUnit.MILLISECONDS);
                BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = br.readLine()) != null) sb.append(line).append("\n");
                br.close();
                if (sb.length() == 0) sb.append("(log kosong / belum ada data)\n");
                String ts = new SimpleDateFormat("yyyyMMdd-HHmm", Locale.getDefault()).format(new Date());
                String outPath = "/sdcard/alpha/alpha-lapor-" + ts + ".txt";
                new File("/sdcard/alpha").mkdirs();
                FileWriter fw = new FileWriter(outPath);
                fw.write(sb.toString());
                fw.close();
                final String res = outPath;
                a.runOnUiThread(() -> {
                    try { Toast.makeText(a, "Log: " + res, Toast.LENGTH_LONG).show(); } catch (Throwable t) { Log.w(TAG, "toast gagal"); }
                });
            } catch (Throwable t) {
                Log.w(TAG, "send gagal: "+t);
                final String msg = "Gagal: "+t.getMessage();
                a.runOnUiThread(() -> { try { Toast.makeText(a, msg, Toast.LENGTH_SHORT).show(); } catch (Throwable t2) {} });
            }
        }).start();
    }
}
