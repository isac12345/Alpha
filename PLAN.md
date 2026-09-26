# PLAN.md — Alpha Fusion (nama versi v1; internal naik per build)

## Hybrid-v36 (2026-09-26, L2 MENANG di HP user)
- Zip: /sdcard/alpha/Alpha-Fusion-v36-hybrid.zip (vCode 34, md5 67dea4).
  Isi = hybrid floors (extreme 80/45, perf 40, tap 55/bal 30) + GPU
  opsi A (Mali polling 10ms + kbase 45) + monitor event fix. TANPA
  floor-lock engine, TANPA adaptive AGF, TANPA antisnapshot v31.
- [x] L2 user: stutter minim, WuWa <10% — paling enak sejauh ini.
- Catatan: vCode 34 = snapshot NATIVE_VERSION=30, rentan racun
  (min=max + GPU max 384M). Bila snapshot keracunan, rasa enak bisa
  berubah. Opsi v38: tuning hybrid-v36 persis + antisnapshot saja.

## V37-adaptive-floor (2026-09-26, L1 DONE, L2 GAGAL vs hybrid)
- [x] Adaptive GPU floor tiered-delta (monitor.sh +415, work/adaptive-floor):
  delta trans_stat -> busy% -> HIGH/MID/LOW (70/30, MID 60% plafon),
  naik langsung + turun 3 tick + thermal paksa LOW; plafon live dari
  profiles.sh; battery OFF. Termasuk final v36 (balanced CPU35/GPU40,
  perf GPU90, battery release, floor thermal gate) + antisnapshot v31.
- [x] L1: bash-n OK, shellcheck 0, sandbox 24/24, HP test fungsi
  (parser/thermal/battery/plafon/naik-768M). Merge 3ea3fe9 + bump 37.
  Zip: /sdcard/alpha/Alpha-Fusion-v37-adaptive.zip (md5 f9278920).
- [x] L2 (2026-09-26, user): KALAH vs hybrid — busy% cuma turun ke 54%
  (masih MID, floor 60% plafon, tak pernah LOW). Dugaan: UI render
  54-72% busy = MID terus. Opsi: tune ambang MID atau balik hybrid statis.

## Perf-max + Balanced-adem (2026-09-25, L1 DONE, L2 TUNGGU HP)
- [x] Performance raw-power (floor 50%/big75%, uclamp60, kbase30,
  fast, gate95C, tangga 85/90) + Balanced adem-stabil (floor25%,
  kbase 2/55, mild uclamp30). Merge ba16cd7, tanpa bump versi.
- [x] L1: bash-n + shellcheck 0 + sandbox + uji tier 10/10.
- [ ] L2: tes HP PGR/WuWa berat + sesi panjang balanced (TUNGGU user).

## Modul33 — stabil-otomatis universal (2026-09-25, L1 DONE, L2 TUNGGU HP)
- Isi modul33: lihat entri STATE MODUL33-STABIL-OTOMATIS. L2: tes HP
  PGR + WuWa pacing-cepat (TUNGGU user).

## B35 — universal runtime guards + flash/uninstall hardening (2026-09-25, L1 DONE, L2 TUNGGU HP)
- [x] Restore GPU: backup min absen → skip tulis min (was fallback=max
  = kunci ulang). GPU-max: fallback max_freq-node (was cur_freq);
  absen → skip. Thermal tanpa sensor: sentinel 75000 + log UNKNOWN
  (was 0 = extreme buta). Topologi >2 level: floor uniform 60% + skip
  cpuset (was mid digolong little).
- [x] Flash-timpa: `customize.sh` sudah bersih transient + native basi.
- [x] Uninstall: source `detect.sh` dulu → `CPU_POLICIES` terisi →
  `gb_restore` CPU jalan; unknown-manager AsoulOpt → `retry:` flag
  (bukan `skip:`) + return 1 → service.sh retry boot berikutnya.
- [x] Loop var `_alpha_bin` dikurung subshell. Guards `CPU_POLICIES`
  di `_gb_backup_native`, `_gb_apply_cpu`, `gb_restore` (WARN + return).
- [x] L1: sh-n OK, shellcheck 0, sandbox (2-cluster identik modul33;
  3-cluster 912000/1000000/1440000 + cpuset utuh; no-sensor→performance;
  GPU-tanpa-OPP→gov saja; restore-tanpa-min→min utuh). Merge 69f914d,
  tanpa bump versi.
- [ ] L2: tes HP (TUNGGU user).

