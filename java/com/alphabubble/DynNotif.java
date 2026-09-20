package com.alphabubble;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

// Batch 3: notifikasi dinamis — judul = profil aktif + aksi Show/Hide +
// aksi Pengaturan. Aksi profil per-item DITUNDA (butuh handler onStartCommand,
// patch menengah — lihat PLAN). Dipanggil di akhir updateSelection() (p0 = service).
public final class DynNotif {
    private static final String TAG = "DynNotif";
    private static final int NID = 0x15;

    private DynNotif() {}

    public static void refresh(Object svc) {
        HelperGuard.run(null, "dynNotif", () -> refreshInner(svc));
    }

    private static void refreshInner(Object svc) throws Throwable {
        if (!(svc instanceof Context)) return;
        Context c = (Context) svc;
        String active;
        try {
            java.lang.reflect.Field f = svc.getClass().getDeclaredField("active");
            f.setAccessible(true);
            Object o = f.get(svc);
            active = o != null ? o.toString() : "?";
        } catch (Throwable t) {
            Log.w(TAG, "refresh: baca active gagal: " + t);
            return;
        }
        try {
            NotificationManager nm =
                    (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            if (Build.VERSION.SDK_INT >= 26) {
                try {
                    nm.createNotificationChannel(
                            new NotificationChannel("bubble", "Bubble",
                                    NotificationManager.IMPORTANCE_LOW));
                } catch (Throwable t) {
                    Log.w(TAG, "refresh: channel gagal: " + t);
                }
            }
            Notification.Builder b;
            if (Build.VERSION.SDK_INT >= 26) {
                b = new Notification.Builder(c, "bubble");
            } else {
                b = new Notification.Builder(c);
            }
            b.setContentTitle("Alpha: " + active);
            b.setContentText("Ketuk untuk sembunyikan/tampilkan");
            try {
                b.setSmallIcon(c.getResources().getIdentifier(
                        "ic_stat_alpha", "drawable", c.getPackageName()));
            } catch (Throwable t) {
                Log.w(TAG, "refresh: icon gagal: " + t);
            }
            try {
                Intent t = new Intent(c, Class.forName("com.alphabubble.BubbleService"));
                t.setAction("com.alphabubble.BUBBLE_TOGGLE");
                PendingIntent pi = PendingIntent.getService(c, 0, t,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                b.addAction(0, "Show/Hide", pi);
                b.setContentIntent(pi);
            } catch (Throwable t) {
                Log.w(TAG, "refresh: toggle gagal: " + t);
            }
            try {
                Intent s = new Intent(c, Class.forName("com.alphabubble.BubbleSettingsActivity"));
                PendingIntent pi = PendingIntent.getActivity(c, 1, s,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                b.addAction(0, "Pengaturan", pi);
            } catch (Throwable t) {
                Log.w(TAG, "refresh: pengaturan gagal: " + t);
            }
            Notification n = b.build();
            try {
                nm.notify(NID, n);
            } catch (Throwable t) {
                Log.w(TAG, "refresh: notify gagal: " + t);
            }
        } catch (Throwable t) {
            Log.w(TAG, "refresh gagal: " + t);
        }
    }
}
