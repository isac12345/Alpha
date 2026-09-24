package com.alphabubble;

import android.util.Log;
import java.util.concurrent.TimeUnit;

// B2: tiap perintah root wajib timeout, cek exit code, quoting aman.
// - timeout default 20 detik (rentang 15-30 dtk per perintah)
// - waitFor dengan timeout, anggap gagal bila timeout
// - catat exit code via Log.w
// - quoting aman via quoteArg/buildCommand (tanpa拼接 string mentah dari input user)
public final class RootExecutor {
    private static final String TAG = "RootExecutor";
    public static final long DEFAULT_TIMEOUT_MS = 20000L;

    private RootExecutor() {}

    // Quoting POSIX aman: token alfanum dibiarkan, selain itu Bungkus '...' dan escape '.
    public static String quoteArg(String arg) {
        if (arg == null) return "''";
        if (arg.matches("[a-zA-Z0-9._/@:=-]+")) return arg;
        return "'" + arg.replace("'", "'\\''") + "'";
    }

    // Gabung token dengan quoting aman (hindari string mentah dari input user).
    public static String buildCommand(String... args) {
        if (args == null || args.length == 0) return "";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < args.length; i++) {
            if (i > 0) sb.append(' ');
            sb.append(quoteArg(args[i]));
        }
        return sb.toString();
    }

    // Eksekusi shellCommand via su -c dengan timeout default.
    public static boolean exec(String shellCommand) {
        return exec(shellCommand, DEFAULT_TIMEOUT_MS);
    }

    // Eksekusi via su -c dengan timeout custom; cek exit code; timeout = gagal.
    public static boolean exec(String shellCommand, long timeoutMs) {
        if (shellCommand == null) shellCommand = "";
        long to = timeoutMs > 0 ? timeoutMs : DEFAULT_TIMEOUT_MS;
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"su", "-c", shellCommand});
            boolean done;
            try {
                done = p.waitFor(to, TimeUnit.MILLISECONDS);
            } catch (InterruptedException ie) {
                Log.w(TAG, "exec interrupted: " + shellCommand + " : " + ie);
                Thread.currentThread().interrupt();
                try { p.destroy(); } catch (Throwable t) { Log.w(TAG, "destroy gagal: " + t); }
                return false;
            }
            if (!done) {
                Log.w(TAG, "exec timeout " + to + "ms: " + shellCommand);
                try { p.destroy(); } catch (Throwable t) { Log.w(TAG, "destroy gagal: " + t); }
                try { p.destroyForcibly(); } catch (Throwable t) { Log.w(TAG, "destroyForcibly gagal: " + t); }
                return false;
            }
            int code = p.exitValue();
            if (code != 0) {
                Log.w(TAG, "exec exit=" + code + ": " + shellCommand);
                return false;
            }
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "exec gagal: " + shellCommand + " : " + t);
            return false;
        }
    }

    // Varian aman untuk argumen user: tiap token di-quote lalu dieksekusi.
    public static boolean execTokens(String... tokens) {
        return exec(buildCommand(tokens), DEFAULT_TIMEOUT_MS);
    }

    public static boolean execTokens(long timeoutMs, String... tokens) {
        return exec(buildCommand(tokens), timeoutMs);
    }
}
