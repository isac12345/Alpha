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

## Investigasi Alpha Control (TAHAP 1, 2026-09-19, read-only + tes live aman)

Sumber kode: tag `backup-source-rebuild` (source lama). HP: Android 14, SDK 34
(`getprop ro.build.version.release`=14, `...sdk`=34). Resolusi native 720x1600, density 320.

1. Notifikasi/bubble — BELUM seperti B1:
- `AndroidManifest.xml:12` deklarasi POST_NOTIFICATIONS, tapi `git grep requestPermissions|ActivityCompat|checkSelfPermission` → NOL (tidak pernah diminta runtime).
- `FloatingBubbleService.kt:107-111` startForeground(NOTIF_ID=21) + channel `alpha_floating` IMPORTANCE_LOW (163-168). Isi STATIS (171-186): "Alpha Floating", aksi Tampilkan/Sembunyikan saja — tanpa profil aktif, tanpa aksi Battery/Balanced/Perf, tanpa deleteIntent.
- `ProfileMonitorService.kt:36-47,94-107` notifikasi "Alpha: <Profil>" + 3 aksi + tap→show bubble, poll `current_state` tiap 3 dtk (55-60). Hanya jalan bila `Prefs.isNotifEnabled` (default true, `Prefs.kt:72-73`).
- Batasan Android 14: notif FGS IMPORTANCE_LOW bisa di-swipe user; tanpa deleteIntent tidak bisa tampilkan ulang otomatis.
2. Resolusi — parser SALAH + tanpa feedback:
- `RootShell.kt:151-155` apply hanya `wm size WxH` (tanpa density); `:157-159` reset hanya `wm size reset` (tanpa density reset). `DisplayFragment.kt:355-370` reload label bila success, tanpa toast gagal/berhasil.
- `RootShell.kt:119-136` parse `dumpsys display | grep mDisplayWidth|...` — key TIDAK ADA di ROM ini (terbukti: perintah sama via su → kosong). Data nyata: `DisplayDeviceInfo{...720 x 1600...density 320}`, `mStableDisplaySize`, `supportedModes fps 60/90/120/144`.
- Tes auto-reset 432x960 (60%): `wm size` → `Override size: 432x960`, tapi dumpsys TETAP fisik 720x1600. Jadi parser dumpsys tidak bisa baca Override; fix harus parse `wm size` (Physical vs Override) + `wm density`. Reset terverifikasi kembali native (hanya Physical).
3. Dexopt — perintah sinkron, UX fire-and-forget:
- `RootShell.kt:161-163` = `cmd package compile -m $mode -f $pkg` (selalu -f). `SuExecutor.kt:57` waitFor tanpa timeout.
- `DexoptDialog.kt:44-50` panggil lalu abaikan hasil. Live `com.alphabubble`: before `[status=run-from-apk]` → Success 0.485s → after `[status=verify] [reason=cmdline]` (minta speed, dapat verify — kemungkinan karena `android:debuggable="true"` di manifest).
4. Profil per game — JALAN (event-driven): map `/data/adb/alpha/game_profile_map.conf` format `pkg:profil`; `monitor.sh` logcat events + fallback polling 7/60 dtk; tulis `current_state` via `apply_now.sh`. Tes `com.android.settings:performance`: buka→performance ~4 dtk (`APPLY-EVENT`), tutup→battery(manual) ~5 dtk. Daftar asli dikembalikan identik (3 entri), tidak ada sisa.
- BUG APP (bukan modul): `RootShell.kt:165-184` gameList baca `$modulePath/game_profile_map.conf` (TIDAK ADA di HP) dengan delimiter `=` (file nyata di `/data/adb/alpha/`, delimiter `:`). `removeGameFlow` (`:192-198`) tulis langsung file modul + `=`, bypass script. Akibat: daftar game di aplikasi tidak sinkron dengan modul.
5. `com.example.test` — TIDAK DITEMUKAN di: branch fusion-v2, tag backup-source-rebuild, `/data/adb/alpha/game_profile_map.conf` (isi: wobblylife, punishing grayraven, wutheringwaves), `games.toml` modul maupun `/sdcard/Android/fas-rs/games.toml`, `uperf.json`. Satu-satunya "example" adalah placeholder `com.example.game` di `item_game.xml:32` (teks preview layout, bukan data). Butuh info user: di layar mana melihatnya.
6. UI = XML (17 file `res/layout`, Activity+Fragment, `git grep compose` → nol). Background: XML default `centerCrop` (`fragment_home.xml:25`, `fragment_display.xml:41`); preview kode CENTER_CROP/FIT_CENTER (`DisplayFragment.kt:244`, `HomeFragment.kt:137`); tidak ada fitXY; simpan mentah tanpa crop (`DisplayFragment.kt:321-338`), downsample max 1080 (blur di layar 1600, bukan gepeng). DIVERGENSI: prefs HP pakai `app_bg_uri` (content URI) sedangkan source lama pakai `bg_image_path` (file) — APK terpasang LEBIH BARU dari source tag. Penyebab gepeng kemungkinan di kode baru → perlu decode APK via pipeline untuk bukti, atau screenshot user.

