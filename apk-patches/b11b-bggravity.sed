# Fix5b (REVISI b25): gravity FILL agar bitmap mengisi penuh bounds View.
# CENTER (0x11) TERBUKTI salah: bitmap tampil ukuran intrinsic di tengah,
# area tak tertutup jadi transparan -> tembus ke background abu tema
# (bug background bawah abu-abu). 0x77 = Gravity.FILL.
# Anchor: setBackground(Drawable) unik 1x. v0 bebas sesudahnya (try_end),
# v2=BitmapDrawable, v4=View. Tanpa .locals baru.
s#    invoke-virtual {v4, v2}, Landroid/view/View;->setBackground(Landroid/graphics/drawable/Drawable;)V#    const/16 v0, 0x77\n\n    invoke-virtual {v2, v0}, Landroid/graphics/drawable/BitmapDrawable;->setGravity(I)V\n\n    invoke-virtual {v4, v2}, Landroid/view/View;->setBackground(Landroid/graphics/drawable/Drawable;)V#
