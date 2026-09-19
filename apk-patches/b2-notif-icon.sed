# B2: ikon status bar monokrom. Ganti framework 0x108009b -> ic_stat_alpha
# 0x7f05001a (public.xml overlay). HANYA konstanta ini; method lain untouched.
# Anchor unik: setSmallIcon muncul 1x di BubbleService.smali.
s#const v3, 0x108009b#const v3, 0x7f05001a#
