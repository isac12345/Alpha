package com.alphabubble
import android.service.quicksettings.TileService
class ProfileTileService : TileService() { override fun onClick() { val r = RootShell(); kotlinx.coroutines.GlobalScope.launch { r.run("cat /data/adb/alpha/current_state"); } } }
