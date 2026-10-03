package com.alphabubble
import android.service.quicksettings.TileService
class ProfileTileService : TileService() { override fun onClick() { val r = RootShell(); Thread { r.run("cat /data/adb/alpha/current_state"); }.start() } }
