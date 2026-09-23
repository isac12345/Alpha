# b33: PAKAI BANNER DEFAULT ikut hapus crop (kunci + file) agar crop
# lama tak muncul lagi. Range dibatasi ke method clearAppBackground
# (chooseAppBackground yang memanggil applyAppBackground JUGA harus
# menyimpan crop -> jangan tersentuh). p0 = Activity. Tanpa .locals baru.
/^\.method public final clearAppBackground/,/^\.end method/ s#    invoke-virtual {p0}, Lcom/alphabubble/MainActivity;->applyAppBackground()V#    invoke-static {p0}, Lcom/alphabubble/BgFull;->clearCrop(Landroid/app/Activity;)V\n\n    invoke-virtual {p0}, Lcom/alphabubble/MainActivity;->applyAppBackground()V#
