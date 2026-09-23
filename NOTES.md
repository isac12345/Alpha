# NOTES.md — Alpha Fusion v2 (branch fusion-v2)

## Build 20 — fix radio Fill/Fit + cropRatio fallback (2026-09-22, leader + dev-apk 2 tugas)

Akar penyebab masing-masing:

1. Kedua radio tampak terpilih — kedua RadioButton dibuat via
   `new RadioButton(a)` TANPA ID (default NO_ID=-1), sehingga
   RadioGroup tak bisa menegakkan eksklusivitas; tambahan pula
   `rbFill.setChecked(true)` dipanggil SEBELUM addView (di luar
   RadioGroup). Akibat: `getCheckedRadioButtonId()` = -1 dan
   perbandingan `== rbFill.getId()` (-1==-1) selalu true. Fix:
   `setId(View.generateViewId())` untuk keduanya + `rg.check(id)`
   SETELAH addView (BgEditor.java, +3/-1). Bukan masalah
   drawable/selector (tak ada style kustom di overlay).
2. `cropRatio: metrics 0, fallback` pakai rasio salah — satu-satunya
   sumber metrics adalah `c.getResources().getDisplayMetrics()`;
   bila 0 (context belum attach / application context), fallback
   memakai outWidth/outHeight atau ukuran sumber (bisa persegi).
   Fix (BubbleStyle.java, +68/-6): rantai berlapis decorView
   Activity (getRealMetrics) → WindowManager.getDefaultDisplay →
   Resources context → `Resources.getSystem()` (rasio device
   sebenarnya, mis. 720x1600) → total-gagal pakai outWidth/outHeight
   HANYA sebagai ukuran output. Tiap fallback melog Log.w eksplisit
   (`metrics ctx 0, pakai system WxH` / `metrics TOTAL 0, output
   paksa WxH`); jalur total-gagal + Toast.LENGTH_LONG. Signature +
   logika FILL/FIT/letterbox tak tersentuh.
- Verifikasi leader: diff 2 file disjoint; brace balance OK (delta
  paren -5 = 5 komentar bernomor `// N)`); import View sudah ada;
  kedua commit di work/b20-bgfix, merge --no-ff 7c43a63 tanpa
  konflik. Bump 3 file ke 20 (version.txt 18→20, module.prop 19→20,
  ALPHA_COMPANION_VER 18→20).
- Bukti CI: run 35672669126 SUCCESS (package 34 dtk: javac semua
  java/ + d8 + rebuild + sign + enforce versionCode 20).
- Status: fusion-v2 sudah push. Verifikasi HP ikut CEK_TES-b20.md
  (radio visual, logcat tanpa "metrics 0", Fill penuh 720x1600).

## Build 19 — restart fas-rs di live merge (2026-09-22, leader + dev-modul)

- Akar penyebab: do_live_merge() (b18) menulis games.toml baru TAPI
  fas-rs yang sedang berjalan tidak membacanya — README_EN.md:141
  ("merged config ... will replace ... on the next restart"). Fix:
  setelah merge sukses, killall fas-rs + relaunch `run` (flag persis
  service.sh thp 9 / engine_manager.sh apply_and_restart,
  RUST_BACKTRACE=1 nohup >> fas_log.txt &), tanpa sleep (jeda ms).
  Koreksi leader: restart HANYA bila instans berjalan (pidof/killall);
  bila mati → lewati + log (jangan start di device yang service.sh
  sengaja lewati karena API/kernel). PID lama+baru dicatat di log.
- Bukti: sandbox stub — daemon 25606 mati, 25680 hidup, target toml
  ter-update, log `restarted old_pid=25606 new_pid=25680`. sh -n OK,
  shellcheck 0. Modul-only: APK tetap v18 (version.txt +
  ALPHA_COMPANION_VER tak berubah); module.prop 18→19.
- Status: merge --no-ff ke fusion-v2, push → CI (b19). Verifikasi HP:
  catat PID fas-rs sebelum/sesudah add/remove (HARUS berubah) +
  CEK_TES-b18 poin 1-2.

## Build 18 — 3 perbaikan bug + koreksi leader (2026-09-22, leader + dev-modul 2 tugas + dev-apk 1 tugas)

Akar penyebab masing-masing (bukan cuma "sudah diperbaiki"):

1. game_add hanya efektif setelah reboot — merge `fas-rs merge ... >
   .update_games.toml` HANYA ada di service.sh (tahap boot 9), sedangkan
   game_add.sh cuma `touch .need_merge` lalu selesai. Jadi games.toml di
   /sdcard tidak berubah sampai boot berikut. Fix: helper `do_live_merge()`
   di game_add.sh menjalankan perintah merge yang SAMA persis, dipanggil
   dari do_add + do_remove; gagal = warning, operasi utama tetap sukses.
   Koreksi leader susulan: `grep -v ... && mv` di do_remove GAGAL menghapus
   entri TERAKHIR (grep exit 1 bila output kosong → mv tak jalan; map masih
   berisi paket yang sudah di-remove → monitor tetap anggap performance).
   Pola sama di hapus-toml repo. Fix: mv tanpa && (seperti do_add).
   Bukti: sandbox stub fas-rs — add→target ADA+flag habis, remove→target
   HILANG+map kosong, binary hilang→warn+tambah tetap OK. sh -n OK,
   shellcheck 0.
2. gb_apply tak pernah jalan di monitor — service.sh me-source gameboost.sh
   di PROSES service, tapi monitor.sh jalan sebagai PROSES TERPISAH
   (`nohup sh monitor.sh`) yang tak pernah source gameboost.sh, sehingga
   `command -v gb_apply` selalu gagal diam-diam (tanpa else/log).
   Fix: source `$MODDIR/gameboost.sh` di awal monitor.sh (aman: top-level
   hanya assignment + def fungsi, tanpa efek samping; LOG_FILE di-save/
   restore) + `else monitor_log WARN` di semua 7 guard. Bukti: emulasi
   blok source — gb_apply/gb_restore ter-resolve, LOG_FILE utuh, kasus
   file-hilang melog WARN; shellcheck delta hanya +1 SC1091 info.
