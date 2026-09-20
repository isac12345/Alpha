# STATE.md — Alpha Fusion v2 (branch fusion-v2)

- CHECKPOINT FINAL FASE 0 (2026-09-20 19:30, rincian ~/work/CHECKPOINT-final.md):
  Pekerja: NOL berjalan. HEAD=0944574. final-apk: A1+A3 SELESAI, A2 SEPARUH
  (bug toggle diperbaiki 0944574, review TERIMA; "berlaku langsung" jadi
  "berlaku saat dibuka ulang"). final-modul: M1,M2,M4-M7 SELESAI; M3 SEPARUH
  (GPU_MAX_FREQ tercatat tapi tune_gpu belum pakai); M8 SEPARUH (tanpa counter
  2x); M9 SEPARUH (sandbox 10/10 klaim pekerja; alpha-diag ditulis, tak
  dijalankan). Review M1-M9: GAGAL 3x, belum terbaca. Run: 5 terpakai.
  Serah-terima BELUM. FASE 1 rombak tim berikutnya.

- BUILD 15 (2026-09-20, TERIMA D+E, review terbaca):
  Audit b14: A1 SEBAGIAN (alpha/corner masih aktif), A2 a-c SUDAH + d BELUM
  (res60-100 mentah), A3 tombol galeri BELUM + chip SUDAH + dialog SEBAGIAN
  (radius tanpa density) + label SUDAH.
  Alur diperbaiki: brief path ABSOLUT, reviewer bash git-only (git diff/show/log
  allow, lain deny — terverifikasi), pekerja disjoint (D=java, E=XML).
  Review b14 yang GAGAL diulang TERBACA (temuan: radius tanpa density, dual key
  crop/uri, klaim ToolsKit tanpa bukti) → koreksi 1 blok (8d89df4).
  b15-d TERIMA (hapus alpha/corner apply, commit 891f126 + koreksi dead code
  7aea74e, review TERIMA); b15-e TERIMA (7 tombol pill monospace, bb27915,
  review TERIMA). Merge + bump 15 (945280d). Build 15 SUCCESS run
  `35502125769` (package) — anggaran tugas final: 2/10 run.
  APK `/sdcard/alpha/AlphaBubble-b15.apk` (`6b7c0e28...`, 2.3M) +
  ZIP `/sdcard/alpha/Alpha-Fusion-v1-b15.zip` (5.6M); b14 utuh.
  Tester 4/4 PASS statis. Worktree+cabang dihapus. BELUM tes HP. JANGAN merge master.
  Direktur: brief `~/work/tasks/b14-{bubble,restyle}.md`, 2 dev-apk paralel
  (worktree `~/work/wt/b14-{bubble,restyle}`, cabang `work/b14-*-dev`, trailer
  `Worker: dev-apk`), seleksi gabungan (konflik 1 blok di BSA diselesaikan
  manual, kedua sisi dipertahankan), merge f2a6cdb + bump 14 (2311e09).
  Build 14 SUCCESS run `35496819225`; APK `/sdcard/alpha/AlphaBubble-b14.apk`
  (`3e0fd5e4...`, 2.3M). Revisi: 0 putaran (keduanya TERIMA langsung).
  Turun tangan direktur: 1x (resolve konflik merge, ~15 baris).
  Bukti model (header log): dev-apk x2 = Alpha-think, reviewer = Alpha-think
  (gagal path), tester = Alpha-fast (PASS statis). Reviewer/tester gagal
  sebagian (path `~` + bash-deny) — direktur verifikasi sendiri (brace 65/65,
  48/48; pola OK; ver 13 sinkron sebelum bump). Worktree + cabang kerja
  dihapus. BELUM tes HP. JANGAN merge master.
  (Token konteks footer: tidak tersedia di CLI ini — tidak dicatat.)

