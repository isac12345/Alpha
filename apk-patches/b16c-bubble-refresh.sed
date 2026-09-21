# b16 hook (REV2 leader): tangani BUBBLE_STYLE_REFRESH di onStartCommand.
# Akar (bukti decode): onStartCommand (BubbleService.smali:2053-2110) hanya tangani
# BUBBLE_TOGGLE; REFRESH jatuh ke :cond_0 tanpa apply -> ukuran baru tak berlaku live;
# toggle off/on hanya applyVisibility sehingga ukuran lama bertahan; force-stop lewat
# attach (.line 289 applyLook) -> BubbleStyle.apply baca prefs fresh (BubbleStyle.java:59-62).
# NOL field static scale di smali (grep "static.*scale/size" kosong) -> tak ada cache yang
# perlu dibersihkan; tangani REFRESH + baca-prefs-tiap-apply = perbaikan akar.
# Anchor SATU BARIS unik 1x (cek equals TOGGLE; di titik ini p1 = action String,
# v0/v1 MATI -> aman). Tanpa .locals baru. p0 = BubbleService.
s#    invoke-virtual {p3, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z#    const-string v0, "com.alphabubble.BUBBLE_STYLE_REFRESH"\n    invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n    move-result v0\n    if-eqz v0, :not_refresh16\n    invoke-direct {p0}, Lcom/alphabubble/BubbleService;->applyLook()V\n    goto :cond_0\n    :not_refresh16\n    invoke-virtual {p3, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z#
