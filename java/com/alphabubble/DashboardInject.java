package com.alphabubble;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.util.Log;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

// Injeksi programatik F1-F4 ke content view (pola HomeCards.attach). Tidak pakai R.layout.activity_main.
public final class DashboardInject {
    private static final String TAG = "DashboardInject";
    private DashboardInject() {}

    public static void inject(Activity a) {
        if (a == null) return;
        // Cegah kartu ganda bila attach dipanggil ulang (mis. recreate ganti bahasa):
        // lewati hanya bila view kita masih nempel di activity INI.
        try { if (DashViews.tvStatus != null && DashViews.tvStatus.getParent() != null) return; } catch (Throwable t) { /* lanjut */ }
        try {
            ViewGroup root = (ViewGroup) a.findViewById(android.R.id.content);
            if (root == null) return;
            Context c = a;

            // Card STATUS + SNAPSHOT (F1)
            LinearLayout cardStatus = new LinearLayout(c);
            cardStatus.setOrientation(LinearLayout.VERTICAL);
            cardStatus.setPadding(16,16,16,16);
            cardStatus.setBackgroundColor(Color.parseColor("#232325"));
            TextView lbl = new TextView(c); lbl.setText("STATUS DASH"); lbl.setTextColor(Color.parseColor("#f4f2ee")); lbl.setTextSize(12); cardStatus.addView(lbl);
            DashViews.tvStatus = new TextView(c); DashViews.tvStatus.setText("uperf: -- | fas-rs: -- | monitor: -- | boost: --"); DashViews.tvStatus.setTextColor(Color.parseColor("#87878a")); DashViews.tvStatus.setTextSize(10); cardStatus.addView(DashViews.tvStatus);
            DashViews.indBoost = new TextView(c); DashViews.indBoost.setText("●"); DashViews.indBoost.setTextColor(Color.parseColor("#2ecc40")); DashViews.indBoost.setTextSize(14); cardStatus.addView(DashViews.indBoost);
            DashViews.tvSnapshot = new TextView(c); DashViews.tvSnapshot.setText("belum ada data"); DashViews.tvSnapshot.setTextColor(Color.parseColor("#87878a")); DashViews.tvSnapshot.setTextSize(10); cardStatus.addView(DashViews.tvSnapshot);
            root.addView(cardStatus);

            // Card GAME CONTROLS (F2)
            LinearLayout cardG = new LinearLayout(c); cardG.setOrientation(LinearLayout.VERTICAL); cardG.setPadding(16,16,16,16); cardG.setBackgroundColor(Color.parseColor("#232325"));
            TextView lblG = new TextView(c); lblG.setText("GAMES — KONTROL"); lblG.setTextColor(Color.parseColor("#f4f2ee")); lblG.setTextSize(12); cardG.addView(lblG);
            LinearLayout rowF = new LinearLayout(c); rowF.setOrientation(LinearLayout.HORIZONTAL);
            DashViews.btnF18_1 = makeBtn(c,"F18-1"); DashViews.btnF18_2 = makeBtn(c,"F18-2"); DashViews.btnF18_3 = makeBtn(c,"F18-3");
            rowF.addView(DashViews.btnF18_1); rowF.addView(DashViews.btnF18_2); rowF.addView(DashViews.btnF18_3); cardG.addView(rowF);
            LinearLayout rowF2 = new LinearLayout(c); rowF2.setOrientation(LinearLayout.HORIZONTAL);
            DashViews.btnF20_fast = makeBtn(c,"fas-fast"); DashViews.btnF20_bal = makeBtn(c,"fas-bal"); DashViews.btnF20_perf = makeBtn(c,"fas-perf");
            rowF2.addView(DashViews.btnF20_fast); rowF2.addView(DashViews.btnF20_bal); rowF2.addView(DashViews.btnF20_perf); cardG.addView(rowF2);
            LinearLayout rowF3 = new LinearLayout(c); rowF3.setOrientation(LinearLayout.HORIZONTAL);
            DashViews.btnF21_bal = makeBtn(c,"uperf-bal"); DashViews.btnF21_perf = makeBtn(c,"uperf-perf");
            rowF3.addView(DashViews.btnF21_bal); rowF3.addView(DashViews.btnF21_perf); cardG.addView(rowF3);
            DashViews.tvFpsLog = new TextView(c); DashViews.tvFpsLog.setText("FPS logbook (manual): belum ada data"); DashViews.tvFpsLog.setTextColor(Color.parseColor("#87878a")); DashViews.tvFpsLog.setTextSize(9); cardG.addView(DashViews.tvFpsLog);
            root.addView(cardG);

            // Card TOOLS (F3) + CUSTOM (F4) — disederhanakan: hanya tombol utama
            LinearLayout cardT = new LinearLayout(c); cardT.setOrientation(LinearLayout.VERTICAL); cardT.setPadding(16,16,16,16); cardT.setBackgroundColor(Color.parseColor("#232325"));
            TextView lblT = new TextView(c); lblT.setText("PERALATAN / CUSTOM"); lblT.setTextColor(Color.parseColor("#f4f2ee")); lblT.setTextSize(12); cardT.addView(lblT);
            DashViews.btnKillApps = makeBtn(c,"TUTUP APP"); DashViews.tvKillResult = new TextView(c); DashViews.tvKillResult.setText("-"); DashViews.tvKillResult.setTextColor(Color.parseColor("#87878a")); DashViews.tvKillResult.setTextSize(9); cardT.addView(DashViews.btnKillApps); cardT.addView(DashViews.tvKillResult);
            DashViews.btnSendLog = makeBtn(c,"KIRIM LOG"); DashViews.tvSendLogResult = new TextView(c); DashViews.tvSendLogResult.setText("-"); DashViews.tvSendLogResult.setTextColor(Color.parseColor("#87878a")); DashViews.tvSendLogResult.setTextSize(9); cardT.addView(DashViews.btnSendLog); cardT.addView(DashViews.tvSendLogResult);
            DashViews.btnThemeBW = makeBtn(c,"Tema BW"); DashViews.btnLangId = makeBtn(c,"ID"); DashViews.btnLangEn = makeBtn(c,"EN"); DashViews.btnBubblePosLeft = makeBtn(c,"Bubble Kiri"); DashViews.btnBubblePosRight = makeBtn(c,"Bubble Kanan");
            LinearLayout rowC = new LinearLayout(c); rowC.setOrientation(LinearLayout.HORIZONTAL);
            rowC.addView(DashViews.btnThemeBW); rowC.addView(DashViews.btnLangId); rowC.addView(DashViews.btnLangEn); cardT.addView(rowC);
            LinearLayout rowB = new LinearLayout(c); rowB.setOrientation(LinearLayout.HORIZONTAL);
            rowB.addView(DashViews.btnBubblePosLeft); rowB.addView(DashViews.btnBubblePosRight); cardT.addView(rowB);
            DashViews.tvCustomStatus = new TextView(c); DashViews.tvCustomStatus.setText("Tema: default | Pos: default | Bahasa: ID"); DashViews.tvCustomStatus.setTextColor(Color.parseColor("#87878a")); DashViews.tvCustomStatus.setTextSize(9); cardT.addView(DashViews.tvCustomStatus);
            DashViews.tvModule = new TextView(c); DashViews.tvModule.setText("Modul: v?"); DashViews.tvModule.setTextColor(Color.parseColor("#87878a")); DashViews.tvModule.setTextSize(9); cardT.addView(DashViews.tvModule);
            root.addView(cardT);

            // Pasang listener semua tombol v2 (pola HomeCards.setOnClickListener)
            DashViews.btnF18_1.setOnClickListener(v -> HelperGuard.run(a, "f18_1", () -> GamesControl.toggleFlag(a, 0, "EXTREME")));
            DashViews.btnF18_2.setOnClickListener(v -> HelperGuard.run(a, "f18_2", () -> GamesControl.toggleFlag(a, 1, "FORCE_ALPHA")));
            DashViews.btnF18_3.setOnClickListener(v -> HelperGuard.run(a, "f18_3", () -> GamesControl.toggleFlag(a, 2, "FORCE_OWNS")));
            DashViews.btnF20_fast.setOnClickListener(v -> HelperGuard.run(a, "f20_fast", () -> GamesControl.setFasMode(a, "", "fast")));
            DashViews.btnF20_bal.setOnClickListener(v -> HelperGuard.run(a, "f20_bal", () -> GamesControl.setFasMode(a, "", "balance")));
            DashViews.btnF20_perf.setOnClickListener(v -> HelperGuard.run(a, "f20_perf", () -> GamesControl.setFasMode(a, "", "performance")));
            DashViews.btnF21_bal.setOnClickListener(v -> HelperGuard.run(a, "f21_bal", () -> GamesControl.setUperfProfile(a, "balanced")));
            DashViews.btnF21_perf.setOnClickListener(v -> HelperGuard.run(a, "f21_perf", () -> GamesControl.setUperfProfile(a, "performance")));
            DashViews.btnKillApps.setOnClickListener(v -> HelperGuard.run(a, "kill", () -> new Thread(() -> AppKillHelper.killApp("com.example")))); // placeholder: user pilih via UI manual
            DashViews.btnSendLog.setOnClickListener(v -> HelperGuard.run(a, "log", () -> LogSender.send(a)));
            DashViews.btnThemeBW.setOnClickListener(v -> HelperGuard.run(a, "bw", () -> ThemeToggle.toggle(a)));
            DashViews.btnLangId.setOnClickListener(v -> HelperGuard.run(a, "id", () -> LangToggle.set(a, "id")));
            DashViews.btnLangEn.setOnClickListener(v -> HelperGuard.run(a, "en", () -> LangToggle.set(a, "en")));
            DashViews.btnBubblePosLeft.setOnClickListener(v -> HelperGuard.run(a, "left", () -> BubblePos.set(a, "left")));
            DashViews.btnBubblePosRight.setOnClickListener(v -> HelperGuard.run(a, "right", () -> BubblePos.set(a, "right")));

            // Set id untuk referensi (pakai ids.xml, tapi view baru perlu id agar bisa diupdate)
            DashViews.tvStatus.setId(android.R.id.content); // placeholder; sebenarnya kita pakai field statik

            // Kembalikan gaya tombol bawaan (hilang saat overlay layout dibuang)
            StyleRestore.apply(a);
        } catch (Throwable t) { Log.w(TAG, "inject gagal: "+t); }
    }

    private static Button makeBtn(Context c, String text) {
        Button b = new Button(c); b.setText(text); b.setTextSize(10); b.setBackgroundColor(Color.parseColor("#333")); b.setTextColor(Color.parseColor("#f4f2ee")); return b;
    }
}
