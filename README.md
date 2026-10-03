# Alpha Fusion v51 + Alpha Control v2 (APK)

Satu repo: modul root (`module/`) dan aplikasi pengendali (`app/`). Build lewat GitHub Actions
(`.github/workflows/build.yml`) menghasilkan `AlphaControl-v51.apk` dan `Alpha-Fusion-v51.zip`
(zip modul sudah berisi APK di `companion/AlphaBubble.apk`, nama yang dicari `customize.sh`/`service.sh`).

## Prinsip
APK hanya remote. Semua logika di modul. APK memanggil `common/alphactl.sh` lewat `su -c`
(`Root.kt` -> `Alpha.kt`). Tidak ada tuning di sisi APK kecuali `wm size/density`, `cmd package compile`,
`am force-stop` (alat bantu, bukan tuning engine).

## Peta tombol -> modul
| UI | Perintah |
|---|---|
| Ganti profil (Dash, bubble, notifikasi, tile) | `alphactl profile <battery\|balanced\|performance>` -> `apply_now.sh <p> manual` |
| Status Dash / Thermal / bubble | `alphactl status` |
| Auto-profile (aturan baterai / charging) | `alphactl conf set AUTO_*`, dijalankan `common/autoctl.sh` (daemon baru) |
| Proteksi thermal | flag `THERMAL_GUARD_OFF`, file `THERMAL_WARM_C` via `alphactl thermal set 60-90`; dibaca `monitor.sh` (`thermal_user_thr`). Batas kritis 95C tetap |
| Statistik sesi | `autoctl.sh` menulis `/data/adb/alpha/sessions.log`; dibaca `alphactl sessions` |
| Games (list/tambah/edit/hapus/auto-detect) | `alphactl games`, `game add`, `game remove` -> `game_add.sh` |
| Render | `alphactl render get/set` -> `render_manager.sh` |
| Toggle Mesin | flag `GB_FASRS_FORCE_ALPHA` (toggle "fas-rs pegang CPU" = flag TIDAK ada), `GB_COOLDOWN_EXTREME`, `NO_CPUSET` (toggle "Cpuset dipersempit" = flag TIDAK ada) |
| Boot guard | flag `BOOT_GUARD_OFF` (dibaca `service.sh`) |
| Health check | `alphactl health` |
| Device / Deteksi ulang | `alphactl device` / `redetect` |
| Resolusi + DPI | `wm size` + `wm density`; pengaman auto-revert di sisi perangkat (`.res_keep`) |
| Dexopt (pilih mode) | `cmd package compile -m <speed-profile\|speed\|everything\|verify> -f <pkg>` atau `--reset` |
| Tutup semua app | `am force-stop` daftar app; opsi app sistem hanya yang punya ikon launcher dan bukan layanan inti |
| Battery Lab | sysfs `power_supply/battery/*` |

## Perubahan modul (v50 -> v51)
- baru: `common/alphactl.sh`, `common/autoctl.sh`
- `monitor.sh`: ambang suhu bisa diatur (`thermal_user_thr`), default tanpa file = perilaku lama
- `service.sh`: start `autoctl.sh` saat boot, sakelar `BOOT_GUARD_OFF`
- `uninstall.sh`, `customize.sh`, `companion_install.sh`, `module.prop`: ikut versi 51

## Build / ubah versi
Naikkan `version.txt` (sumber tunggal), samakan `module.prop` versionCode dan `ALPHA_COMPANION_VER`
di `module/common/companion_install.sh`. `tools/check_module.sh` memeriksa ketiganya.

## Yang belum terverifikasi
Kode Kotlin ditulis tanpa Android SDK di sandbox, jadi belum pernah dikompilasi. Script modul sudah
dites di sandbox (alphactl, autoctl). Jika build gagal, perbaiki error kompilasi dulu; logika sudah lengkap.
Tanda tangan APK memakai `keystore/alpha-release.jks` (password default di `app/build.gradle.kts`,
bisa dioverride via env `ALPHA_*`). Kalau APK lama terpasang dengan tanda tangan berbeda,
uninstall sekali sebelum memasang yang baru.
