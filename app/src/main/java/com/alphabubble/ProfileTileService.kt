package com.alphabubble

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Quick Settings tile: tap untuk berputar DAILY -> BALANCED -> PERF. */
class ProfileTileService : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onStartListening() {
        super.onStartListening()
        scope.launch { render(Alpha.status()?.profile ?: "none") }
    }

    override fun onClick() {
        super.onClick()
        scope.launch {
            val cur = Alpha.status()?.profile ?: "none"
            val next = PROFILE_KEYS[(PROFILE_KEYS.indexOf(cur) + 1) % PROFILE_KEYS.size]
            render(next)
            Alpha.setProfile(next)
            render(Alpha.status()?.profile ?: next)
        }
    }

    private fun render(p: String) {
        val t = qsTile ?: return
        t.label = "Alpha ${profileLabel(p)}"
        t.state = if (p == "none") Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
        t.updateTile()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
