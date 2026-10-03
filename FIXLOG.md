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

## 2026-10-03 — Alpha Control v2 rebuilt (4 tab) — L2 LOLOS
- Apa: app ditulis ulang dari nol (Kotlin, tanpa AndroidX) dengan 4 tab
  DASH/GAMES/CUSTOM/TOOLS, UI dari kode, R8 + shrink. 377 KB (dari 2,3 MB).
- Bukti L1: CI GitHub Actions run 37106755499 SUCCESS (branch app-control,
  repo isac12345/Alpha). Verifikasi: package com.alphabubble,
  versionCode=20 (cocok ALPHA_COMPANION_VER), signed (apksigner verify),
  banner+ikon ada (res/8b.webp, res/3e.jpg), string 4 tab + apply_now.sh
  ada di classes.dex, nol dependency.
- Bukti L2: user pasang di HP — "jalan smua jir modenya". Semua tombol
  modul (profil, flag, log, render, resolusi) berfungsi.
- Catatan: versionCode sengaja 20 = sama dengan app lama, jadi WAJIB
  uninstall com.alphabubble dulu sebelum pasang (data app ikut hilang).
- File APK: ~/storage/downloads/AlphaControl-apk/AlphaBubble-v2.apk (377 KB).