3. cropSquare paksa 1:1 — `side=min(w,h)` + scale ke sizePx², sedangkan
   alur background nyata (BgEditor) sudah rasio-layar. Fix: `cropRatio()`
   baru (baca displayMetrics widthPixels/heightPixels; FILL=crop tengah
   +scale penuh; FIT=scale min+letterbox hitam) + cropSquare jadi wrapper
   deprecated; version.txt+module.prop 17→18. Koreksi leader: pekerja
   LEWATKAN `ALPHA_COMPANION_VER=17` di companion_install.sh (lokasi versi
   ke-3; CI package.yml GAGAL bila ≠ version.txt) → disamakan ke 18.
   Bukti: grep pola persegi NOL, metrics ADA, 18 di 3 file.
- PELAJARAN: bump versi = 3 file (version.txt + module.prop +
  ALPHA_COMPANION_VER di companion_install.sh) — jadikan checklist di
  setiap brief bump. Polusi uji pekerja (com.test.newgame di
  fasrs/games.toml worktree gamemerge) — enforce `git status` bersih dari
  file di luar tugas sebelum merge.
- Status: 3 merge --no-ff ke fusion-v2, push → CI package.yml (b18).
  Verifikasi live (fas-rs pegang/lepas game, GAMEBOOST APPLIED +
  node berubah, crop Fill/Fit) = tugas user di HP ikut CEK_TES-b18.md.

## Porting Extreme HSIN b17 (2026-09-21, leader + dev-modul P1/P2/P3, dev-apk 2x cancel)

