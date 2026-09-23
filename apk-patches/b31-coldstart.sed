# b31: cold start tertumpuk — onCreate (.line 92) memanggil setTab(v3)
# LAMA yang un-hide semua child by-index (cocok untuk layout lama 2 tab,
# merusak layout baru 4 tab + detail). Ganti dengan NavTabs.showDashboard
# (peta id benar). Anchor unik 1x (hanya call site ini pakai {p0, v3}).
# v3 mati sesudahnya; 2 lambda setTab lain (tombol lama, GONE) tak tersentuh.
# Tanpa .locals baru.
s#    invoke-direct {p0, v3}, Lcom/alphabubble/MainActivity;->setTab(Z)V#    invoke-static {p0}, Lcom/alphabubble/NavTabs;->showDashboard(Landroid/app/Activity;)V#
