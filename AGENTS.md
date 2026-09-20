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

## 3. Aturan direktur-pekerja (ARSITEKTUR 2026-09-20 malam)

- Kombo (terverifikasi via curl /v1/chat/completions, biasa + tools):
  Budak OK, Alpha-code OK, Alpha-code-b OK, Alpha-fast OK, Alpha-review OK.
  Via `opencode run`: Alpha-fast + Budak OK; Alpha-code/code-b/review GAGAL
  (`Unexpected server error`, berulang, dilaporkan, kombo tidak diubah).
- Agent: dev-smali + dev-java = Alpha-code; dev-modul + dev-res = Alpha-code-b;
  explorer + researcher + qa + ci = Alpha-fast; reviewer + debugger =
  Alpha-review; direktur = Budak. Semua mode `all`.
- Kepemilikan file: dev-smali (apk-patches/, overlay manifest), dev-java
  (java/), dev-res (apk-overlay/res/), dev-modul (common/, uperf/, fasrs/,
  skrip root, sandbox), qa (baca + tulis ~/work/qa/), ci (.github/,
  version.txt, module.prop, package.yml, dokumen serah-terima),
  reviewer/debugger/explorer/researcher (baca saja). Lintas kepemilikan
  dicatat di BOARD.md.
- Direktur tidak menulis kode: tulis brief berkriteria, tugaskan sesuai
  kepemilikan, gelombang maks 3 paralel, baca BOARD.md + report.md (bukan
  log), putuskan TERIMA / REVISI (maks 2 putaran) / KOREKSI KECIL (<=20
  baris) / ESKALASI (ulang model Alpha-review sebagai pekerja). Direktur
  kerjakan sendiri hanya setelah 2 putaran gagal terdokumentasi + error
  persis, hasil wajib diperiksa reviewer. Polling ≤1x/10 menit via
  ~/bin/tunggu. Alur: pekerja → qa → reviewer → direktur merge ke
  fusion-v2. Hanya direktur yang merge. Master tidak disentuh.
