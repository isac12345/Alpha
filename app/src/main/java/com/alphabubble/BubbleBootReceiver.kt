package com.alphabubble

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.alphabubble.Prefs
import com.alphabubble.service.FloatingBubbleService
import com.alphabubble.service.ProfileMonitorService

class BubbleBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            if (Prefs.isAutostart(context)) {
                context.startForegroundService(Intent(context, FloatingBubbleService::class.java))
                context.startForegroundService(Intent(context, ProfileMonitorService::class.java))
            }
        }
    }
}