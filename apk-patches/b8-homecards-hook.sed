# Batch1 hook A: onCreate akhir -> HomeCards.attach. Anchor: baris
# setOnCheckedChangeListener terakhir + ".line 128" (unik, 1x).
# Tanpa ubah .locals (p0 = Activity).
s#    invoke-virtual {v1, v2}, Landroid/widget/Switch;->setOnCheckedChangeListener(Landroid/widget/CompoundButton\$OnCheckedChangeListener;)V#    invoke-virtual {v1, v2}, Landroid/widget/Switch;->setOnCheckedChangeListener(Landroid/widget/CompoundButton$OnCheckedChangeListener;)V\n\n    invoke-static {p0}, Lcom/alphabubble/HomeCards;->attach(Landroid/app/Activity;)V#
# Batch1 hook B: onResume setelah super -> refresh + onboard. Anchor unik 1x.
s#    invoke-super {p0}, Landroid/app/Activity;->onResume()V#    invoke-super {p0}, Landroid/app/Activity;->onResume()V\n\n    invoke-static {p0}, Lcom/alphabubble/HomeCards;->refresh(Landroid/app/Activity;)V\n\n    invoke-static {p0}, Lcom/alphabubble/HomeCards;->maybeOnboard(Landroid/app/Activity;)V#
