package com.alphabubble.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.IBinder
import android.graphics.drawable.Icon
import androidx.core.app.NotificationCompat
import com.alphabubble.NotifHelper
import com.alphabubble.Prefs
import com.alphabubble.R
import com.alphabubble.RootShell
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class ProfileMonitorService : Service() {

    companion object {
        const val CHANNEL_ID = "alpha_profile"
        const val NOTIF_ID = 42
    }

    private var monitorJob: Job? = null
    private var lastProfile = ""
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun onCreate() {
        super.onCreate()
        createChannel()
        if (Prefs.isNotifEnabled(this)) {
            scope.launch {
                val profile = RootShell.readCurrentState() ?: "balanced"
                val hasRoot = RootShell.hasRoot()
                val modulePath = RootShell.findModulePath(this@ProfileMonitorService)
                startForeground(NOTIF_ID, buildNotification(profile, hasRoot, modulePath))
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!Prefs.isNotifEnabled(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        monitorJob?.cancel()
        monitorJob = scope.launch {
            while (true) {
                checkAndUpdate()
                delay(3000) // check every 3 seconds
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        monitorJob?.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Alpha Profile", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Active profile status"
            channel.setShowBadge(false)
            channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun checkAndUpdate() {
        scope.launch {
            val profile = RootShell.readCurrentState() ?: "balanced"
            val hasRoot = RootShell.hasRoot()
            val modulePath = RootShell.findModulePath(this@ProfileMonitorService)

            if (profile != lastProfile || !Prefs.isNotifEnabled(this@ProfileMonitorService)) {
                lastProfile = profile
                updateNotification(profile, hasRoot, modulePath)
            }
        }
    }

    private fun buildNotification(profile: String, hasRoot: Boolean, modulePath: String?): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_small)
            .setContentTitle(NotifHelper.titleFor(profile))
            .setContentText("Root: ${if (hasRoot) "OK" else "NO"} | Module: ${modulePath ?: "NOT FOUND"}")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(getTapIntent())
            .addAction(getProfileAction("battery"))
            .addAction(getProfileAction("balanced"))
            .addAction(getProfileAction("performance"))
            .build()
    }

    private fun updateNotification(profile: String, hasRoot: Boolean, modulePath: String?) {
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_small)
            .setContentTitle(NotifHelper.titleFor(profile))
            .setContentText("Root: ${if (hasRoot) "OK" else "NO"} | Module: ${modulePath ?: "NOT FOUND"}")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(getTapIntent())
            .addAction(getProfileAction("battery"))
            .addAction(getProfileAction("balanced"))
            .addAction(getProfileAction("performance"))
            .build()
        (getSystemService(NotificationManager::class.java)).notify(NOTIF_ID, notif)
    }

    private fun getTapIntent(): PendingIntent {
        val intent = FloatingBubbleService.getShowIntent(this)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getService(this, 0, intent, flags)
    }

    private fun getProfileAction(profile: String): NotificationCompat.Action {
        val intent = Intent(this, ProfileActionReceiver::class.java).putExtra("profile", profile)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_IMMUTABLE else 0
        val pending = PendingIntent.getBroadcast(this, profile.hashCode(), intent, flags)
        return NotificationCompat.Action.Builder(
            Icon.createWithResource(this, R.drawable.ic_notification_small),
            NotifHelper.labelFor(profile),
            pending
        ).build()
    }
}