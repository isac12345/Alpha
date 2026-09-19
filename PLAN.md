# PLAN.md — Alpha Fusion v2 (branch fusion-v2)

## Selesai (terverifikasi, run 35429540702)
- [x] Tree modul dari `Alpha-fusion-v2-final.zip` + `.gitignore` + `AGENTS.md` di `fusion-v2`.
- [x] Workflow `package.yml`: zip META-INF di root, exclude docs/`.opencode`/`build-output`.
- [x] Zip 5.4M terverifikasi: `module.prop` root ✓, `update-binary` ✓, sha256 APK = asli ✓, tanpa folder pembungkus.
- [x] Pipeline `apk-edit.yml`: rebuild + sign kunci baru (cert `a0698c50…` ≠ lama), smoke test SUCCESS.
- [x] Pipeline terintegrasi: `version.txt`=2 sumber tunggal, enforce vs `ALPHA_COMPANION_VER`, patch versionCode bare int (apktool 3), apktool di `work/tools/`, `.gitignore` di-exclude.
- [x] Fix flag basi `companion_install.sh` (uninstall→reflash tetap install ulang).
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
- F2 bubble hidden: `BubbleService$3.smali` punya 800ms threshold + `hidden` persist. Yang belum: tanpa `withTimeout`, tanpa vibrator/toast, `hidden` tidak dibaca saat `startFg()` (`bubble` muncul lagi setelah reboot), notifikasi statis ("Alpha Bubble"). **Jalur (b) patch `BubbleService.smali` + (a) overlay notif.**
- `openBatteryLab` selalu ada, tombol selalu tampil → **(a) overlay `activity_main.xml` + `AndroidManifest.xml`** untuk cek `resolveActivity` via intent filter (butuh smali guard, `(b)`).

## Berikutnya (satu per satu)
- [ ] Baca smali relevan dari decode (BubbleService, MainActivity bagian resolusi/dexopt, RootShell displayInfo/gameList) → tentukan patch (b) yang aman.
- [ ] Overlay (a): `AndroidManifest.xml` + `POST_NOTIFICATIONS`, `activity_main.xml` guard BatteryLab, `res/values/` konsistensi.
- [ ] Patch (b): `displayInfo` parse Override, `BubbleService` hidden persist on boot + withTimeout, guard BatteryLab.
- [ ] (c2) fitur besar setelah persetujuan user per item.
- [ ] Tes flash di HP setelah pipeline + verifikasi.
- [ ] Finalisasi keystore + merge (BUTUH persetujuan).
