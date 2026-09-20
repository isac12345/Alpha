# Batch2 hook B: hasil dexopt -> dialog durasi+status. Anchor: Toast.makeText
# unik 1x di file result. v1=Context(Activity), v2=teks hasil. Tanpa .locals baru.
s#    invoke-static {v1, v2, v3}, Landroid/widget/Toast;->makeText(Landroid/content/Context;Ljava/lang/CharSequence;I)Landroid/widget/Toast;#    invoke-static {v1, v2}, Lcom/alphabubble/ToolsKit;->dexoptDone(Landroid/app/Activity;Ljava/lang/CharSequence;)V\n    invoke-static {v1, v2, v3}, Landroid/widget/Toast;->makeText(Landroid/content/Context;Ljava/lang/CharSequence;I)Landroid/widget/Toast;#
