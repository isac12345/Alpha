package com.alphabubble;

import android.app.Activity;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.util.Log;
import java.util.Locale;

// F4-15 bahasa ID/EN: toggles locale + recreate
public final class LangToggle {
    private static final String PREFS = "alpha_lang";
    private static final String KEY = "lang";
    private LangToggle() {}

    public static void set(Activity a, String lang) {
        if (a == null) return;
        a.getSharedPreferences(PREFS, Activity.MODE_PRIVATE).edit().putString(KEY, lang).apply();
        Locale locale = new Locale("id".equals(lang) ? "id" : "en");
        Locale.setDefault(locale);
        Configuration cfg = new Configuration();
        cfg.locale = locale;
        a.getResources().updateConfiguration(cfg, a.getResources().getDisplayMetrics());
        a.recreate();
        Log.i("LangToggle", "lang=" + lang);
    }
}
