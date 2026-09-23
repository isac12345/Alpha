# b25: background full-height — panggil BgFull.apply sesudah setBackground
# di applyAppBackground (anchor SAMA unik 1x seperti b11b; berlaku apapun
# urutan b11b/b25 karena baris asli tetap muncul tepat 1x).
# p0 = MainActivity (Activity). v0/v2/v4 MATI sesudahnya (try_end lalu
# return-void). Tanpa .locals baru.
s#    invoke-virtual {v4, v2}, Landroid/view/View;->setBackground(Landroid/graphics/drawable/Drawable;)V#    invoke-virtual {v4, v2}, Landroid/view/View;->setBackground(Landroid/graphics/drawable/Drawable;)V\n\n    invoke-static {p0}, Lcom/alphabubble/BgFull;->apply(Landroid/app/Activity;)V#
