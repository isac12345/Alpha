# b16 hook: gaya dialog dexopt (gelap membulat + tombol pill) (REV2 leader: anchor
# SATU BARIS unik 1x di openDexopt, MainActivity.smali:2007 — \n di pola tak pernah match).
# v8 = AlertDialog hasil create(). Tanpa .locals baru.
s#    invoke-virtual {v8}, Landroid/app/AlertDialog;->show()V#    invoke-virtual {v8}, Landroid/app/AlertDialog;->show()V\n    invoke-static {v8}, Lcom/alphabubble/ToolsKit;->styleDexoptDialog(Landroid/app/AlertDialog;)V#