## B34 — timeout perintah root (2026-09-25, L1 DONE, L2 TUNGGU HP)
- [x] `RootExecutor` (timeout 20 dtk + exit code + quoting); `ToolsKit.revert`
  pakai wrapper; CI SUCCESS `36042954181`; merge 822fadf.
- [ ] L2: tes HP revert resolusi (TUNGGU user).

## B33 — cpuset top-app (2026-09-25, L1 DONE, L2 TUNGGU HP)
- [x] `top-app` = big + 2 little pertama; `foreground` tetap big;
  `background`/`system-background` tetap little; topologi tak dikenal =
  skip cpuset (merge 72dfb81, tanpa bump versi).
- [x] L1: sh-n OK, shellcheck 0, sandbox 3 skenario (normal, little<2,
  topologi-unknown).
- [x] Push + CI SUCCESS `36042556279` (46s).
- [ ] L2: tes HP PGR + WuWa (TUNGGU user).

## Selesai dan lolos tes HP
- [x] v1 build 3 (run 35445291496, tag `v3-tested`): B1 Override-first + manifest POST_NOTIFICATIONS/debuggable=false. Tes: label resolusi benar.
- [x] v1 build 6 (run 35453438021, tag `v6-tested`): F2 HideFeedback + BubbleSettingsActivity + VIBRATE. Tes: saklar bubble bekerja.
- [x] v1 build 7 (run 35454848558): 1 ikon LAUNCHER + shortcut + ikon notif monokrom. Tes HP: lolos. Tag `v7-tested` + merge FF ke master (workflow aktif).
- [x] B3 guard BatteryLab: DILEWATI (tombol tanpa id; try/catch fallback ada).

## Batch 1 (build 8) — PIPELINE SUCCESS, tunggu tes user
- [x] Onboarding izin + kartu Bubble di Home (run `35478758890`).
- [x] Guard Battery Lab (via refresh, id baru).
- [x] Overlay kecil: kontras tab, padding log, id-ID.
- [x] alpha-test full: 6/7 → 7/7 (service wajar mati saat autostart off).

## Batch 2 (build 9) — PIPELINE SUCCESS, tag batch2-built
- [x] C3 dexopt progres + hasil (run `35480098420`).
- [x] C2 revert resolusi otomatis (root penjaga).
- [x] Restyle Tools (overlay).
- [ ] BLOCKED: konfirmasi render backend (alasan di atas).

## Batch 3 (build 10) + perbaikan tes HP (build 13, run `35493343726`)
- [x] C1 kustomisasi bubble: proporsional setScale (tanpa paksa persegi), clamp 60-140%, slider baca tersimpan/default 100%, RESET KE BAWAAN.
- [x] Notifikasi dinamis: judul profil aktif + aksi Show/Hide + Pengaturan (aksi berfungsi? PERLU tekan manual).
- [x] Editor crop background: hook handlePick + gravity CENTER + inSampleSize; picker TERBUKTI terbuka (screenshot). Crop+simpan: PERLU TES MANUAL.
- [x] Dexopt FC diperbaiki (Context signatures) + status jujur; TERVERIFIKASI HP (Canta 89.788 dtk, tanpa crash).
- [x] Kartu Home 1 kalimat + membulat; pill APPLY/RESET/DEXOPT (dump + screenshot).
- [ ] BLOCKED: aksi profil per-item (alasan di atas).

## Backlog
- [ ] B2 timeout perintah root.
- [ ] Perbaikan log (waktu --:--, teks penuh, salin).
- [ ] Daftar game nama + ikon.
- [ ] Keystore final.

## Game Boost paritas Extreme HSIN (2026-09-21, merge 0532eca)
- [x] common/gameboost.sh gb_apply/gb_restore + native_boost.conf + sakelar (extreme default).
- [x] Pemicu monitor (game+performance, grace 12 dtk) + thermal 75/85/95C + baterai + auto-kembali.
- [x] SF_LATCH opt-in + bin/pgr-log + CEK_PGR.md. Sandbox (a)-(e) + verifikasi leader (a)+(c).
- [ ] BELUM tes HP (uji A/B ikut CEK_PGR.md).

## Aturan build
- Nama versi tetap v1. Internal versionCode = version.txt = ALPHA_COMPANION_VER, naik per build.
- Tiap batch = satu build; alpha-test dulu (maks 3x per masalah); merge hanya bila user OK.
## Revisi 2026-09-19 (setelah verifikasi smali HP live) — KOREKSI B1