## Pipeline edit APK (`.github/workflows/apk-edit.yml`, 2026-09-19)

- Cara kerja: checkout → setup JDK 17 → install apktool rilis terbaru (via GitHub API, tanpa versi hardcode) → `apktool d companion/AlphaBubble.apk` (file asli tidak diubah) → timpa dengan `apk-overlay/` bila ada isi (rsync, `.gitkeep` diabaikan) → `apktool b` → `zipalign` → `apksigner sign` dengan keystore dari secret `KEYSTORE_B64` (decode ke `$RUNNER_TEMP`, PKCS12, alias `alpha`, password `KEYSTORE_PASSWORD`, secret di-mask, file sementara dihapus + always-cleanup, keystore tidak di-upload) → `verify --print-certs` → upload artifact `AlphaBubble-edited`.
- Temuan: `workflow_dispatch` 404 bila file workflow tidak ada di default branch (master) — diatasi dengan trigger `push` ke `fusion-v2` (paths: workflow, overlay, APK). Build-tools 37.0.0 menolak `--ks-pass:env`/`:file`; sintaks benar `--ks-pass env:KS_PASS` (spasi, sesuai `--help`).
- Smoke test rebuild-tanpa-perubahan (run 35428755191): verify SUKSES, 2.3M, cert SHA-256 `a0698c50…` BEDA dari kunci lama `48:74:…` (benar: kunci baru), package `com.alphabubble` versionCode `1` tetap sama.
- PENTING: aplikasi Alpha Control lama HARUS di-uninstall dulu sebelum pasang hasil pipeline, karena tanda tangan berubah (Android menolak update beda signer).

## Pipeline terintegrasi (package.yml, 2026-09-19)

- Alur: checkout → JDK 17 → apktool terbaru → cek `version.txt` vs `ALPHA_COMPANION_VER` (GAGAL bila beda) → decode APK repo (asli tak diubah) → overlay → patch `versionCode` apktool.yml dari version.txt → rebuild → zipalign → sign (PKCS12/alias alpha, secret mask+cleanup) → verify cert → aapt cek package + versionCode (GAGAL bila ≠ version.txt) → staging rsync (APK signed hanya di zip) → zip META-INF di root → upload.
- `version.txt`=2 (sumber tunggal; naikkan tiap APK berubah + samakan `ALPHA_COMPANION_VER`). APK di-zip: versionCode 2, package `com.alphabubble`, cert baru `a0698c50…`.
- Insiden: (1) `NumberFormatException "'2'"` — apktool 3 butuh bare int; (2) zip 20M — `apktool.jar` bocor dari root → pindah ke `work/tools/`; (3) `.gitignore` ikut ke-zip → exclude. Daftar file zip final IDENTIK dengan asli.
- Flag basi: `alpha_companion_install_once` dulu skip bila flag ≥ VER tanpa cek terpasang — uninstall lalu reflash = APK tak terpasang (flag di `/data/adb/alpha/.companion_installed` selamat dari uninstall). Fix: flag hanya fast-path bila dumpsys cocok; bila basi lanjut install ulang.
- Zip final: run 35429540702, `build-output/Alpha-Fusion-v2.zip` (5.4M). Link: https://github.com/isac12345/Alpha/actions/runs/35429540702
