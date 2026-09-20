# Fix5b: gravity CENTER agar bitmap tidak stretch dari kiri-atas.
# Anchor: setBackground(Drawable) unik 1x. v0 bebas sesudahnya (try_end),
# v2=BitmapDrawable, v4=View. 0x11 = Gravity.CENTER. Tanpa .locals baru.
s#    invoke-virtual {v4, v2}, Landroid/view/View;->setBackground(Landroid/graphics/drawable/Drawable;)V#    const/16 v0, 0x11\n\n    invoke-virtual {v2, v0}, Landroid/graphics/drawable/BitmapDrawable;->setGravity(I)V\n\n    invoke-virtual {v4, v2}, Landroid/view/View;->setBackground(Landroid/graphics/drawable/Drawable;)V#
