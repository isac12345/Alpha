# CEK_TES-b17 — Uji Porting Extreme HSIN (Alpha Fusion v1-b17)

## (a) Extreme vs Balanced (satu game, mis. PGR)
1. `pgr-log start`, profil Balanced, main 10 mnt stage berat, catat: FPS rata-rata, jumlah drop, suhu maks (lihat game-log.csv).
2. Ganti map game ke performance (`game_add.sh add <pkg> 60 performance`), main lagi 10 mnt, catat sama.
3. Bandingkan: Extreme harus FPS lebih stabil + suhu <85C. Cek alpha.log ada `[GAMEBOOST] APPLIED` + `fas-rs mode=fast`.
4. Keluar game 12 dtk: harus ada `RESTORED`, governor/GPU kembali (cek `pgr-log stop` + kolom csv).

## (b) Daily (pemakaian normal 1-2 jam)
1. Profil Daily (tombol DAILY di APK). Pakai normal: scroll, buka app, video.
2. Catat: lag (ya/tidak, di app apa), drain baterai per jam (%), suhu.
3. Buka game casual saat Daily: harus naik ke Balanced lalu kembali ke Daily (+12 dtk, cek log `PROMOTE`/`DAILY RESTORED`).

## (c) Tambah game
- fas-rs + uperf + map: `su -c 'sh /data/adb/modules/alpha_uperf_fasrs_fusion/common/game_add.sh add <pkg> 30,60 performance'` lalu `list` untuk cek. Efek fas-rs aktif setelah reboot (merge games.toml).
- AsoulOpt: TIDAK bisa ditambah (binary hardcoded 270 paket). Cek cakupan: `su -c 'strings /data/adb/modules/asoul_affinity_opt/AsoulOpt' | grep <pkg>`.
- PGR EN tidak ada di AsoulOpt maupun games.toml bawaan — tambah manual via perintah di atas.

## Bila aneh
`touch /data/adb/alpha/NO_CPUSET` lalu `GAMEBOOST_NO_VM` (satu per satu), `DISABLE_GAMEBOOST` untuk pembanding. Kirim game-log.csv + alpha.log.
