package com.alphabubble
import android.app.Service
import android.content.Intent
import android.os.IBinder
class BubbleService : Service() { override fun onBind(i: Intent?): IBinder? = null; override fun onStartCommand(i: Intent?, f: Int, sId: Int): Int { startForeground(1, android.app.Notification.Builder(this,"alpha").setContentTitle("Alpha Bubble").build()); return START_STICKY } }
