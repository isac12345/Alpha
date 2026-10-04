package com.alphabubble

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Settings

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val p = Prefs(context)
        if (p.autostart && p.bubbleOn && Settings.canDrawOverlays(context)) {
            BubbleService.start(context)
        }
    }
}
