# STATE.md — Alpha Fusion v2 (branch fusion-v2)

- Branch: `fusion-v2` (tracking `origin/fusion-v2`). Master TIDAK disentuh sejak backup.
- HEAD: tree modul dari `Alpha-fusion-v2-final.zip` (158 file) + `.gitignore` + `AGENTS.md`.
- Backup: tag `backup-source-rebuild` → master `efaa117` (sudah push). Stash `termux-workaround-mirror-timeout` masih ada.
- Sumber zip: `/sdcard/alpha/Alpha-fusion-v2-final.zip` (md5 `6c609177a75509104aa8d402f6017ee2`).
- APK asli: `companion/AlphaBubble.apk`, sha256 `159d4e771a6f1c0bd6ac480fa4f8f780eacb87c9f646d9d33a628a4daee89b48`.
- module.prop: id=`alpha_uperf_fasrs_fusion`, version=v2, versionCode=2.
- Sudah diverifikasi: exec bit + LF (script bersih, hanya biner + 1 md yang mengandung CR).
- Belum: workflow packaging, run Actions, verifikasi zip hasil, bersih cache.
- 2026-09-19: `.opencode/` disalin (AGENTS.md + agent/7 + skill/3 + command/5, 16 file, tanpa secret).
- 2026-09-19: workflow `.github/workflows/package.yml` dibuat (zip META-INF di root, exclude docs/.opencode/build-output, upload artifact). Validasi YAML lokal diskip (no pyyaml, dilarang install); run Actions yang memvalidasi.
- JANGAN merge ke master tanpa persetujuan user.
