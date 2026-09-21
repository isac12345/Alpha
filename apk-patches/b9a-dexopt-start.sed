# Batch2 hook A (REV b16): dexoptStart HANYA dari tombol COMPILE (REV2 leader: anchor
# SATU BARIS unik 1x — \n di pola tak pernah match).
# Akar (bukti decode): dulu hook di pemanggil openDexopt()V -> progres "Mengompilasi..."
# muncul saat dialog DIBUKA sehingga BATAL pun terlihat menjalankan compile. Jalur COMPILE
# asli = openDexopt$lambda$33$lambda$32 (hanya getButton(-0x1)/COMPILE yang dipasangi
# listener, MainActivity.smali:2064-2123; "Batal" listener null :1946-1952) ->
# lambda$31 baca paket+mode lalu coroutine di .line 217. p4 = this$0 MainActivity
# (lambda$31 params p0..p6, .locals 20). Tanpa .locals baru (hanya p4).
s#    iget-object v14, v8, Lcom/alphabubble/MainActivity;->scope:Lkotlinx/coroutines/CoroutineScope;#    invoke-static {p4}, Lcom/alphabubble/ToolsKit;->dexoptStart(Landroid/app/Activity;)V\n    iget-object v14, v8, Lcom/alphabubble/MainActivity;->scope:Lkotlinx/coroutines/CoroutineScope;#
