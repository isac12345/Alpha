# F2 hook: panggil HideFeedback.buzz() tepat sebelum applyVisibility.
# v0 berisi BubbleService (= Context) setelah iget-object, tanpa .locals/move baru.
# Target: BubbleService$2$1.smali run(), 1 kemunculan access$000.
s#    invoke-static {v0}, Lcom/alphabubble/BubbleService;->access\$000(Lcom/alphabubble/BubbleService;)V#    invoke-static {v0}, Lcom/alphabubble/HideFeedback;->buzz(Landroid/content/Context;)V\n    invoke-static {v0}, Lcom/alphabubble/BubbleService;->access$000(Lcom/alphabubble/BubbleService;)V#