Bug resolusi yang beneran: `activeDisplayInfo()` (`RootShell.smali:812`) pakai `(?:Override|Physical)` + `find()` → regex engine cari dari kiri → `Physical size:` (baris pertama output `wm size`) SELALU menang, walau Override aktif. Dampak: label "Resolusi aktif saat ini" nunjukin nilai FISIK (720x1600) padahal override aktif 432x960.

**Target patch B1 = `activeDisplayInfo()`: ubah jadi cek `Override size: (\d+)x(\d+)` DULU → null? fallback `Physical size:...`. Sama untuk density (`Override density` dulu). `displayInfo()` TIDAK diubah** (ia baseline fisik untuk kalkulasi persen anti-stacking, pembuktian `MainActivity$renderResolutionActive$1.smali:345-352` pakai `displayInfo.getWidth()` sebagai penyebut).

Bukti klaim lama (`(?:Override|Physical) size:`) — `RootShell.smali:1040` (size) & `:1063` (density): keduanya `Regex(...); find$default(...,0,...)` — POSISI 0 → selalu match Physical. `find()` Kotlin = first match dari kiri, bukan scan alternation. Ini yang bikin `a)` overlay-only tidak cukup: bahkan sebagai fallback pun dapat nilai salah.
- [x] Versi sinkron: `module.prop` versionCode=2 = `version.txt` = `ALPHA_COMPANION_VER`.

## Laporan jalur (TAHAP 2, 2026-09-19 — berubah setelah decode APK)

Decode APK `AlphaBubble.apk` (run `35436973720`, `/usr/tmp/opencode/decode`, jangan commit):
- Single-Activity programmatic (`MainActivity.smali` 5040 baris, NOL Fragment).
- `BubbleService` (bukan `FloatingBubbleService`), `ProfileTileService`, TANPA `ProfileMonitorService`.
- Manifest: 7 permission, TANPA `POST_NOTIFICATIONS` (beda dari manifest tag).
- Prefs: `app_bg_uri`/`app_bg_alpha` (cocok HP), TANPA `bg_image_path`.
- Game: lewat `game_manager.sh` + `engine_manager.sh`, parse JSON (`parseGameArray`) — **bug path+delimiter SUDAH TIDAK ADA di APK**.
- Resolusi: baca `wm size`+`wm density` (regex Physical saja, Override belum), apply keduanya, reset keduanya.
- Dexopt: speed/everything/verify/space/speed-profile, selalu `-f`, tanpa progres/durasi.
- Bubble: long-press 800ms + persist `hidden` ADA; TANPA vibrator/toast.
- BatteryLab: explicit intent tanpa guard (fallback Settings).
- Root: hanya `waitFor`, tanpa `withTimeout`.

**JALUR NYATA (bukan estimasi tag lagi):**
- **(a) overlay resource** = aman: `AndroidManifest.xml` (tambah `POST_NOTIFICATIONS`), `res/layout/activity_main.xml` (tambah guard tombol BatteryLab), `res/values/` (warna/teks).
- **(b) patch smali kecil** = kandidat: timeout root (`withTimeoutOrNull`), guard BatteryLab (`resolveActivity`), `displayInfo` parse Override (`Override size: (\d+)x(\d+)`), `gameList` delimiter `:`. Perlu telusuri smali dulu.
- **(c2) source Kotlin** = fitur besar: editor crop, countdown UI, photo picker, F1 bubble kustom, T1 sinkronisasi. Usaha besar, perlu spesifikasi perilaku dari smali.

**Prioritas eksekusi:** (1) baca smali yang relevan → tentukan patch (b) mana yang aman; (2) overlay (a) B3+T3 + POST_NOTIFICATIONS; (3) (c2) setelah persetujuan per item.

## Tambahan 2 — R1/F2 (2026-09-19, berubah setelah decode)

