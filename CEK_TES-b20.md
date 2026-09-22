# CEK_TES-b20 — Uji fix radio Fill/Fit + cropRatio (Alpha Fusion v1-b20, versionCode 20)

HP uji: 720x1600. APK timpa biasa (cert sama).

## 1. Radio Fill/Fit (dialog "Atur latar")
1. Pilih background custom dari galeri → dialog editor terbuka.
2. Default: HANYA lingkaran Fill yang terisi; Fit kosong.
3. Ketuk Fit → HANYA Fit yang terisi; Fill kosong. Ketuk Fill lagi → kembali.
4. SIMPAN di tiap mode → latar tersimpan tanpa error/FC.

## 2. cropRatio tanpa fallback salah
1. `adb logcat -c`, lalu pasang background custom mode Fill.
2. `adb logcat -d | grep -i "cropRatio"` → TIDAK BOLEH ada baris
   `metrics 0, fallback` / `metrics ctx 0` / `metrics TOTAL 0`.
   (Bila muncul `pakai system 720x1600` = fallback lapis-4 kepakai —
   laporkan; bila muncul `TOTAL 0` + Toast "Ukuran layar tak terbaca"
   = laporkan segera.)
3. Hasil Fill: penuh ke pojok bawah layar 720x1600, tanpa terpotong
   seperti bug lama; Fit: utuh + letterbox hitam bila perlu.

## Regresi
- Kartu, bubble, dexopt, resolusi, game_add live, GameBoost tetap normal (b18/b19).
