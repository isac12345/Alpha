# PLAN.md — Alpha Fusion v2 (branch fusion-v2)

## Selesai (terverifikasi, run 35429540702)
- [x] Tree modul dari `Alpha-fusion-v2-final.zip` + `.gitignore` + `AGENTS.md` di `fusion-v2`.
- [x] Workflow `package.yml`: zip META-INF di root, exclude docs/`.opencode`/`build-output`.
- [x] Zip 5.4M terverifikasi: `module.prop` root ✓, `update-binary` ✓, sha256 APK = asli ✓, tanpa folder pembungkus.
- [x] Pipeline `apk-edit.yml`: rebuild + sign kunci baru (cert `a0698c50…` ≠ lama), smoke test SUCCESS.
- [x] Pipeline terintegrasi: `version.txt`=2 sumber tunggal, enforce vs `ALPHA_COMPANION_VER`, patch versionCode bare int (apktool 3), apktool di `work/tools/`, `.gitignore` di-exclude.
- [x] Fix flag basi `companion_install.sh` (uninstall→reflash tetap install ulang).
- [x] Versi sinkron: `module.prop` versionCode=2 = `version.txt` = `ALPHA_COMPANION_VER`.

## Berikutnya (satu per satu)
- [ ] Tes flash `build-output/Alpha-Fusion-v2.zip` di HP (Magisk/KernelSU): cek boot, APK `com.alphabubble` versionCode 2 terpasang, uninstall-dulu bila signer lama.
- [ ] Setelah terpasang OK: hapus APK/zip lama tak terpakai (`app-debug.apk`, `AlphaBubble-edited.apk` bila tak perlu).
- [ ] Finalisasi keystore rilis (baca fingerprint dengan password; tentukan kandidat A vs B).
- [ ] Merge `fusion-v2` → master (BUTUH persetujuan user, jangan otomatis).
