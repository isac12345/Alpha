# FIXLOG.md — catatan perbaikan yang SUDAH disetujui user (L2)

Aturan (AGENTS.md no. 8): tiap perbaikan wajib lewat 2 langkah.
L1 = leader verifikasi teknis + bukti. L2 = user tes di HP + bilang OK.
HANYA yang L2 yang masuk file ini + repo arsip modulroot.
Bahasa sederhana biar gampang diingat.

## 2026-09-22 — Aplikasi versi 20 (yang baru, bukan yang lama)
- L1: run CI `35729531470` SUCCESS; APK `versionCode='20'`,
  stempel `CN=Alpha Control`; isi ZIP identik dengan APK.
- L2: user "alhamdulillah" (2026-09-22).
- Arsip: rilis GitHub `v1.0.0` (diganti file baru) +
  `/sdcard/alpha/Alpha-Fusion-v1.zip`.
- Pelajaran: ada 2 file stempel; yang cocok password = `alpha-new.jks`
  (bukan `alpha-release.jks`).

## 2026-09-22 — Modul RC2 + pengaman panas T5
- L1: sandbox 70/70, unit `_gb_level` 6/6, `gb_apply` 4/4,
  monitor 3/3; `sh -n` + shellcheck 0 error.
- L2: user tes di HP — buka-tutup game PASS, uji panas PASS
  (perangkat setara RC2 penuh).
- Arsip: modul di rilis `v1.0.0` + `/sdcard/alpha/Alpha-Fusion-v1.zip`.

## 2026-09-25 — Modul32 PGR-kenceng
- L1: CI `36016623318` SUCCESS; T615 sandbox p6 1040000→1228800,
  p0 tetap 614400; zip `Alpha-Fusion-v32-pgr.zip` md5 `49c323ab`.
- L2: user 2026-09-25 lapor PGR gacor/OK; WuWa belum dites.
- Arsip: BELUM push ke `arsip`.

## 2026-09-19 — Build 7: 1 ikon + shortcut + notifikasi monokrom
- L1: pipeline SUCCESS saat itu (ID run sudah kedaluwarsa di GitHub,
  tidak bisa dicek ulang; tag lokal `v7-tested` ada).
- L2: user tes di HP: lolos.
- Arsip: tag `v7-tested` + merge ke master (riwayat lama).
