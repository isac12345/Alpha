package com.alphabubble;

import android.Manifest;
import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CompoundButton;
import android.widget.LinearLayout;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

// Batch 1: kartu BUBBLE di Home + onboarding izin + guard Battery Lab.
// Semua entry lewat HelperGuard (kill-switch + Throwable). Dipanggil dari
// MainActivity.onCreate (attach) dan onResume (refresh), 1 baris tiap hook.
public final class HomeCards {
    private static final String TAG = "HomeCards";
    private static final String PREFS = "alpha_bubble";
    private static final String KEY_HIDDEN = "hidden";
    private static final String KEY_ONBOARD = "onboard_done";
    private static final int CARD_ID = 0x00B0BB1E;

    private HomeCards() {}

    public static void attach(Activity a) {
        HelperGuard.run(a, "attach", () -> attachInner(a));
    }

    public static void refresh(Activity a) {
        HelperGuard.run(a, "refresh", () -> refreshInner(a));
    }

    public static void maybeOnboard(Activity a) {
        HelperGuard.run(a, "onboard", () -> onboardInner(a));
    }

    public static boolean guardBatteryLab(View v) {
        final boolean[] ok = {false};
        HelperGuard.run(v != null ? v.getContext() : null, "guardBL", () -> {
            ok[0] = guardInner(v);
        });
        return ok[0];
    }

    private static void attachInner(Activity a) throws Throwable {
        View content = a.findViewById(android.R.id.content);
        if (!(content instanceof ViewGroup)) {
            Log.w(TAG, "attach: content bukan ViewGroup");
            return;
        }
        ViewGroup container = findContainer((ViewGroup) content);
        if (container == null) {
            Log.w(TAG, "attach: container LinearLayout tidak ketemu");
            return;
        }
        if (container.findViewById(CARD_ID) != null) {
            return;
        }
        LinearLayout card = buildCard(a);
        int idx = Math.min(2, container.getChildCount());
        container.addView(card, idx);
        // Kartu injeksi muncul belakangan (tak kena pressAll NavTabs.attach).
        UiAnim.pressAll(a, card);
    }

    private static ViewGroup findContainer(ViewGroup g) throws Throwable {
        for (int i = 0; i < g.getChildCount(); i++) {
            View c = g.getChildAt(i);
            if (c instanceof LinearLayout) {
                LinearLayout ll = (LinearLayout) c;
                if (ll.getOrientation() == LinearLayout.VERTICAL && ll.getChildCount() > 2) {
                    return ll;
                }
            }
            if (c instanceof ViewGroup) {
                ViewGroup found = findContainer((ViewGroup) c);
                if (found != null) return found;
            }
        }
        return null;
    }

