# B1: activeDisplayInfo() baca Override dulu, fallback Physical.
# Alasan: find() regex dari posisi 0; pola lama (?:Override|Physical)
# selalu match baris "Physical size:" (baris pertama output wm size),
# walau Override aktif. Pola baru greedy [\s\S]* memaksa match terakhir
# (Override bila ada), fallback ke Physical bila tidak ada.
# Target 2 baris di activeDisplayInfo() saja; displayInfo() (Physical murni) TIDAK diubah.
s#const-string v8, "(?:Override|Physical) size: (\\\\d+)x(\\\\d+)"#const-string v8, "(?:[\\\\s\\\\S]*Override size: |Physical size: )(\\\\d+)x(\\\\d+)"#
s#const-string v11, "(?:Override|Physical) density: (\\\\d+)"#const-string v11, "(?:[\\\\s\\\\S]*Override density: |Physical density: )(\\\\d+)"#