- Sumber: HSIN-v4.2.6-fixed.zip. JUJUR: core/extreme.sh v4.2.6 JUGA
  terkontaminasi 9router-sync (bukan cuma v4.2.5) — inventaris dari
  engine.sh (7299 baris) + game/protect/monitor + extreme.sh v4.2.7
  (bersih) + profiles/*.conf. Temuan: conf swappiness=10 DEAD (engine
  pakai tabel HSIN_VM_SAFE: 40/200/10/1/0) — Alpha ikut engine (40).
- HP live (T615 ums9230, BUKAN T7250): policy0 0-5 (614400-1612000),
  policy6 6-7 (768000-1820000), gov uscfreq (tak disentuh); GPU Mali
  23100000.gpu 384-850M + kbase; sched_latency_* TAK ADA (proc/debugfs);
  stune TAK ADA; power_policy/dvfs/js TAK ADA; net TANPA bbr (reno cubic);
  IO sda/sdb/sdc (tanpa mmcblk0); fas-rs+uperf+asoulopt hidup.
- Desain: CPU = LANTAI 65% (tak ada lock/governor, fas-rs/uperf hidup);
  EXTREME→fas-rs fast, BALANCED→balance, DAILY→powersave; DAILY=max 75
  (internal battery, label DAILY di APK overlay); game→balanced promote
  + grace 12 dtk; guard 75/85/95 + baterai 30/15 + loadavg + cooldown 60s.
- AsoulOpt: binary hardcoded 270 paket (WuWa global ADA, PGR EN TIDAK);
  tak bisa ditambah — wrapper game_add.sh ke games.toml+uperf+map saja.
  games.toml bawaan tak ada PGR EN/WuWa global.
- Verifikasi live per-tweak (su): apply→nilai berubah, restore→persis.
  NOL FAILED setelah fix equiv kernel (6-7/60.00/[mq]/max) + backup
  kbase+IO + mode fast/restore + unforce + cooldown 4 tick + grace daily.
  Skenario thermal/grace harness 5/5 PASS. Freq range utuh (min≠max).
- PEKERJA: dev-apk 2x cancel (jaringan) → label DAILY 1 baris oleh leader.
  P3 arg order vs APK (add pkg profile fps) → kompatibel dua arah + remove.
  P2 promote menelan performance-game + cooldown 900s + grace tanpa
  restore → dibetulkan leader + diverifikasi ulang via harness.

- Berlaku SEMUA game + SEMUA device (generic, node tak ada di-skip).
- Isi: common/gameboost.sh (gb_apply/gb_restore, native_boost.conf sekali,
  tulis-baca-verifikasi 2x, GAMEBOOST_LEVEL extreme default, sakelar
  DISABLE_GAMEBOOST/NO_CPUSET/GAMEBOOST_NO_VM, CPU skip bila fas-rs);
  monitor grace 12 dtk + transient-ignore + thermal 75/85/95C + baterai<15% +
  auto-kembali 70C/60s; SF_LATCH opt-in (hapus dari system.prop);
  bin/pgr-log CSV 1 dtk/30 mnt; CEK_PGR.md 10 baris.
- Referensi: /sdcard/alpha/HSIN-v4.2.5-consolidated.zip core/extreme.sh
  TERKONTAMINASI (isi 9router-sync, bukan HSIN) — otoritas = spesifikasi
  tugas; fallback baca /sdcard/Hsin/HSIN-v4.2.7-fixed.zip. Snap
  hsin-extreme/alpha TIDAK ADA di /sdcard/alpha (perbandingan snap dilewati).
- Sandbox T4: 26 PASS klaim pekerja; leader verifikasi independen (a)
  roundtrip apply→restore identik + (c) fas-rs CPU untouched. Fix leader-
  terima 18+/6-: pola governor `case " $_govs "` + backup min_freq/child_runs_first.
- Koreksi leader susulan (57b7e32, terverifikasi sandbox): PREFIX untuk
  cpuset/cpuctl/stune/debugfs/ged/battery (sebelumnya hardcode, tak bisa
  diuji sandbox) + tulis/hapus $CONF_DIR/boost_level agar kolom boost
  pgr-log terisi (sebelumnya tidak ada yang menulisnya).
- PELAJARAN: pekerja T3 tulis test/ + unit-tests.yml + edit PLAN/STATE
  langsung di repo utama (langgar AGENTS p7 + luar tugas) — dikembalikan
  (revert + hapus untracked), tidak di-merge. Laporan T3 juga salah isi
  (klaim Java tests) padahal file benar — JANGAN percaya laporan, cek diff.

## Build 16 — 4 perbaikan APK (2026-09-21, leader + dev-apk work/b16-fix)

Hasil: run `35561861525` SUCCESS. APK `/sdcard/alpha/AlphaBubble-b16.apk`
(`19ac2519`, 2.3M, versionCode 16, cert SAMA `a0698c50`, CardAlpha =
kelas ke-9). Gagal dulu `35561280307` (b9a `{p4}` = v24 invalid di fresh
decode → ganti `{v8}`, rebuild OK). Bukti akar per perbaikan (decode
`~/work/decode`, diverifikasi ulang pasca-fix via simulasi sed):
1. Kartu: `card_bg.xml` solid `@color/alpha_dark` (#0a0a0a, colors.xml:6) +
   kartu HomeCards #1e1e1e (HomeCards.java:238); slider lama (`onCreate$23`)
   DEAD code (tak diinstansiasi) + `app_bg_alpha` hanya dibaca
   `applyAppBackground` → slider dialihfungsikan aman. Alpha via
   `GradientDrawable.setAlpha` (drawable saja, teks utuh), key baru
   `card_alpha_pct`, hook onCreate-setTab (b16a) + refreshAll 2x (b16b).
2. Bubble: `onStartCommand` (BubbleService.smali:2053-2110) hanya tangani
   TOGGLE; REFRESH jatuh ke `:cond_0` (inilah "cache": bukan field static —
   grep static scale/size NOL — melainkan intent tak ditangani + toggle
   hanya visibility; force-stop segar via attach→applyLook→prefs).
   Fix b16c: cek REFRESH di titik p1=action String (v0 mati), →applyLook.
3. Dexopt: kedua tombol listener null (MainActivity.smali:1946-1952);
   hanya COMPILE(-0x1) dipasangi listener (:2064-2123)→lambda$31; hook lama
   di pemanggil openDexopt bikin progres muncul saat dialog dibuka (= yang
   terlihat "BATAL menjalankan compile"). Fix b9a: dexoptStart pindah ke
   lambda$31 (.line 217, register v8).
4. Dialog: `ToolsKit.styleDexoptDialog` (bg #1e1e1e radius 12*d +
   pill 24*d monospace, tombol dipost pasca-show) via b16d (show()V unik 1x);
   `styleDialog` kini pakai density; OK "Hasil dexopt" di-pill pasca-show.
Pelajaran sed (2 bug fatal pola pekerja, keduanya lolos "verifikasi" pekerja):
(a) `\n` di POLA tak pernah match (pattern space 1 baris) — wajib anchor
1 baris (b16b: refreshAll 2x, keduanya valid); (b) `\(` di BRE = grup,
bukan kurung literal — pakai `()` polos (lih. f2/b10a).
Insiden: 4x dispatch dev-apk "Task cancelled" (jaringan) tapi task tetap
jalan di background (worktree+cabang sudah dibuat attempt pertama, 5 commit
mendarat). Model dev-apk tak teridentifikasi (tanpa header log).

## TIM v1 — penyederhanaan (2026-09-21)

- Tim: 1 leader + dev-apk + dev-modul (rujukan: AGENTS.md).
- Total 12 skill; versi v1.
- Tanpa sentuh perangkat (hanya edit teks, git, gh).

## Build 15 — audit b14 + D/E (2026-09-20)

Audit statis b14 (langsung, direktur):

| Poin | Status | Bukti |
|---|---|---|
| A1 bubble bawaan, hanya ukuran | SEBAGIAN | scale+clamp OK (BubbleStyle.java:65-66); tapi `setImageAlpha` (:100) + `setClipToOutline` (:102) masih aktif |
| A2a slider baca tersimpan | SUDAH | prefs baca + clamp (BubbleSettingsActivity.java:197-198) |
| A2b tulis tiap geser | SUDAH | onProgressChanged tulis prefs (:96-98) |
| A2c refresh pasca-reset | SUDAH | reset panggil refreshSlider (:116-117) |
| A2d tombol persen XML | BELUM | res60-100 tanpa fontFamily/background (activity_main.xml:66-70) |
| A3 tombol galeri/banner | BELUM | btnAppBackground/Default tanpa gaya (:60-61) |
| A3 chip seg profil | SUDAH | segBattery dkk benar (:24-26) |
| A3 dialog crop | SEBAGIAN | monospace+radius OK, tapi radius tanpa ×density (BgEditor.java:181) |
| A3 label slider | SUDAH | tvSizeValue + refreshSlider (:86-90, :194-204) |

Dikerjakan: b15-d (A1 → skala-only, hapus alpha/corner apply + dead code)
+ b15-e (A2d/A3 → 7 tombol pill monospace). File disjoint: D=java, E=XML.
Review: b14 diulang TERBACA (radius bug, dual key app_bg_crop/app_bg_uri,
klaim ToolsKit tanpa bukti) → koreksi 8d89df4. D TERIMA + koreksi dead code.
E TERIMA. Tester 4/4 PASS. Run tugas final: 2/10
(`35501446870` aturan, `35502125769` build 15).
Diketahui belum dikerjakan: ToolsKit.styleDialog radius juga tanpa ×density
(ToolsKit.java:107) — pola sama, untuk build berikut.

## Arsitektur direktur-pekerja + pilot build 14 (2026-09-20)

- Direktur (`direktur`, 9router/Budak): brief, delegasi, seleksi, merge. Pekerja:
  `dev-apk` + `dev-modul` (9router/Alpha-think). Pendukung: planner/explorer/
  researcher/tester/reviewer/critic. Backup config: `~/.config/opencode.bak-20260920-arsitek`.
- `~/bin/karyawan` terima `--branch` + `--worktree` (validasi cabang worktree),
  log `~/work/logs/`, maks 2 paralel, cek baterai/game seperti sebelumnya.
- `package.yml` trigger `fusion-v2` + `work/*`. Total run tugas ini: 4
  (1 aturan + 2 cabang kerja + 1 build 14) dari batas 8.
- Pilot b14: bubble (refreshSlider + label % + refresh pasca-reset, 27+/5-)
  + restyle (pill-outline, dialog BgEditor monospace/radius 24, 70+/2-).
  Merge f2a6cdb (konflik 1 blok, resolve manual ~15 baris) + bump 14 (2311e09).
  Run `35496819225` SUCCESS; APK `/sdcard/alpha/AlphaBubble-b14.apk` (`3e0fd5e4...`).

| Agent | Mode | Model | Uji |
|---|---|---|---|
| direktur | primary | 9router/Budak | OK (`run --agent direktur`) |
| dev-apk | all | 9router/Alpha-think | OK (b14 x2, header log `dev-apk · Alpha-think`) |
| dev-modul | all | 9router/Alpha-think | OK (`run --agent dev-modul`) |
| reviewer | all | 9router/Alpha-think | GAGAL: baca `~/...` (path tak resolve) + coba `bash` (deny) |
| tester | all | 9router/Alpha-fast | OK header, verifikasi lewat (`git show`/read); tanpa compile |
| explorer | all | 9router/Alpha-fast | OK (uji sebelumnya) |

- Gagal + error persis: reviewer `Read ~/work/tasks/b14-bubble.md failed —
  File not found: .../AlphaRebuild/~/work/tasks/b14-bubble.md` dan
  `Invalid Tool ... Model tried to call unavailable tool 'bash'`.
  Perbaikan: beri path absolut di tugas reviewer/tester; ingatkan pendukung
  read-only agar tidak memanggil bash/git.
- Revisi per item: b14-bubble 0, b14-restyle 0. Direktur turun tangan: 1x
  (resolve konflik). Master tidak disentuh. BELUM tes HP.

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

## Tambahan 2 — analisis R1/F2 (2026-09-19, read-only, BELUM eksekusi)

R1 (resolusi+DPI otomatis) — semua poin = jalur (c), kode baru di `RootShell` + `DisplayFragment` + prefs baru:
- Acuan asli belum ada → simpan sekali saat deteksi pertama (fisik dari `wm size` Physical + `wm density` Physical). Persen selalu relatif ke acuan (anti-menumpuk).
- Rumus: w/h = genap terdekat dari (asli×p%), dpi = bulat(asli×p%) bila saklar nyala (default); bila mati → input manual dalam batas sistem (cek `wm density` range valid, tolak di luar).
- Preview SEBELUM Apply + nilai aktif sistem SESUDAH (baca `wm size`/`wm density`, bukan dumpsys).
- Countdown 15 dtk + auto-revert ukuran+DPI sekaligus; RESET NATIVE = `wm size reset` + `wm density reset`.
- PERSISTENSI REBOOT — TERBUKTI YA: saat override 432x960, `settings get global display_size_forced` → `432,960` (tersimpan di Settings.Global → bertahan reboot); sesudah reset → kosong, `wm size` native. Artinya tanpa penanganan, override ikut reboot; modul/service saat ini tidak menyentuh wm sama sekali → perlu kebijakan (re-apply setting user vs reset native saat boot).
F2 (bubble disembunyikan) — sebagian ADA di source lama, kurangnya = jalur (c):
- ADA: long-press >800ms → haptic + hidden=true + persist `hidden` (`FloatingBubbleService.kt:410-417`); `hapticFeedback()` 30ms (`:747-754`); `applyVisibility()` (`:701-703`); aksi TOGGLE/SHOW (`:114-128`).
- KURANG: (1) tanpa ambang gerak — drag lambat >800ms ikut menyembunyikan (konflik gesture); (2) tanpa toast; (3) `hidden` TIDAK dibaca saat service start (hanya di intent TOGGLE/SHOW) → setelah reboot bubble muncul lagi walau sebelumnya disembunyikan (`BubbleBootReceiver.kt:10-18` hanya cek autostart); (4) notifikasi tidak tahu status hidden (teks/aksi statis); (5) tap body saat ini unhide, bukan buka panel profil; (6) tanpa saklar di pengaturan.
- Peringatan divergensi tetap berlaku: APK terpasang lebih baru dari tag (prefs `app_bg_uri`), jadi peta baris di atas acuan awal — wajib decode via pipeline sebelum tulis kode.

## Koreksi baseline dari smali APK asli (decode run 35436973720, 2026-09-19)

Decode `companion/AlphaBubble.apk` (43M di `/usr/tmp/opencode/decode`, luar repo, jangan commit).
Fakta arsitektur: single-Activity programmatic (`MainActivity.smali` 5040 baris, NOL `*Fragment*.smali`),
`BubbleService` (bukan Floating), `ProfileTileService`, TANPA `ProfileMonitorService`.
Manifest APK: 7 permission, TANPA POST_NOTIFICATIONS (beda dari manifest tag).
`MainActivity` pakai key `app_bg_uri`/`app_bg_alpha` (cocok prefs HP) — tag (`bg_image_path`, Fragment) MENYIMPANG:
analisis TAHAP 1 dari tag hanya acuan awal, yang berlaku di bawah ini.
- Resolusi: `RootShell.displayInfo` SUDAH baca `wm size`+`wm density` (regex Physical saja — Override belum);
`applyDisplay` = `wm size WxH; wm density D`; `resetDisplay` = keduanya di-reset. UI: preview "%, DPI", tanpa countdown
(`grep pertahankan|countdown` nol), tanpa saklar DPI/manual, tanpa even-rounding (0 `and-int`).
- Game: `gameList`/`removeGameFlow` LEWAT `game_manager.sh`+`game_add.sh` + parse JSON (`parseGameArray`) — bug path+delimiter
dari tag SUDAH TIDAK ADA di APK. Monitor terbukti jalan (tes live).
- Dexopt: mode speed/everything/verify/space/speed-profile, selalu ` -f `; UI programmatic (`openDexopt`), tanpa progres/durasi.
- Bubble: long-press 800ms + persist `hidden` ADA; TANPA vibrator/toast (`grep VibrationEffect|Toast` nol).
- BatteryLab: explicit intent tanpa guard (`openBatteryLab`, fallback Settings); tombol selalu tampil (`activity_main.xml:92`).
- Root: hanya `waitFor`, tanpa `withTimeout` di mana pun.
- `com.example.test`: tetap tidak ditemukan di smali/res/state/toml/uperf.json.
KESIMPULAN JALUR: (c)-via-tag GUGUR (arsitektur beda). Jalur nyata = (a) overlay `res/`+`AndroidManifest.xml`,
(b) patch smali. Fitur besar baru (editor crop, countdown UI, photo picker) via smali = tidak layak;
opsinya (c2) tulis ulang source menyamai perilaku (usaha besar, perlu persetujuan + spesifikasi perilaku dari smali).

## Pipeline edit APK (`.github/workflows/apk-edit.yml`, 2026-09-19)

- Cara kerja: checkout → setup JDK 17 → install apktool rilis terbaru (via GitHub API, tanpa versi hardcode) → `apktool d companion/AlphaBubble.apk` (file asli tidak diubah)

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

## v3 tested + merge master (2026-09-19)

- Sudah: B1 patch 2 baris + manifest overlay + bump v3 + tag `v3-tested` + merge FF ke master (workflow apk-edit/decode/package active di master).
- Hasil tes HP (laporan user): label resolusi benar, aplikasi normal.
- Belum: B2 (timeout root, TUNDA), B3 (guard BatteryLab, DILEWATI — tombol tanpa id), F2 vibrator/toast (uji coba terpisah, perlu persetujuan), keystore final (fingerprint belum dibaca).
- Usulan berikut (belum mulai): T4 countdown 15 dtk APPLY RES, B5 dexopt progres+hasil (cek status speed-profile, APK kini debuggable=false).

## v1 build 6 (F2-T1 BubbleSettingsActivity, 2026-09-19)

- Skema versi dikunci: nama versi v1 di mana-mana (module.prop `version=v1`, APK versionName v1 bawaan apktool, artifact `Alpha-Fusion-v1.zip`). versionCode internal = 6 (= version.txt = ALPHA_COMPANION_VER) agar companion_install ganti APK lama. Nomor build dicatat di sini, bukan di nama versi.
- Isi: BubbleSettingsActivity (saklar tampilkan bubble, resync tanpa listener, overlay-perm saat ON, tema dashboard, Log.w) + activity LAUNCHER "Alpha Bubble" + classes5.dex berisi 2 kelas.
- Saklar Notifikasi DITUNDA (FGS wajib notifikasi di 12+).

## v1 build 7 (1 ikon + shortcut + ikon notif, 2026-09-19)

- Skema versi: nama v1, internal 7 (= version.txt = ALPHA_COMPANION_VER = module.prop), artifact `Alpha-Fusion-v1.zip`.
- Isi: B1 hapus LAUNCHER BubbleSettingsActivity (exported=false) + shortcut "Pengaturan Bubble" via `res/xml/shortcuts.xml` + `@string/bubble_settings_shortcut` (aapt2 menolak literal); B2 vector monokrom `ic_stat_alpha` id `0x7f05001a`, patch 1 konstanta `setSmallIcon`.
- Insiden: badging tak list non-launcher activity → verify activity via xmltree.
- Status: pipeline SUCCESS (run `35454848558`), zip `~/work/v7/Alpha-Fusion-v1.zip`, BELUM tes HP, JANGAN merge.

## v1 build 8 Batch 1 (kartu BUBBLE + onboarding + guard BL, 2026-09-20)

- Isi: HomeCards.java (kartu + onboarding + guard BL via HelperGuard) + hook onCreate/onResume (tanpa .locals) + overlay (tab GAMES kontras, btnLogAll padding, btnBatteryLab id 0x7f06009c) + hardening (Throwable + kill-switch).
- Insiden alpha-test: cp langsung ke /data/local/tmp gagal (Permission denied) → via /sdcard + su cp; BubbleService tidak terdaftar saat autostart off (wajar) → start manual → retry 7/7.
- Bukti: hook Batch1 OK, 4 kelas dex OK, versionCode 8, cert SAMA. Kartu BUBBLE tampil di dump UI. Zip `~/work/v8/Alpha-Fusion-v1.zip`, APK `88961b26...`.
- BELUM tes user. JANGAN merge master.

## v1 build 9 Batch 2 + build 10 Batch 3 (2026-09-20)

- Build 9 (run `35480098420`): ToolsKit (dexopt progres+hasil, countdown revert 15 dtk) + 3 hooks + restyle Tools. BLOCKED: render confirm. Tag `batch2-built`. APK `/sdcard/alpha/AlphaBubble-b9.apk` (`99d4c1c9...`).
- Build 10 (run `35480723146`): BubbleStyle + DynNotif + crop UI + 2 hooks, 7 kelas dex, versionCode 10. BLOCKED: aksi profil per-item. Tag `batch3-built`. APK `/sdcard/alpha/AlphaBubble-b10.apk` (`83df3047...`).
- Tes perangkat build 10: STATIS SAJA (Chrome di depan saat build selesai; tes UI + install ditunda). alpha-test penuh dijadwalkan serah-terima bila layar aman.
- Cert SAMA semua build (timpa tanpa uninstall).

## v1 build 13 perbaikan tes HP (2026-09-20)

- Run `35493343726` SUCCESS: 8 kelas dex, versionCode 13, cert SAMA. APK `/sdcard/alpha/AlphaBubble-b13.apk` (`41bec86e...`).
- Fix1 dexopt FC: VerifyError v1 Context vs Activity (`MainActivity$openDexopt$3$1$1$1$1`, log 09-20 PID 22101) → signature Context + cast + main looper. TERVERIFIKASI HP: Canta 89.788 dtk, dialog "Hasil dexopt", tanpa crash. Status get-compile-mode = Unknown command → fallback jujur (mode sukses / "?").
- Fix2 bubble proporsional (setScaleX/Y, tanpa paksa persegi) + clamp 60-140% + RESET KE BAWAAN (dump BSA + screenshot b13-bsa.png).
- Fix4 kartu: "Akses cepat ganti profil." + GradientDrawable membulat (dump home5 + b13-homecard.png).
- Fix5 crop: hook handlePick + gravity CENTER; picker terbuka (screenshot b13-picker.png) → STOP, PERLU TES MANUAL lanjut (pilih gambar + crop + simpan).
- Fix6 pill: APPLY RES/RESET NATIVE/DEXOPT gaya pill_outline + monospace (dump b13tools + b13-tools.png).
- Fix3 aksi Pengaturan: sudah ada dari build 10, belum ditekan (butuh buka notifikasi shade manual).
- BELUM lolos user. JANGAN merge master.

## Uji model Budak (2026-09-20, TAHAP 1)

| Model | Agent uji | Tugas | Hasil |
|---|---|---|---|
| 9router/Alpha-fast | explorer | baca version.txt | OK, tanpa tool mentah bocor |
| 9router/Alpha-think | planner | baca version.txt | OK, tanpa tool mentah bocor |

Server: `http://127.0.0.1:20128/v1/models` ada `Alpha-think`, `Alpha-fast`, `Budak` (ID persis). Config backup `opencode.json.bak-20260920`. Agent think: planner/debugger/reviewer/critic; fast: explorer/tester/researcher.

## PEKERJAAN FINAL (2026-09-21, leader; OPSI GANTI-MODEL dari instruksi tugas)

- Otorisasi khusus tugas ini: "leader boleh ganti field model agent ke
  cadangan bila 429/tumbang + catat di NOTES" — pengecualian tugas ini;
  AGENTS.md poin 6 tetap berlaku umum. Hasil: NOL 429 → tanpa ganti
  model. dev-apk opencode/nemotron-3-ultra-free; dev-modul
  opencode/mimo-v2.5-free.
- Status awal (CHECKPOINT 5723662): final-apk SUDAH merge ke fusion-v2
  (A1-A3 checkpoint + build15); final-modul (de9d984+c0917d9) BELUM merge.
- dev-apk work/b16-apk (c2951ab) TERIMA: A1 pref lama dibuang
  (BubbleStyle -4 baris, apply abaikan alpha/corner); A2 slider
  HelperGuard + intent BUBBLE_STYLE_REFRESH aman (guarded + try/catch,
  unhandled-action diabaikan service); A3 chip res60-100 (chip_res/
  chip_text + public.xml 0x7f03000f/0x7f05001b) + galeri pill
  terverifikasi + BgEditor RadioGroup sudah tunggal. BLOCKED-smali
  (terdokumentasi): A2a refresh live, A2h audit drag tepi, A3b logika
  setSelected. Bukti: 4 XML parse OK; hitung hook = baseline
  (BUBBLE_TOGGLE BSA 3→2 = hapus komentar, tanpa duplikat hook).
- dev-modul work/final-modul-2 (ee82297) + REVISI-1 (03fdf50, +12 baris:
  Adreno cap pakai GPU_MAX_FREQ pola Mali; sandbox PASS + edge 0
  fallback) TERIMA. M1-M9 SELESAI. Bukti: sh -n 7/7 OK; shellcheck
  hanya SC3043 (baseline 106 vs baru 112, gaya pre-existing);
  resetprop aktif NOL (2 hit komentar); secret 0; boot counter 2x +
  DISABLE_TWEAKS + CPU_OWNER log + MTK tulis-baca-kembalikan OK;
  PowerVR/Xclipse SKIPPED jujur; alpha-diag 13/13 item OK (read-only).
  Slip: modul-2 branched dari b16-apk (bukan fusion-v2) — isi APK
  identik (diff kosong), merge aman; milik modul hanya 7 file.
- Merge leader ke fusion-v2: 0398254 (APK) + d1eb55d (modul), tanpa konflik.
- INSIDEN 2026-09-21: edit leader yang belum commit (AGENTS p6,
  STATE/NOTES uji-tim) terhapus oleh checkout/reset pekerja di working
  tree bersama → diterapkan ulang; aturan baru AGENTS.md p7 melarang
  checkout/reset cabang di repo utama oleh pekerja Task.

## FALLBACK MODEL OTOMATIS (2026-09-21, tanpa router)

- Backup: ~/work/backup-opencode-20260921-fallback (63M, penuh).
- Audit 3 kandidat (README + SELURUH source dibaca):
  - PILIH: youngbinkim0/opencode-fallback = npm
    `opencode-runtime-fallback@0.2.4` (MIT, latest 2026-04-06, 80 komit,
    28 star/6 fork). Rantai per agent: YA via `fallback_models` di blok
    agent opencode.json (format asli). TTFT: YA `timeout_seconds`.
    Cooldown + pulih otomatis: YA (`cooldown_seconds` + recoverToOriginal
    tiap prompt). Pemicu: 429/5xx (retry_on_errors) + built-in kuota,
    model-not-found, missing-key. Dep runtime: 1 (jsonc-parser,
    Microsoft) + peer @opencode-ai/plugin. Jaringan selain model: NOL.
    Telemetri: NOL. Exec: NOL (13 file source bersih — hanya SDK calls,
    baca config, tulis log lokal).
  - TOLAK peva3 `opencode-fallback@1.2.0`: tanpa rantai per agent (satu
    model global) + fitur Ralph-loop (kirim prompt sendiri tiap idle —
    perilaku otonom tak diinginkan).
  - TOLAK zaplakhov `opencode-rate-limit@1.4.0`: tanpa rantai per agent
    (pool global) + dep `@opencode-ai/plugin@latest` TAK-PIN + native
    better-sqlite3 (berat di Termux) + baca DB internal OpenCode.
- Versi ter-pin: `opencode-runtime-fallback: 0.2.4` (exact di
  ~/.config/opencode/package.json + lock; integrity
  sha512-V0bTGkWSkquXhmyH5vcxNIebSNNuploSUZ4utrGqI7bE+x5iW3wO/U9IdbSqRgowYBeH++D1fPANwQQDM/oHOg==).
  Yang lain TIDAK dipasang.
- Konfigurasi: plugin `opencode-runtime-fallback` di opencode.json +
  `~/.config/opencode/opencode-fallback.json` (enabled, retry_on_errors
  [429,500,502,503,504], cooldown 600 dtk, TTFT 60 dtk, max 10,
  notify). Rantai: leader [muse-spark → ollama nemotron-3-ultra →
  mimo-v2.5-free]; dev-apk [nemotron-free → laguna-s-2.1 → gemma4:31b →
  nemotron]; dev-modul [mimo-v2.5-free → nemotron → laguna-xs-2.1].
  Ollama Cloud maks 1 per rantai, bukan cadangan pertama pekerja.
- UJI (tanpa bakar kuota, agent sementara uji-fallback, sudah dihapus):
  primer bogus `opencode/tidak-ada-uji` → log membuktikan
  `resolvedAgent: uji-fallback`, `errorType: model_not_found`,
  `Planned fallback: tidak-ada-uji -> mimo-v2.5-free (attempt 1)`.
  Kaki cadangan dibuktikan terpisah: mimo menjawab "OK" (15,3 dtk).
  Batas headless: `opencode run` keluar saat error terminal sehingga
  replay tak selesai dalam mode run; di sesi TUI sesi hidup dan replay
  mendarat. Tanpa model berbayar / kuota OpenRouter terpakai.
- PANTAU: `tail -f ~/.config/opencode/opencode-fallback.log`
  (tampilkan JSON per baris); status sesi di TUI via toast fallback.
- MEMATIKAN: hapus entri `"plugin"` dari `~/.config/opencode/opencode.json`
  (atau `"enabled": false` di `opencode-fallback.json`), lalu restart.
- RESTART: server opencode PID 3868 masih konfigurasi lama — user WAJIB
  restart (`kill 3868` lalu jalankan opencode kembali) agar fallback
  aktif di sesi utama. Proses `opencode run` uji memakai config baru.

## MTK universal + b23 final (2026-09-22, leader + dev-modul T1-T4)

- Prinsip (koreksi user): "EXTREME"/"BALANCED" = label tampilan dari state
  internal performance/balanced yang SUDAH ADA — tanpa variabel/state baru.
  Nilai tuning di balik performance/balanced dibuat universal (deteksi
  chipset), bukan tambah profil.
- T1 detect.sh (+165/-3, DETECT_VERSION 2→3): detect_chipset_family() =
  unisoc|mtk|mtk_legacy_unsupported|unknown, folder > nama (asopt → unisoc;
  fpsgo tanpa /proc/ppm+/proc/gpufreq → mtk; legacy → mtk_legacy_unsupported;
  sisanya unknown). Koreksi leader: nama platform TAK BOLEH menentukan
  sendiri (cabang "via nama" pekerja dihapus → unknown), GPU path generik
  (*.gpu/*.mali) khusus MALI, vendor lain tetap resolver lama. Diagnostik:
  "chipset detection: <hasil> (matched via: folder/keduanya/tidak-ada)".
  CPU_POLICIES kini sorted ascending cpuinfo_max_freq (semua cluster, 1/2/3+).
- T2 engine/gameboost (+67/-18): alpha_opp_snap_nearest() (seri → bawah)
  dipakai tune_cpu_freq max+min; loop semua policy tanpa asumsi jumlah;
  tune_gpu_mali/tune_devfreq log 0/>1 kandidat; gameboost governor devfreq
  cek available dulu, fallback performance→schedutil→sugov_ext→
  simple_ondemand→ondemand (sugov_ext tambahan leader, untuk MTK).
  Verifikasi: tidak ada tulis ke asopt; semua stune ter-guard.
- T3 monitor.sh (+18/-11): gb_safety_check baca per-zone `timeout 2 cat`
  (fallback langsung bila tanpa timeout) + filter rentang -50000..150000
  mC (ganti sentinel -274000/-40000). Dekat dengan hotfix b23 plaintext
  yang teruji HP (timeout sama; beda: b23 sentinel-list, final range).
- T4 sandbox 70/70 PASS + rerun independen leader IDENTIK: S1 Unisoc
  (unisoc, extreme p0/p6=1036800, balanced 1459200/1574400, revert identik),
  S2 MTK (mtk, extreme 1300000/1400000, balanced 1600000/2200000, revert
  identik), S3 unknown (fallback, revert identik), S4 3-cluster (loop 3/3),
  S5 snap (85%×2M=1.7M→1600000). sh -n 16/16, shellcheck 0 error.
  Bukti: /data/data/com.termux/files/usr/tmp/opencode/sbx-mtk/
  (full_output.txt + rerun-leader.txt). Catatan: balanced 85% bisa snap
  SEDIKIT di atas target (nearest, mis. 1370200→1459200) — sesuai spek.
- PELAJARAN: pekerja tulis "via nama" walau spek revisi melarang —
  spek REVISI harus di-quote verbatim di brief bila mengoreksi spek awal.
- Status: merge --no-ff 3 cabang ke fusion-v2. Rilis v1.0.0 MENUNGGU:
  (1) monitor.bin final di-encode + (2) user tes HP b23 ELF (ganti hotfix
  plaintext, buka-tutup game, APPLIED tanpa hang).

## T5 — thermal-safety fix (2026-09-22)

### Bug
`_gb_level()` hanya punya `if performance → performance; else → extreme`.
Saat monitor.sh thermal safety menulis "balanced" ke GAMEBOOST_LEVEL
(≥85°C), _gb_level mengembalikan "extreme" → proteksi panas gagal total.

### Root cause
Balance tidak ada di case statement. File "balanced" → `tr` lower →
tidak match "performance" → jatuh ke `echo "extreme"`.

### Fix (4 bagian)
1. `_gb_level()`: 3 case eksplisit (performance/balanced/extreme),
   default = balanced (fail-safe, bukan extreme).
2. `gb_apply()`: balanced = restore-native snapshot + return awal
   (TIDAK panggil _gb_apply_cpu/gpu/vm/io/net) → lantai extreme tidak
   tertulis. Tambah `balanced→balance` di `_gb_set_fasrs_mode()`.
3. monitor.sh game-open: non-forced tulis "extreme" eksplisit dengan
   pola save-orig/restore-orig (sama seperti forced path).
4. monitor.sh log: "APPLIED {level}" baca dari boost_level sesudah
   gb_apply. Cooldown COMPLETE log level juga dari boost_level.

### Test results
- _gb_level unit: 6/6 PASS (performance/balanced/extreme/absent/garbage/BALANCED-cap)
- gb_apply sandbox: 4/4 PASS (balanced→restore native, extreme→floor 65%, perf→floor 35%, absent→fail-safe)
- monitor snippet: 3/3 PASS (non-forced→extreme, forced-balanced→restore, forced-perf→floor 35%)
- sh -n: 0 error. shellcheck: 0 error.

### Observasi
- gb_restore() menghapus boost_level (baris 949). Di balanced path,
  gb_apply menulis ulang boost_level=balanced SETELAH gb_restore.
- _gb_restore_fasrs_mode() membaca current_state (bukan boost_level),
  jadi tidak terpengaruh oleh boost_level write order.
- Delta: +54/-20 baris, 2 file (gameboost.sh, monitor.sh).

## PELAJARAN on-device (2026-09-22)
- shc -r: isi script UTUH kelihatan di /proc/PID/cmdline (bukan
  enkripsi thd pembaca root lokal). Encode = anti-edit-santai saja.
- Bind-mount fake sensor dari Termux+su TIDAK terlihat proses Magisk
  (namespace beda). Pakai `su -M` (mount-master).
- Pola ps `monitor.bin -c` parent+child = NORMAL (child = subshell
  reader). Jangan dibunuh sebagai "duplikat".
- Watchdog restart monitor ≤180s setelah kill (pidfile+cmdline check).
  Kill monitor aman, verifikasi via baris START baru + md5 .bin.
- Sourcing copy gameboost.sh dari /sdcard dgn env override
  (ALPHA_CONF_DIR, CPU_POLICIES) = cara uji fungsi modul di HP tanpa
  ubah file modul.

## b27 — grace-defer + oom-guard (2026-09-23, leader langsung; TANPA push)
- Bukti live (leader eksekusi, user pegang HP saja): PGR EN
  (com.kurogame.gplay.punishing.grayraven.en, BUKAN .tw) APPLIED extreme;
  HOME+3s -> GRACE started TAPI APPLY-POLL battery instan (bug #2
  terkonfirmasi); balik -> CANCEL + performance; HOME+20s -> DAILY
  RESTORED 12s tepat + balik -> APPLIED lagi. Monitor POLLING (7s).
  OOM: monitor.bin/watchdog.bin adj=-1000 (warisan induk Magisk, BUKAN
  kode kita), fas-rs adj=0. B-window: LMK bunuh 8 proses app
  (signal 9, uid app), NOL sentuh 351/3818/3827; watch 32 siklus penuh.
- Fix (23547b5, 5 file, +52/-2): (1) grace-defer di handle_event:
  boost aktif + non-game + pending ADA -> return sebelum apply_now
  (revert via check_grace saat habis); manual tanpa boost tetap instan.
  (2) _oom_guard (service.sh) + inline di watchdog/game_add/
  engine_manager: echo -1000 ke /proc pid + log; 6 titik (monitor,
  watchdog, fas-rs x3 path). Launcher-side -> berlaku .sh maupun .bin.
- Verifikasi: sh -n 5/5 OK; sandbox harness (fungsi asli + stub)
  16/16 PASS (S1 apply, S2 defer, S3 cancel, S4 expiry-revert,
  S5 manual-instan). Harness di /usr/tmp/opencode/test-b27-grace.sh
  (tidak di-commit, anti-polusi). CI BELUM. Status: TUNGGU.
- Follow-up: "PAKAI BANNER DEFAULT" tak hapus crop (b28 kandidat);
  guardian untuk watchdog sendiri (restart silang) BELUM.
