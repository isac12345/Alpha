package com.alphabubble;

import android.content.Context;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.util.Log;
import android.widget.Toast;

public final class HideFeedback {
    private static final String TAG = "HideFeedback";

    private HideFeedback() {}

    public static void buzz(Context c) {
        final Context ctx = c;
        HelperGuard.run(ctx, "buzz", () -> buzzInner(ctx));
    }

    private static void buzzInner(Context c) {
        if (c == null) {
            Log.w(TAG, "buzz: context null, dilewati");
            return;
        }
        try {
            Vibrator v = (Vibrator) c.getSystemService(Context.VIBRATOR_SERVICE);
            if (v != null && v.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= 26) {
                    v.vibrate(VibrationEffect.createOneShot(30, VibrationEffect.DEFAULT_AMPLITUDE));
                } else {
                    v.vibrate(30);
                }
            } else {
                Log.w(TAG, "buzz: vibrator tidak tersedia");
            }
        } catch (Throwable t) {
            Log.w(TAG, "buzz: vibrate gagal: " + t);
        }
        try {
            Toast.makeText(c, "Bubble disembunyikan", Toast.LENGTH_SHORT).show();
        } catch (Throwable t) {
            Log.w(TAG, "buzz: toast gagal: " + t);
        }
    }
}
