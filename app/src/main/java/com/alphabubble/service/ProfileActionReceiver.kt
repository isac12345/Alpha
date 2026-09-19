package com.alphabubble.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.alphabubble.RootShell
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class ProfileActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val profile = intent.getStringExtra("profile") ?: return
        CoroutineScope(Dispatchers.IO).launch {
            RootShell.applyProfile(context, profile)
        }
    }
}