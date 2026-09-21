# b16 hook: pasang listener slider transparansi kartu di onCreate (REV2 leader:
# anchor SATU BARIS, unik 1x — \n di pola sed tak pernah match).
# p0 = MainActivity. Tanpa .locals baru (hanya p0).
s#    invoke-direct {p0, v3}, Lcom/alphabubble/MainActivity;->setTab(Z)V#    invoke-static {p0}, Lcom/alphabubble/CardAlpha;->setupSeekBar(Landroid/app/Activity;)V\n    invoke-direct {p0, v3}, Lcom/alphabubble/MainActivity;->setTab(Z)V#
