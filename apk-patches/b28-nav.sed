# b28: bottom nav — NavTabs.attach sesudah setContentView di onCreate.
# Anchor unik 1x (setContentView cuma 1x di MainActivity). p0 = Activity.
# Views sudah inflate; HomeCards.attach (b8, akhir onCreate) jalan sesudahnya
# dan kartu BUBBLE-nya diatur NavTabs.show saat tab Dashboard aktif.
# Tanpa .locals baru.
s#    invoke-virtual {p0, v0}, Lcom/alphabubble/MainActivity;->setContentView(I)V#    invoke-virtual {p0, v0}, Lcom/alphabubble/MainActivity;->setContentView(I)V\n\n    invoke-static {p0}, Lcom/alphabubble/NavTabs;->attach(Landroid/app/Activity;)V#
