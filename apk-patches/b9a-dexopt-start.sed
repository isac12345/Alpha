# Batch2 hook A (REV b16): dexoptStart HANYA dari tombol COMPILE (REV3 leader: anchor
# SATU BARIS unik 1x; insert pakai v8 BUKAN p4 — {p4} di fresh decode resolve ke v24
# di luar jangkauan method (build 16 run 35561280307: "Invalid register: v24").
# v8 TERBUKTI valid: baris anchor berikutnya (iget-object v14, v8, ...scope...) deref v8
# sebagai MainActivity (move-object/from16 v8, p4 di awal lambda$31), jadi v8 = Activity
# untuk dexoptStart. Tanpa .locals baru.
s#    iget-object v14, v8, Lcom/alphabubble/MainActivity;->scope:Lkotlinx/coroutines/CoroutineScope;#    invoke-static {v8}, Lcom/alphabubble/ToolsKit;->dexoptStart(Landroid/app/Activity;)V\n    iget-object v14, v8, Lcom/alphabubble/MainActivity;->scope:Lkotlinx/coroutines/CoroutineScope;#
