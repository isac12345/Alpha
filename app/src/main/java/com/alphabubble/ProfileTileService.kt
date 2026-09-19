package com.alphabubble

import android.content.Context
import android.graphics.drawable.Icon
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class ProfileTileService : TileService() {

    override fun onClick() {
        super.onClick()
        val tile = qsTile
        if (tile == null) return
        tile.state = Tile.STATE_INACTIVE
        tile.updateTile()

        CoroutineScope(Dispatchers.IO).launch {
            val current = RootShell.readCurrentState() ?: "balanced"
            val profiles = NotifHelper.PROFILES
            val idx = profiles.indexOf(current)
            val next = profiles[(idx + 1) % profiles.size]
            val result = RootShell.applyProfile(this@ProfileTileService, next)
            if (result.success) {
                updateTile(next)
            }
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        CoroutineScope(Dispatchers.IO).launch {
            val profile = RootShell.readCurrentState() ?: "balanced"
            updateTile(profile)
        }
    }

    private fun updateTile(profile: String) {
        val tile = qsTile ?: return
        mainExecutor.execute {
            tile.icon = Icon.createWithResource(this, R.drawable.ic_notification_small)
            tile.label = NotifHelper.labelFor(profile)
            tile.state = Tile.STATE_ACTIVE
            tile.updateTile()
        }
    }
}