- R1 resolusi+DPI: `applyDisplay` SUDAH apply size+density (`; wm density `), `resetDisplay` SUDAH reset keduanya. Yang belum: preview "%, DPI" sudah ada, tapi tanpa countdown, tanpa saklar DPI, tanpa even-rounding, `displayInfo` hanya baca Physical (Override belum). **Jalur (b) patch smali `displayInfo` + (a) overlay UI.**
- F2 bubble hidden — KOREKSI (smali, bukan tag): `BubbleService$2$1.smali:44-81` hold-check ambang **500ms** (`0x1f4`), BUKAN 800ms; ada guard `moved` (BubbleService$2.smali:154-175 set moved saat gerak > slop, `:165` removeCallbacks bila slop terlampaui) → "tanpa ambang gerak" di tag WRONG; `hidden` **DIBACA** saat `attach()` (`BubbleService.smali:665` applyVisibility() dipanggil attach) → "hidden tidak dibaca saat startFg" WRONG (bubble tetap terlihat setelah reset). Yang BENAR-BENAR kurang di F2: (1) tanpa vibrator/toast saat hide (grep VibrationEffect|Toast = nol), (2) notifikasi statis "Alpha Bubble", (3) tanpa `withTimeout` pada holdCheck. **Jalur (b) patch BubbleService$2$1 (tambah vibrator/toast opsional) + (a) overlay notif.**
- `openBatteryLab` selalu ada, tombol selalu tampil → **(a) overlay `activity_main.xml` + `AndroidManifest.xml`** untuk cek `resolveActivity` via intent filter (butuh smali guard, `(b)`).

## Berikutnya (satu per satu — REVISI 2026-09-19, setelah verifikasi smali)

- [x] **B1 (DONE, run 35445291496)**: patch `RootShell.activeDisplayInfo()` → Override-FIRST, `displayInfo()` TIDAK diubah.
- [x] **Overlay manifest (DONE)**: `POST_NOTIFICATIONS` + `debuggable=false` (cek smali: nol dependensi debug).
- [ ] **B3 (DILEWATI)**: tombol tanpa `android:id` (layout:92, hanya `onClick`) → guard butuh patch menengah. Try/catch fallback Settings sudah ada (`MainActivity.smali:5030-5037`), tanpa crash. Tidak ada perubahan B3 di v3.
- [ ] **B2 (TUNDA)** + **F2 (TUNDA)**: sesuai instruksi.
- [ ] Tes flash v3 di HP + verifikasi.
- [ ] Finalisasi keystore + merge (BUTUH persetujuan).

## Nota verifikasi (jangan ubah tanpa bukti smali ulang)
- F2 bubble: hold-threshold smali = **500ms** (`BubbleService$2.smali:416` = `0x1f4`), BUKAN 800ms; ada guard `moved` (`BubbleService$2.smali:153-166`); `hidden` **DIBACA** saat `attach()` (`BubbleService.smali:665` → `applyVisibility`) → patch hidden-persist/reboot TIDAK diperlukan. Yang benar-benar kurang: vibrator/toast saat hide + notif statis — **DITUNDA** (opsional, butuh persetujuan).
- B1 resolusi: `activeDisplayInfo()` (bukan `displayInfo()`) yang bermasalah — `find()` dari kiri selalu match `Physical size:` (baris pertama output `wm size`). Patch v3 = regex-only Override-FIRST (tanpa instruksi/label baru, grup 1-2 unchanged). `displayInfo()` tetap Physical murni = baseline persen anti-stacking.
- BatteryLab: `openBatteryLab` explicit intent (`MainActivity.smali:5004`) + try/catch fallback Settings (`:5030-5037`), tanpa guard `resolveActivity`, tombol tanpa id → **B3 DILEWATI** (butuh patch menengah).
- Root: tanpa `withTimeout` (`RootShell$exec$2.smali`, `BubbleService.su` waitFor) → **B2 DITUNDA**.

## Modul32 — PGR-kenceng (2026-09-24, L1 DONE, L2 TUNGGU HP)
- [x] Extreme big floor 65→75% (satu variabel; little 35% + uclamp/sched/VM/IO/GPU/cpuset/thermal tetap). T615: p6 1040000→1228800, p0 tetap 614400, performance tetap (CI 36016623318, commit 5ad155d).
- [x] L2-PGR: user 2026-09-25 lapor gacor/OK.
- [ ] L2-WuWa: tes HP WuWa (TUNGGU user). Bila panas/kresek: kandidat revert = floor kembali 65%.

## Modul30/31 — stabil rasa rilis + timpa-bersih (2026-09-24, L1 DONE, L2 TUNGGU HP)
- [x] Modul30: profiles 4 angka revert v20 + NATIVE_VERSION=30 refresh snapshot + service hapus transient (CI 35957462703).
- [x] Modul31: guard set_perm .bin + cleanup state saat timpa + uninstall bersih (kill watchdog/restore/timeout) (CI 35959277271).
- [x] Zip modul31 (vCode 31, md5 45a4a55) di /sdcard/alpha, sisa 1 file.
- [ ] L2: tes HP flash-timpa + WuWa 2-3 mnt (TUNGGU user, tanpa desak).
