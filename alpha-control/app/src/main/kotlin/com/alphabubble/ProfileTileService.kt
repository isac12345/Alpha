package com.alphabubble
import android.service.quicksettings.TileService
import android.widget.Toast

// Tile QS: ketuk = ganti profil ke berikutnya; subtitle = profil aktif.
// Modul cari module.prop id=alpha_uperf_fasrs_fusion di 3 lokasi (lihat MOD_DIRS).
class ProfileTileService : TileService() {
    private val root = RootShell()

    private fun modDir(): String =
        MOD_DIRS.firstOrNull { java.io.File(it, "module.prop").isFile } ?: ""

    override fun onStartListening() {
        super.onStartListening()
        val active = readActive()
        qsTile?.let {
            it.state = android.service.quicksettings.Tile.STATE_INACTIVE
            it.label = "Alpha Control"
            it.contentDescription = active.ifEmpty { "Profil tidak terbaca" }
            it.updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val mod = modDir()
        if (mod.isEmpty()) {
            Toast.makeText(this, "Gagal: modul tidak ditemukan", Toast.LENGTH_SHORT).show()
            return
        }
        val current = readActive().lowercase()
        val next = when {
            current.startsWith("batt") || current.startsWith("dail") -> "balanced"
            current.startsWith("balanc") -> "performance"
            else -> "battery"
        }
        root.run("sh $mod/common/apply_now.sh $next") { out ->
            val ok = !out.contains("Gagal")
            Toast.makeText(this, if (ok) "Profil: $next" else "Gagal: ganti profil", Toast.LENGTH_SHORT).show()
            onStartListening()
        }
    }

    private fun readActive(): String {
        var out = ""
        root.run("cat /data/adb/alpha/current_state 2>/dev/null") { out = it.trim() }
        return out
    }

    companion object {
        val MOD_DIRS = listOf(
            "/data/adb/modules/alpha_uperf_fasrs_fusion",
            "/data/adb/ksu/modules/alpha_uperf_fasrs_fusion",
            "/data/adb/ap/modules/alpha_uperf_fasrs_fusion"
        )
    }
}