    private static void refreshInner(Activity a) throws Throwable {
        View card = a.findViewById(CARD_ID);
        if (card == null || !(card instanceof ViewGroup)) return;
        ViewGroup g = (ViewGroup) card;
        Switch sw = (Switch) g.findViewById(CARD_ID + 1);
        TextView tvOv = (TextView) g.findViewById(CARD_ID + 2);
        TextView tvNt = (TextView) g.findViewById(CARD_ID + 3);
        Button bOv = (Button) g.findViewById(CARD_ID + 4);
        Button bNt = (Button) g.findViewById(CARD_ID + 5);
        boolean ov = Settings.canDrawOverlays(a);
        boolean nt = notifOn(a);
        boolean hidden = a.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_HIDDEN, false);
        sw.setOnCheckedChangeListener(null);
        sw.setChecked(!hidden);
        sw.setOnCheckedChangeListener((bv, show) -> applyShow(a, show));
        tvOv.setText(ov ? "Izin overlay: aktif" : "Izin overlay: belum");
        tvNt.setText(nt ? "Notifikasi: aktif" : "Notifikasi: belum");
        bOv.setVisibility(ov ? View.GONE : View.VISIBLE);
        bNt.setVisibility(nt ? View.GONE : View.VISIBLE);
        guardBatteryLab(a);
    }

    private static void guardBatteryLab(Activity a) throws Throwable {
        int id = a.getResources().getIdentifier("btnBatteryLab", "id", a.getPackageName());
        if (id == 0) return;
        View v = a.findViewById(id);
        if (v == null) return;
        guardBatteryLab(v);
    }

    private static void onboardInner(Activity a) throws Throwable {
        SharedPreferences sp = a.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (sp.getBoolean(KEY_ONBOARD, false)) return;
        boolean ov = Settings.canDrawOverlays(a);
        boolean nt = notifOn(a);
        if (ov && nt) {
            sp.edit().putBoolean(KEY_ONBOARD, true).apply();
            return;
        }
        new AlertDialog.Builder(a)
                .setTitle("Izin Bubble")
                .setMessage("Bubble butuh izin tampil di atas aplikasi dan notifikasi agar tetap hidup. Berikan sekarang?")
                .setPositiveButton("Lanjut", (d, w) -> {
                    HelperGuard.run(a, "onboardGo", () -> {
                        if (!Settings.canDrawOverlays(a)) {
                            a.startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:" + a.getPackageName())));
                        } else if (!notifOn(a)) {
                            requestNotif(a);
                        }
                    });
                })
                .setNegativeButton("Nanti saja", (d, w) -> {
                    HelperGuard.run(a, "onboardLater", () -> {
                        sp.edit().putBoolean(KEY_ONBOARD, true).apply();
                    });
                })
                .setCancelable(false)
                .show();
    }

    private static boolean guardInner(View v) throws Throwable {
        if (v == null) return false;
        Context c = v.getContext();
        Intent i = new Intent(Intent.ACTION_MAIN);
        i.setClassName("com.transsion.batterylab", "com.transsion.batterylab.BatteryLabHomeActivity");
        boolean ok = i.resolveActivity(c.getPackageManager()) != null;
        v.setEnabled(ok);
        v.setAlpha(ok ? 1.0f : 0.4f);
        return ok;
    }

    private static void applyShow(Activity a, boolean show) {
        HelperGuard.run(a, "applyShow", () -> {
            SharedPreferences sp = a.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            boolean cur = sp.getBoolean(KEY_HIDDEN, false);
            boolean want = !show;
            if (cur == want) return;
            if (show && !Settings.canDrawOverlays(a)) {
                Toast.makeText(a, "Berikan izin overlay dulu", Toast.LENGTH_LONG).show();
                a.startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:" + a.getPackageName())));
                refresh(a);
                return;
            }
            if (isRunning(a)) {
                Intent t = new Intent(a, Class.forName("com.alphabubble.BubbleService"));
                t.setAction("com.alphabubble.BUBBLE_TOGGLE");
                a.startForegroundService(t);
            } else {
                sp.edit().putBoolean(KEY_HIDDEN, want).apply();
                a.startForegroundService(new Intent(a, Class.forName("com.alphabubble.BubbleService")));
            }
        });
    }

    private static boolean notifOn(Activity a) throws Throwable {
        if (Build.VERSION.SDK_INT < 33) return true;
        return a.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED;
    }

    private static void requestNotif(Activity a) throws Throwable {
        if (Build.VERSION.SDK_INT >= 33
                && a.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
            a.requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 7001);
        } else if (Build.VERSION.SDK_INT >= 33) {
            boolean asked = a.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getBoolean("notif_asked", false);
            if (!asked) {
                a.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .edit().putBoolean("notif_asked", true).apply();
                a.requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 7001);
            } else {
                Intent i = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS);
                i.putExtra(Settings.EXTRA_APP_PACKAGE, a.getPackageName());
                a.startActivity(i);
            }
        }
        a.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_ONBOARD, true).apply();
    }

    private static boolean isRunning(Activity a) throws Throwable {
        ActivityManager am = (ActivityManager) a.getSystemService(Context.ACTIVITY_SERVICE);
        if (am == null) return false;
        for (ActivityManager.RunningServiceInfo s : am.getRunningServices(64)) {
            if (s != null && s.service != null
                    && "com.alphabubble.BubbleService".equals(s.service.getClassName())) {
                return true;
            }
        }
        return false;
    }

    private static LinearLayout buildCard(final Activity a) throws Throwable {
        float d = a.getResources().getDisplayMetrics().density;
        int pad = (int) (12 * d + 0.5f);
        LinearLayout card = new LinearLayout(a);
        card.setId(CARD_ID);
        card.setOrientation(LinearLayout.VERTICAL);
        try {
            android.graphics.drawable.GradientDrawable gd =
                    new android.graphics.drawable.GradientDrawable();
            gd.setColor(Color.parseColor("#1e1e1e"));
            gd.setCornerRadius(12 * d);
            card.setBackground(gd);
        } catch (Throwable t) {
            Log.w(TAG, "card bg gagal: " + t);
            card.setBackgroundColor(Color.parseColor("#1e1e1e"));
        }
        card.setPadding(pad, pad, pad, pad);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = (int) (10 * d + 0.5f);
        lp.bottomMargin = (int) (10 * d + 0.5f);
        card.setLayoutParams(lp);

        TextView head = new TextView(a);
        head.setText("BUBBLE");
        head.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        head.setTextColor(Color.parseColor("#f4f2ee"));
        card.addView(head);

        TextView desc = new TextView(a);
        desc.setText("Akses cepat ganti profil.");
        desc.setTypeface(Typeface.MONOSPACE);
        desc.setTextColor(Color.parseColor("#87878a"));
        card.addView(desc);

        Switch sw = new Switch(a);
        sw.setId(CARD_ID + 1);
        sw.setText("Tampilkan bubble");
        sw.setTypeface(Typeface.MONOSPACE);
        sw.setTextColor(Color.parseColor("#f4f2ee"));
        card.addView(sw);

        TextView tvOv = new TextView(a);
        tvOv.setId(CARD_ID + 2);
        tvOv.setTypeface(Typeface.MONOSPACE);
        tvOv.setTextColor(Color.parseColor("#f4f2ee"));
        card.addView(tvOv);

        Button bOv = new Button(a);
        bOv.setId(CARD_ID + 4);
        bOv.setText("BERIKAN IZIN OVERLAY");
        bOv.setTypeface(Typeface.MONOSPACE);
        bOv.setOnClickListener(v -> HelperGuard.run(a, "giveOv", () -> {
            a.startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + a.getPackageName())));
        }));
        card.addView(bOv);

        TextView tvNt = new TextView(a);
        tvNt.setId(CARD_ID + 3);
        tvNt.setTypeface(Typeface.MONOSPACE);
        tvNt.setTextColor(Color.parseColor("#f4f2ee"));
        card.addView(tvNt);

        Button bNt = new Button(a);
        bNt.setId(CARD_ID + 5);
        bNt.setText("BERIKAN NOTIFIKASI");
        bNt.setTypeface(Typeface.MONOSPACE);
        bNt.setOnClickListener(v -> HelperGuard.run(a, "giveNt", () -> requestNotif(a)));
        card.addView(bNt);

        return card;
    }
}
