# NOTES.md — Alpha Fusion v2 (branch fusion-v2)

## Keputusan

1. Repo `isac12345/Alpha` branch `fusion-v2` = source modul Magisk (bukan app source; app source tersimpan di tag `backup-source-rebuild`).
2. `.gitignore` menolak `*.apk`/`*.zip` KECUALI payload wajib: `companion/AlphaBubble.apk`, `uperf/modules/asoulopt.zip` (negasi `!`). Tanpa ini zip rilis gagal verifikasi sha256.
3. Keystore TIDAK di-commit (`*.jks`, `*.keystore`, `keystore.properties` di-ignore; `git ls-files` + `git log --all --name-only` bersih dari jks).
   Kandidat kunci rilis (BELUM final, fingerprint tak bisa dibaca tanpa store password):
   - A: `~/AlphaRebuild/alpha-release.jks` — alias `alpha`, dibuat 19 Sep 2026 (SETELAH zip final 18 Sep 22:19).
   - B: `/usr/tmp/opencode/alpha-release.jks` — alias `alpha`, dibuat 18 Sep 2026 (sehari dengan build APK).
   Keduanya: 1 entry PrivateKeyEntry, chain length 0 saat dibuka dengan password kosong (integrity NOT verified) → fingerprint sertifikat TIDAK tampil. APK asli terkonfirmasi via apksigner: SHA-256 `48:74:C0:7D:05:51:D2:AE:10:AA:D3:4C:46:7B:95:C5:B0:9C:52:FC:3E:93:72:9F:A9:8B:7E:8F:C7:BE:59:B0`. Secara timeline B lebih mungkin, tapi butuh password untuk bukti definitif (tidak ditebak).
4. Tidak ada build di Termux (aturan permanen). Hanya edit teks + git + gh.

## Temuan

- Zip sumber 171 entri (158 file): `META-INF/` di root (tanpa folder pembungkus), `module.prop` versionCode=2.
- `res/values/public.xml` + layout `notification_*` TIDAK ada di tree ini (itu masalah app source lama, sudah lewat).
- `file` tidak tersedia di Termux; cek CRLF via `grep -rl $'\r'` — bersih untuk semua script (hanya biner + `fasrs/README_CN.md` yang mengandung byte CR, tidak berpengaruh).
- `common/*.sh`: sebagian exec (100755), sebagian tidak (100644) — dipertahankan apa adanya sesuai zip.
- `~/Alpha-fusion-v2-final.zip` tak bisa di-md5 (permission media_rw); dipakai `/sdcard/alpha/` (md5 `6c609177...`).

## Verifikasi zip hasil (run 35427306606, 2026-09-19)

- `module.prop` di root zip ✓, `META-INF/com/google/android/update-binary` ada ✓.
- `companion/AlphaBubble.apk` di dalam zip: sha256 `159d4e771a6f1c0bd6ac480fa4f8f780eacb87c9f646d9d33a628a4daee89b48` — SAMA dengan APK asli.
- File pertama di zip: `uninstall.sh`, `module.prop`, `companion/` — tanpa folder pembungkus ✓. Tidak ada `AGENTS.md`/`STATE.md`/`PLAN.md`/`NOTES.md`/`.opencode`/`.github`/`build-output` di dalam (satu-satunya hit grep adalah path arsip itu sendiri).
- Link: https://github.com/isac12345/Alpha/actions/runs/35427306606
