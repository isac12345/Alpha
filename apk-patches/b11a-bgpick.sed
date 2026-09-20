# Fix5a: buka editor crop setelah takePersist. Anchor unik 1x.
# v0=Uri (masih hidup), p0=Activity. move-result ke v1 (mati, dioverwrite
# baris berikut). Tanpa .locals baru.
s#    invoke-virtual {v2, v0, v1}, Landroid/content/ContentResolver;->takePersistableUriPermission(Landroid/net/Uri;I)V#    invoke-virtual {v2, v0, v1}, Landroid/content/ContentResolver;->takePersistableUriPermission(Landroid/net/Uri;I)V\n\n    invoke-static {p0, v0}, Lcom/alphabubble/BgEditor;->handlePick(Landroid/app/Activity;Landroid/net/Uri;)Z\n\n    move-result v1#
