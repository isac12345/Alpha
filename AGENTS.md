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

## 3. Aturan direktur-pekerja (ARSITEKTUR 2026-09-20, ROMBAK FASE 1 19:45)

- Status kombo (terverifikasi 19:45): Alpha-fast OK, Budak OK;
  Alpha-code + Alpha-review GAGAL (`Unexpected server error`, 3x tiap kombo,
  dilaporkan, tidak diubah sendiri). Selama keduanya gagal: pekerja code
  (dev-smali/java/res/modul) dan reviewer TIDAK bisa dipakai; qa (fast) BISA.
  Eskalasi: direktur kerjakan sendiri bagian kecil + catat alasan di STATE.md.
- Direktur (agent `direktur`, Budak) TIDAK implementasi kode. Tugas: tulis brief
  `/data/data/com.termux/files/home/work/tasks/<id>.md` (PATH ABSOLUT, daftar
  file eksklusif per pekerja), delegasikan via `~/bin/karyawan` (maks 2 paralel),
  baca laporan + diff, jalankan reviewer (git-only) + tester, putuskan
  TERIMA / REVISI (maks 2 putaran) / KOREKSI KECIL (~20 baris) / BUANG, catat di
  STATE.md, dan satu-satunya yang merge ke `fusion-v2`. Master tidak disentuh.
  Bila pekerja gagal 2 putaran, direktur boleh kerjakan sendiri + catat alasan.
- Review yang GAGAL dijalankan = "review GAGAL", DIULANG, jangan diganti
  pemeriksaan lain. Tiap item wajib punya review terbaca SEBELUM diterima.
- Pekerja paralel DILARANG mengedit file yang sama; bila tumpang tindih,
  kerjakan berurutan.
- Pekerja (`dev-apk`: java/smali/XML/workflow; `dev-modul`: shell/config/uperf/fasrs;
  `debugger`: crash) kerja HANYA di worktree `~/work/wt/<id>`, cabang
  `work/<id>-<suffix>` dari fusion-v2, commit trailer `Worker: <agent>`.
  DILARANG menyentuh fusion-v2/master. Lapor: ringkasan, `git diff --stat`,
  bukti, hal yang belum pasti.
- Pendukung: planner (sebelum brief), explorer (baca kode besar), researcher
  (docs resmi), reviewer (setelah lapor, sebelum merge), tester (verifikasi
  statis; tes perangkat hanya bila user mengetik "HP bebas"), critic (cek akhir).
- Build: Actions (`package.yml` jalan untuk `fusion-v2` + `work/*`); Termux hanya
  edit teks, git, gh. Version: `version.txt` = `ALPHA_COMPANION_VER` =
  `module.prop` versionCode, naik per build.
