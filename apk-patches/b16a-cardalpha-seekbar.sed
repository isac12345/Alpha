# Batch3 hook C2: setup card alpha seekbar in onCreate. Anchor: invoke-direct setTab (unik 1x di onCreate).
# p0 = MainActivity. Tanpa .locals baru.
s#    invoke-direct {p0, v3}, Lcom/alphabubble/MainActivity;->setTab\(Z\)V#    invoke-static {p0}, Lcom/alphabubble/CardAlpha;->setupSeekBar(Landroid/app/Activity;)V\n    invoke-direct {p0, v3}, Lcom/alphabubble/MainActivity;->setTab(Z)V#