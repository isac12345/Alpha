# PLAN.md — Alpha Fusion v2 (branch fusion-v2)

## Selesai (terverifikasi, run 35429540702)
- [x] Tree modul dari `Alpha-fusion-v2-final.zip` + `.gitignore` + `AGENTS.md` di `fusion-v2`.
- [x] Workflow `package.yml`: zip META-INF di root, exclude docs/`.opencode`/`build-output`.
- [x] Zip 5.4M terverifikasi: `module.prop` root ✓, `update-binary` ✓, sha256 APK = asli ✓, tanpa folder pembungkus.
- [x] Pipeline `apk-edit.yml`: rebuild + sign kunci baru (cert `a0698c50…` ≠ lama), smoke test SUCCESS.
- [x] Pipeline terintegrasi: `version.txt`=2 sumber tunggal, enforce vs `ALPHA_COMPANION_VER`, patch versionCode bare int (apktool 3), apktool di `work/tools/`, `.gitignore` di-exclude.
- [x] Fix flag basi `companion_install.sh` (uninstall→reflash tetap install ulang).
- [x] Versi sinkron: `module.prop` versionCode=2 = `version.txt` = `ALPHA_COMPANION_VER`.

## Laporan jalur (TAHAP 2, 2026-09-19 — investigasi selesai, BELUM eksekusi)

Legenda: (a)=overlay resource, (b)=patch smali kecil, (c)=butuh source Kotlin.
APK terpasang lebih baru dari source tag (prefs `app_bg_uri` vs `bg_image_path`) →
untuk (c), pertama decode APK via pipeline dan diff smali vs tag sebelum tulis kode,
supaya perilaku sama dengan APK asli. Tanpa decode, estimasi di bawah BISA meleset.

- B1 notifikasi ongoing+aksi+tap panel+deleteIntent+runtime permission: (c) — teks/aksi/channel hardcoded di Kotlin (`FloatingBubbleService.kt:171-186`, `ProfileMonitorService.kt:94-107`).
- B2 editor crop + photo picker + simpan internal: (c) — alur `copyImageToInternal` (`DisplayFragment.kt:321-338`).
- B3 Tools gaya Dashboard + dialog Dexopt: (a) — layout/drawable/style (`dialog_dexopt.xml`, `pill_solid`, font mono). AMAN, tapi butuh nama resource asli dari decode dulu (tanpa itu = menebak).
- B4 resolusi baca `wm size`/`wm density` + toast: (c) — `RootShell.displayInfo/applyDisplay/resetDisplay` + `DisplayFragment.kt:340-370`.
- B5 dexopt progres + opsi Paksa/Reset + before/after: (c) — `DexoptDialog.kt:44-50` + `RootShell.dexopt`.
- B6 profil per game (path + delimiter `=`→`:`): (c) ideal; (b) kandidat kecil (2 fungsi `gameList`/`removeGameFlow`) — putuskan setelah lihat smali hasil decode.
- F1 kustomisasi bubble (ukuran/bentuk/gambar/transparansi/preview/reset): (c).
- T1 satu sumber profil: (c) — `current_state` sudah ada; yang kurang sinkronisasi push ke notif/bubble/tile/Dashboard.
- T2 log (tap-full, waktu relatif, salin): (c); padding tombol log: (a).
- T3 kontras tab/padding/bahasa: (a); ikon+nama game (pola seperti picker Dexopt): (c).
- T4 countdown 15 dtk + auto-revert, konfirmasi Skia, root timeout + error jelas, hide Battery Lab: (c). Catatan: tombol Battery Lab TIDAK ADA di source lama (grep nol) — hanya di APK baru.
- T5 hapus `com.example.test`: data, bukan build — DITUNDA sampai lokasi terbukti (tidak ditemukan di repo/state/toml/uperf.json; butuh info user).

Usulan urutan aman: (1) decode APK via pipeline → artifact smali+resources (read-only, tanpa ubah kode); (2) kerjakan (a) B3+T3-res; (3) (b)/(c) setelah persetujuan per item. JANGAN mulai (c) sebelum setuju.

## Berikutnya (satu per satu)
- [ ] Tes flash `build-output/Alpha-Fusion-v2.zip` di HP (Magisk/KernelSU): cek boot, APK `com.alphabubble` versionCode 2 terpasang, uninstall-dulu bila signer lama.
- [ ] Setelah terpasang OK: hapus APK/zip lama tak terpakai (`app-debug.apk`, `AlphaBubble-edited.apk` bila tak perlu).
- [ ] Finalisasi keystore rilis (baca fingerprint dengan password; tentukan kandidat A vs B).
- [ ] Merge `fusion-v2` → master (BUTUH persetujuan user, jangan otomatis).
