# AGENTS.md — Aturan repo Alpha Fusion (modul Magisk)

## 1. Aturan build modul fusion-v2 (permanen, 2026-09-19)

- DILARANG menjalankan gradle, gradlew, npm install, apktool, atau build/compile apa pun di Termux. Semua kompilasi lewat GitHub Actions.
- Di Termux hanya boleh edit teks, git, dan gh.
- Alur tiap perubahan: edit, commit, push, gh workflow run, gh run watch, download hanya hasil akhirnya (zip/APK).
- Baca STATE.md, PLAN.md, dan NOTES.md di awal setiap sesi. Setelah tiap langkah selesai: update STATE.md, commit, push.
- Hapus APK/zip lama yang sudah tidak dipakai setelah versi baru terpasang.

## 2. Struktur modul

- Root repo = root modul Magisk. `META-INF/` harus langsung di root (dan di root zip rilis).
- `module.prop`: id=`alpha_uperf_fasrs_fusion`, versionCode wajib sinkron dengan `ALPHA_COMPANION_VER` di `common/companion_install.sh` dan `versionCode` aplikasi Alpha Control.
- Script `.sh` dan `META-INF/.../update-binary` wajib executable (`100755` di git) dan line ending LF.
- JANGAN commit `*.jks`, `*.keystore`, `*.apk`, `*.zip`, atau isi `build-output/`.