- PERBAIKAN TIM KARYAWAN (2026-09-20, non-kode, sudah diverifikasi jalan):
  Model bawaan `9router/oc/mimo-v2.5-free`; agent plan=primary/Alpha-think;
  7 agent `~/.config/opencode/agent/*.md` mode all (think: planner/debugger/reviewer/critic,
  fast: explorer/tester/researcher); izin `external_directory ~/work/**`=allow.
  Uji: run bawaan OK, plan OK, debugger OK (Alpha-think), explorer via skrip OK
  (Alpha-fast, ISI=13), explorer ringkas 5 baris OK, reviewer temukan 2 bug ringkasan OK.
  Task-tool dalam sesi lama gagal (cache config sesi, mimo-auto) — sesi baru OK.
  Backup: `~/.config/opencode.bak-20260920-fix`. Detail tabel di NOTES.md.
  Perubahan STATE/NOTES ini BELUM di-commit (menunggu instruksi user).

- MODE DIREKTUR 2026-09-20: TAHAP 0 lolos (Alpha-think/fast + Budak ada).
  TAHAP 1 selesai (model agent, karyawan, aturan, tabel uji NOTES).
  DELEGASI GAGAL: `opencode run --agent <subagent>` → "agent is a subagent,
  not a primary agent" + model default mimo-auto Unsupported (log
  ~/work/logs/karyawan-debugger-*.log). Sesuai aturan: KERJA SENDIRI + catat.
  Semua tahap di bawah dikerjakan direktur langsung.

- Fix1 build 12 (2026-09-20): dexopt FC VerifyError TERBUKTI + DIPERBAIKI + TERVERIFIKASI HP (Canta, 89.788 dtk, dialog "Hasil dexopt", tanpa crash). Status get-compile-mode = Unknown command → fallback jujur. Screenshot b12-dexopt-done.png + dump v12-dexopt-done.xml.

