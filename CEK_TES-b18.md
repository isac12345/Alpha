# CEK_TES-b18 — Uji 3 perbaikan bug (Alpha Fusion v1-b18, versionCode 18)

## 1. game_add live tanpa reboot
1. `su -c 'sh /data/adb/modules/alpha_uperf_fasrs_fusion/common/game_add.sh add <pkg> 60 performance'` → cek `/sdcard/Android/fas-rs/games.toml` LANGSUNG ada `<pkg>` (tanpa reboot).
2. `... game_add.sh remove <pkg>` → cek games.toml LANGSUNG hilang + `game_profile_map.conf` tidak lagi berisi `<pkg>`.
3. Cek alpha.log ada `live merge: OK`.

## 2. GameBoost via monitor
1. Mainkan game yang map-nya `performance` → cek alpha.log ada `[GAMEBOOST] APPLIED`.
2. Cek nilai node CPU/GPU benar berubah (bandingkan sebelum/sesudah).
3. Keluar game 12 dtk → ada `RESTORED`. Tidak boleh ada `WARN: gb_apply unavailable` / `WARN: gb_restore unavailable` bila gameboost.sh ada.

## 3. Crop background rasio layar
1. Di APK: pilih background custom dari galeri → mode Fill harus mengisi penuh layar tanpa gepeng (crop tengah sesuai rasio layar), mode Fit menampilkan utuh tanpa terpotong (letterbox hitam bila perlu).
2. Bandingkan dengan b17: background lebar tidak lagi jadi kotak.

## Regresi
- Kartu, bubble, dexopt, resolusi tetap normal seperti b16/b17. APK timpa biasa (cert sama).
