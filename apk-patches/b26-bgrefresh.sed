# b26: refresh background tiap kembali ke Activity utama (termasuk dari
# dialog Atur latar yang window-nya terpisah dan tak lewat onCreate).
# Anchor: super onResume, unik 1x (baris yang sama dipakai b8 hook B,
# tapi baris super-nya tetap ada tepat 1x apapun urutan aplikasi).
# p0 = MainActivity (Activity). Tanpa .locals baru.
s#    invoke-super {p0}, Landroid/app/Activity;->onResume()V#    invoke-super {p0}, Landroid/app/Activity;->onResume()V\n\n    invoke-static {p0}, Lcom/alphabubble/BgFull;->apply(Landroid/app/Activity;)V#
