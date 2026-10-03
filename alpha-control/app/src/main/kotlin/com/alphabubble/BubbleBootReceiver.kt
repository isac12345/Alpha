package com.alphabubble
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
class BubbleBootReceiver : BroadcastReceiver() { override fun onReceive(c: Context, i: Intent) { if (i.action == Intent.ACTION_BOOT_COMPLETED) { c.startService(Intent(c, BubbleService::class.java)) } } }
