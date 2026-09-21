# b16 hook: terapkan alpha kartu dari prefs tiap refresh (REV2 leader: anchor SATU
# BARIS — \n di pola sed tak pernah match). Cocok 2x: onResume + onCreate$lambda$10
# (tombol refresh manual); keduanya titik refresh valid dan applyFromPrefs idempoten.
# p0 = MainActivity di keduanya. Tanpa .locals baru (hanya p0).
s#    invoke-direct {p0}, Lcom/alphabubble/MainActivity;->refreshAll()V#    invoke-direct {p0}, Lcom/alphabubble/MainActivity;->refreshAll()V\n    invoke-static {p0}, Lcom/alphabubble/CardAlpha;->applyFromPrefs(Landroid/app/Activity;)V#