- Branch: `fusion-v2` (tracking `origin/fusion-v2`). Master TIDAK disentuh sejak backup.
- HEAD: tree modul dari `Alpha-fusion-v2-final.zip` (158 file) + `.gitignore` + `AGENTS.md`.
- Backup: tag `backup-source-rebuild` → master `efaa117` (sudah push). Stash `termux-workaround-mirror-timeout` masih ada.
- Sumber zip: `/sdcard/alpha/Alpha-fusion-v2-final.zip` (md5 `6c609177a75509104aa8d402f6017ee2`).
- APK asli: `companion/AlphaBubble.apk`, sha256 `159d4e771a6f1c0bd6ac480fa4f8f780eacb87c9f646d9d33a628a4daee89b48`.
- module.prop: id=`alpha_uperf_fasrs_fusion`, version=v3, versionCode=3 (= version.txt = ALPHA_COMPANION_VER).
- Sudah diverifikasi: exec bit + LF (script bersih, hanya biner + 1 md yang mengandung CR).
- 2026-09-19: `.opencode/` disalin (AGENTS.md + agent/7 + skill/3 + command/5, 16 file, tanpa secret).
- 2026-09-19: workflow `.github/workflows/package.yml` dibuat (zip META-INF di root, exclude docs/.opencode/build-output, upload artifact). Validasi YAML lokal diskip (no pyyaml, dilarang install); run Actions yang memvalidasi.
- 2026-09-19: run `35427306606` (manual) + `35427296073` (push) → SUCCESS. Zip diunduh ke `build-output/Alpha-Fusion-v2.zip` (5.4M).
- Verifikasi: `module.prop` di root ✓, `META-INF/com/google/android/update-binary` ✓, sha256 `companion/AlphaBubble.apk` = `159d4e77...ee89b48` SAMA dengan asli ✓. Tidak ada folder pembungkus, tidak ada file exclude di dalam zip.
- 2026-09-19: bersih cache `~/.gradle` (20M) + `~/.cache` (11M). Protected (`~/.config/opencode`, `~/.config/gh`, `~/.ssh`, `~/storage`) utuh.
- 2026-09-19: cek keystore — keduanya alias `alpha`, fingerprint tak tampil tanpa password (Enter) → belum final; `.gitignore` + `keystore.properties`; git bersih dari jks.
- 2026-09-19: secret KEYSTORE_B64 + KEYSTORE_PASSWORD ada (secret lama diabaikan). Workflow `apk-edit.yml` dibuat + `apk-overlay/.gitkeep`.
- 2026-09-19: run `35428578321` GAGAL di step sign: `Unsupported option: --ks-pass:env` (build-tools 37.0.0; apktool rebuild SUKSES). Fix: password via `:file` (percobaan 1).
- 2026-09-19: run `35428651553` GAGAL juga: `Unsupported option: --ks-pass:file`. Diagnostik `--help` BT37: format benar `--ks-pass env:KS_PASS` (spasi, bukan titik-dua). Fix final (percobaan 2).
- 2026-09-19: run `35428755191` SUCCESS (rebuild tanpa perubahan). APK di `build-output/AlphaBubble-edited.apk` (2.3M): verify OK, cert baru `a0698c50…` ≠ lama, package/versionCode sama.
- 2026-09-19: sambung pipeline ke packaging — `version.txt`=2 (sumber tunggal), `package.yml` terintegrasi (decode→overlay→patch versionCode→sign→enforce→staging→zip), fix flag basi di `companion_install.sh` (uninstall→reflash).
- 2026-09-19: run `35429331531` GAGAL: `NumberFormatException: For input string: "'2'"` — apktool 3.0.3 mau versionCode TANPA kutip. Fix sed → bare number (percobaan 1).
- 2026-09-19: run `35429383410` SUCCESS tapi zip 20M — bocor `apktool.jar` root (15.5M) karena download di root. Fix: apktool ke `work/tools/` (tercover exclude `work/`).
- 2026-09-19: run `35429540702` SUCCESS. Zip final 5.4M di `build-output/`: daftar file identik asli, APK cert baru `a0698c50…`, package `com.alphabubble` versionCode 2 = version.txt = sh.
- v1 build 13 PERBAIKAN TES HP PIPELINE SUCCESS (run `35493343726`): dexopt Context signatures + status jujur + proporsional + slider + kartu + crop + pill. Bukti HP: dexopt Canta 89.788 dtk dialog "Hasil dexopt" tanpa crash (dump v12-dexopt-done.xml + b12-dexopt-done.png); BSA + RESET KE BAWAAN (b13-bsa.png); kartu BUBBLE + "Akses cepat ganti profil." (home5 + b13-homecard.png); picker terbuka (b13-picker.png) → STOP, PERLU TES MANUAL; PERALATAN + pill APPLY/RESET/DEXOPT (b13tools + b13-tools.png). Tanpa FATAL. File `/sdcard/alpha/AlphaBubble-b13.apk` (`41bec86e...`). BELUM lolos user. JANGAN merge master.
- v1 build 10 BATCH3 PIPELINE SUCCESS (run `35480723146`): C1 BubbleStyle + notif dinamis + crop UI + 7 kelas dex. Tes perangkat: STATIS SAJA (Chrome di depan, tes UI ditunda). File `/sdcard/alpha/AlphaBubble-b10.apk` + zip b10. BLOCKED: aksi profil per-item. BELUM tes user. JANGAN merge master.
- v1 build 9 BATCH2: tag `batch2-built`. File `/sdcard/alpha/AlphaBubble-b9.apk`. BLOCKED: render confirm.
- v1 build 8 BATCH1 PIPELINE SUCCESS (run `35478758890`): kartu BUBBLE Home + onboarding + guard BL + overlay kecil + hardening HelperGuard. Bukti: hook Batch1 OK, 4 kelas dex OK, versionCode 8, cert SAMA. alpha-test full install 6/7 (BubbleService mati wajar autostart off; retry hidup 7/7). Kartu BUBBLE tampil di UI dump. Zip `~/work/v8/Alpha-Fusion-v1.zip`, APK `88961b26...`, salinan `/sdcard/alpha/AlphaBubble-b8.apk` + zip. BELUM tes user. JANGAN merge master.
- v1 build 7 PIPELINE SUCCESS (run `35454848558`): 1 ikon LAUNCHER + shortcut Pengaturan Bubble + ikon notif monokrom ic_stat_alpha (0x7f05001a) + internal 7. Insiden: aapt2 tolak label shortcut literal → @string; badging tak list non-launcher activity → verify via xmltree. Zip `~/work/v7/Alpha-Fusion-v1.zip` (5.4M), APK sha256 `aa965a82...`, cert SAMA. BELUM tes HP. JANGAN merge master.
- v1 build 6 DONE PIPELINE (2026-09-19, run `35453438021` SUCCESS): BubbleSettingsActivity + nama v1 dikunci (module v1/6, APK v1/6, artifact Alpha-Fusion-v1.zip). Bukti: 2 kelas di classes5 OK, activity di manifest OK, versionCode 6, cert `a0698c50…` SAMA v3/v4/v6 (timpa tanpa uninstall). Zip `~/work/v6/Alpha-Fusion-v1.zip` (5.4M), APK sha256 `3d0da118...`. BELUM tes HP. JANGAN merge master.
- v4 DONE PIPELINE (2026-09-19, run `35451131225` SUCCESS): F2 HideFeedback (kelas Java javac+d8 → classes5.dex, hook 1 baris, VIBRATE di manifest) + B1 + bump v4. Bukti log: hook F2 OK, inject classes5.dex OK, HideFeedback di classes5.dex OK, versionCode 4, package OK. Insiden: d8 butuh mkdir output dir; sign env null (step terpisah tanpa env) → fix pisah step align+sign. Zip 5.4M `~/work/v4/Alpha-Fusion-v2.zip`, APK sha256 `fefc882b...`. BELUM tes HP. JANGAN merge master sebelum lolos HP.
- v3 DONE (2026-09-19, run `35445291496` SUCCESS): B1 Override-first regex-only (2 baris, grup unchanged) + manifest `POST_NOTIFICATIONS` + `debuggable=false` (nol dependensi debug di smali). B3 DILEWATI (tombol tanpa id). B2/F2 DITUNDA. versionCode 3 = version.txt = ALPHA_COMPANION_VER = module.prop. Zip 5.4M `~/work/v3/Alpha-Fusion-v2.zip`, APK sha256 `674df176...`. Tag `v3-tested` di `95685a2` (sumber zip, run 35445291496). Merge `fusion-v2` → `master` FF tanpa force (33 commit), master berisi modul + workflow apk-edit/decode/package (semua active). Hasil tes v3 di HP (laporan user): label resolusi benar, aplikasi normal.
- KONDISI SAAT INI (2026-09-19):
  - HEAD: `e75a3fe` (branch `fusion-v2`, sinkron dengan `origin/fusion-v2`). Working tree clean.
  - Decode ulang tersedia di `~/work/decode` (di luar repo, aman dari reboot). Jangan re-download kecuali perlu; perintah lama `/usr/tmp/opencode/decode` sudah tidak berlaku.
  - Temuan decode tercatat di NOTES.md § "Koreksi baseline dari smali APK asli" + PLAN.md § "Laporan jalur (TAHAP 2)". Rangkuman: APK = single-Activity programmatic (5040 baris smali), `BubbleService` (bukan Floating), TANPA `ProfileMonitorService`, TANPA `POST_NOTIFICATIONS`, prefs `app_bg_uri`. Game list SUDAH BENAR (`game_manager.sh` + JSON). Apply display SUDAH include density. Reset SUDAH reset keduanya. Long-press 800ms + persist `hidden` ADA (tanpa toast/vibrator). BatteryLab tanpa guard. Root tanpa timeout.
  - Jalur nyata: (a) overlay `res/`+`AndroidManifest.xml`, (b) patch smali kecil (perlu baca smali dulu), (c2) source Kotlin untuk fitur besar.
  - Pipeline terintegrasi `package.yml` berfungsi: zip v3 5.4M (`~/work/v3/Alpha-Fusion-v2.zip`), APK cert baru `a0698c50…`, package `com.alphabubble` versionCode 3 = version.txt = sh.
  - B1 DONE (Override-first), manifest overlay DONE. B3 dilewati, B2/F2 ditunda. Belum merge ke master. Flash + tes HP: OK menurut laporan user (belum ada angka label terverifikasi independen).
