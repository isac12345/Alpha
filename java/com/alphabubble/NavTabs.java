package com.alphabubble;

import android.app.Activity;
import android.graphics.Color;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.ScrollView;

// b28: bottom nav 4 tab (DASH/GAMES/CUSTOM/TOOLS) + detail Customize.
// MURNI visibility groups di 1 Activity (tanpa Activity/Fragment baru):
// semua view lama pindah grup, logika lama (BgEditor, CardAlpha,
// apply/resolusi/dexopt) tak diubah. Dipanggil sekali dari onCreate.
public final class NavTabs {
    private static final String TAG = "NavTabs";
    private static final int CARD_ID = 0x00B0BB1E; // kartu BUBBLE injeksi HomeCards

    private static final String TAB_DASH = "dashboard";
    private static final String TAB_GAMES = "games";
    private static final String TAB_CUSTOM = "customize";
    private static final String TAB_TOOLS = "tools";

    private NavTabs() {}

    public static void attach(final Activity a) {
        HelperGuard.run(a, "navAttach", () -> {
            wire(a, "navDash", TAB_DASH);
            wire(a, "navGames", TAB_GAMES);
            wire(a, "navCustomize", TAB_CUSTOM);
            wire(a, "navTools", TAB_TOOLS);
            wireDetail(a, "btnCusBg", "detailBg");
            wireDetail(a, "btnCusIcon", "detailIcon");
            wireDetail(a, "btnCusHud", "detailHud");
            wireBack(a, "btnBackBg");
            wireBack(a, "btnBackIcon");
            wireBack(a, "btnBackHud");
            show(a, TAB_DASH);
        });
    }

    public static void show(final Activity a, final String tab) {
        HelperGuard.run(a, "navShow", () -> showInner(a, tab));
    }

    public static void openDetail(final Activity a, final String detail) {
        HelperGuard.run(a, "navDetail", () -> {
            setVisible(a, "tabDashboard", false);
            setVisible(a, "tabGames", false);
            setVisible(a, "tabCustomize", false);
            setVisible(a, "tabTools", false);
            setVisible(a, detail, true);
            paintTab(a, null);
            scrollTop(a);
        });
    }

    public static void goBack(final Activity a) {
        HelperGuard.run(a, "navBack", () -> showInner(a, TAB_CUSTOM));
    }

    private static void showInner(Activity a, String tab) throws Throwable {
        if (tab == null) tab = TAB_DASH;
        setVisible(a, "tabDashboard", TAB_DASH.equals(tab));
        setVisible(a, "tabGames", TAB_GAMES.equals(tab));
        setVisible(a, "tabCustomize", TAB_CUSTOM.equals(tab));
        setVisible(a, "tabTools", TAB_TOOLS.equals(tab));
        setVisible(a, "detailBg", false);
        setVisible(a, "detailIcon", false);
        setVisible(a, "detailHud", false);
        // Kartu BUBBLE injeksi: hanya di Dashboard (perilaku setTab lama).
        View bubble = find(a, CARD_ID);
        if (bubble != null) bubble.setVisibility(TAB_DASH.equals(tab) ? View.VISIBLE : View.GONE);
        paintTab(a, tab);
        scrollTop(a);
        if (TAB_GAMES.equals(tab)) refreshGames(a);
    }

    // Pemicu loadGames() asli via reflection (private, tanpa argumen).
    // Pola reflection sama seperti BubbleStyle (field service).
    private static void refreshGames(Activity a) {
        try {
            java.lang.reflect.Method m = a.getClass().getDeclaredMethod("loadGames");
            m.setAccessible(true);
            m.invoke(a);
        } catch (Throwable t) {
            Log.w(TAG, "loadGames gagal: " + t);
        }
    }

    private static void paintTab(Activity a, String active) throws Throwable {
        paintBtn(a, "navDash", TAB_DASH.equals(active));
        paintBtn(a, "navGames", TAB_GAMES.equals(active));
        paintBtn(a, "navCustomize", TAB_CUSTOM.equals(active));
        paintBtn(a, "navTools", TAB_TOOLS.equals(active));
    }

    private static void paintBtn(Activity a, String id, boolean on) throws Throwable {
        View v = find(a, id);
        if (!(v instanceof Button)) return;
        Button b = (Button) v;
        // b30: glow teal (nav_glow layer-list) + elevation, tanpa ubah listener.
        try {
            if (on) {
                int glow = a.getResources().getIdentifier("nav_glow", "drawable", a.getPackageName());
                if (glow != 0) b.setBackground(a.getResources().getDrawable(glow));
                b.setTextColor(Color.parseColor("#0a0a0a"));
                b.setElevation(4f * a.getResources().getDisplayMetrics().density);
            } else {
                b.setBackgroundColor(Color.parseColor("#00000000"));
                b.setTextColor(Color.parseColor("#87878a"));
                b.setElevation(0f);
            }
        } catch (Throwable t) {
            Log.w(TAG, "paint gagal: " + t);
        }
    }

    private static void scrollTop(Activity a) {
        try {
            View root = find(a, "scrollRoot");
            if (root instanceof ScrollView) ((ScrollView) root).smoothScrollTo(0, 0);
        } catch (Throwable t) {
            Log.w(TAG, "scrollTop gagal: " + t);
        }
    }

    private static void setVisible(Activity a, String id, boolean show) throws Throwable {
        View v = find(a, id);
        if (v != null) v.setVisibility(show ? View.VISIBLE : View.GONE);
    }

    private static void wire(final Activity a, String btnId, final String tab) throws Throwable {
        View v = find(a, btnId);
        if (!(v instanceof Button)) {
            Log.w(TAG, "tombol " + btnId + " tak ketemu");
            return;
        }
        ((Button) v).setOnClickListener(view -> show(a, tab));
    }

    private static void wireDetail(final Activity a, String btnId, final String detail) throws Throwable {
        View v = find(a, btnId);
        if (!(v instanceof Button)) {
            Log.w(TAG, "tombol " + btnId + " tak ketemu");
            return;
        }
        ((Button) v).setOnClickListener(view -> openDetail(a, detail));
    }

    private static void wireBack(final Activity a, String btnId) throws Throwable {
        View v = find(a, btnId);
        if (!(v instanceof Button)) {
            Log.w(TAG, "tombol " + btnId + " tak ketemu");
            return;
        }
        ((Button) v).setOnClickListener(view -> goBack(a));
    }

    private static View find(Activity a, String name) throws Throwable {
        int id = a.getResources().getIdentifier(name, "id", a.getPackageName());
        if (id == 0) return null;
        return a.findViewById(id);
    }

    private static View find(Activity a, int id) {
        try {
            return a.findViewById(id);
        } catch (Throwable t) {
            Log.w(TAG, "find gagal: " + t);
            return null;
        }
    }
}
