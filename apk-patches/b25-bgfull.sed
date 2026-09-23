# b25: background full-height — panggil BgFull.apply sesudah tiap pemanggilan
# applyAppBackground()V di MainActivity.smali. Pola cocok TEPAT 3x (grep -c = 3):
# clearAppBackground, onActivityResult, onCreate — ketiganya MainActivity aktif
# (p0), tanpa ubah .locals. Catatan: clearAppBackground hanya remove app_bg_uri
# (bukan app_bg_crop); bila crop sisa di prefs, BgFull bisa re-apply gambar
# sesudah clear — risiko diketahui, bukan crash. Anchor: 4 spasi + invoke.
s#    invoke-virtual {p0}, Lcom/alphabubble/MainActivity;->applyAppBackground()V#    invoke-virtual {p0}, Lcom/alphabubble/MainActivity;->applyAppBackground()V\n\n    invoke-static {p0}, Lcom/alphabubble/BgFull;->apply(Landroid/app/Activity;)V#
