# b32: tegakkan tab aktif tiap onResume (jaring pengaman stacking).
# Anchor: baris maybeOnboard sisipan b8 (ada tepat 1x setelah step Batch1,
# step ini jalan sesudahnya). p0 = Activity. Tanpa .locals baru.
s#    invoke-static {p0}, Lcom/alphabubble/HomeCards;->maybeOnboard(Landroid/app/Activity;)V#    invoke-static {p0}, Lcom/alphabubble/HomeCards;->maybeOnboard(Landroid/app/Activity;)V\n\n    invoke-static {p0}, Lcom/alphabubble/NavTabs;->refresh(Landroid/app/Activity;)V#
