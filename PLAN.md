# PLAN.md — Alpha Fusion v2 (branch fusion-v2)

## Selesai (terverifikasi, run 35429540702)
- [x] Tree modul dari `Alpha-fusion-v2-final.zip` + `.gitignore` + `AGENTS.md` di `fusion-v2`.
- [x] Workflow `package.yml`: zip META-INF di root, exclude docs/`.opencode`/`build-output`.
- [x] Zip 5.4M terverifikasi: `module.prop` root ✓, `update-binary` ✓, sha256 APK = asli ✓, tanpa folder pembungkus.
- [x] Pipeline `apk-edit.yml`: rebuild + sign kunci baru (cert `a0698c50…` ≠ lama), smoke test SUCCESS.
- [x] Pipeline terintegrasi: `version.txt`=2 sumber tunggal, enforce vs `ALPHA_COMPANION_VER`, patch versionCode bare int (apktool 3), apktool di `work/tools/`, `.gitignore` di-exclude.
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
