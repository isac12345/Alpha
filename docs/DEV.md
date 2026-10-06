# Catatan pengembang

## Cara kerja
Aplikasi hanya remote. Semua logika ada di modul. Aplikasi memanggil `module/common/alphactl.sh` lewat `su -c` (`Root.kt` > `Alpha.kt`). Pengecualian: `wm size/density`, `cmd package compile`, `am force-stop`.

## Tombol dan perintah modul
| Aplikasi | Perintah |
|---|---|
| Ganti profil | `alphactl profile <battery\|balanced\|performance>` > `apply_now.sh <p> manual` |
| Status | `alphactl status` |
| Auto-profile | `alphactl conf set AUTO_*`, dijalankan `common/autoctl.sh` |
| Proteksi thermal | flag `THERMAL_GUARD_OFF`, `alphactl thermal set 60-90` (dibaca `monitor.sh`). Batas kritis 95C tetap |
| Statistik sesi | `autoctl.sh` menulis `/data/adb/alpha/sessions.log`, dibaca `alphactl sessions` |
| Games | `alphactl games`, `game add`, `game remove` > `game_add.sh` |
| Render | `alphactl render get/set` > `render_manager.sh` |
| Toggle Mesin | flag `GB_FASRS_FORCE_ALPHA`, `GB_COOLDOWN_EXTREME`, `NO_CPUSET` |
| Boot guard | flag `BOOT_GUARD_OFF` (dibaca `service.sh`) |
| Health / Device | `alphactl health`, `alphactl device`, `alphactl redetect` |
| Resolusi | `wm size` + `wm density`, auto-revert lewat `.res_keep` |
| Dexopt | `cmd package compile -m <mode> -f <pkg>` atau `--reset` |
| Battery Lab | sysfs `power_supply/battery/*` |

## Versi
- Rilis publik: v1, v2, v3, dst (tag GitHub dan `version=` di `module.prop`).
- `versionCode` (sekarang 51) adalah nomor internal dan sumbernya `version.txt`. Samakan dengan `module.prop` dan `ALPHA_COMPANION_VER` di `module/common/companion_install.sh`. `tools/check_module.sh` memeriksa ketiganya.
- Modul hanya memasang ulang APK bila `ALPHA_COMPANION_VER` naik.

## Build
GitHub Actions (`.github/workflows/build.yml`) menghasilkan `AlphaControl-<versionCode>.apk` dan `Alpha-Fusion-<versionCode>.zip` (APK ikut di `companion/AlphaBubble.apk`). Zip rilis diberi nama sesuai versi rilis (mis. `Alpha-Fusion-v2.zip`).

## Tanda tangan APK
Keystore dan password tidak disimpan di repo. CI membacanya dari GitHub Secrets:
`ALPHA_KEYSTORE_BASE64`, `ALPHA_STORE_PASSWORD`, `ALPHA_KEY_ALIAS`, `ALPHA_KEY_PASSWORD`. Build gagal kalau salah satunya kosong. Simpan salinan keystore di luar repo.

## Perilaku yang disengaja
- `engine.sh`: pembacaan ulang node memakai `cat` (builtin `read` hanya mengembalikan 1 karakter di sebagian kernel). Penolakan kernel dicatat SKIPPED, bukan FAILED.
- `service.sh`: pemilik CPU dievaluasi ulang setelah fas-rs hidup.
- Suhu yang ditampilkan di aplikasi adalah suhu baterai. Layar Proteksi thermal memakai sensor terpanas karena batasnya dibandingkan ke sensor itu.

## Hemat resource
- Bubble/notifikasi memanggil `alphactl brief` (tanpa fork) tiap 10 detik, 15 detik saat game. Layar mati: tidak ada panggilan root. Baterai dan suhu dari broadcast sistem, bukan root.
- Notifikasi hanya diperbarui kalau isinya berubah.
- Background 1280px dan banner 1080px, background di-decode RGB_565. Gambar hanya ada di memori saat aplikasi terbuka.
- Release memakai R8 dan shrinkResources. Kalau ada crash yang hanya muncul di release, matikan `isMinifyEnabled` di `app/build.gradle.kts` untuk memastikan.
- Monitor modul: polling saat game 4 detik (sebelumnya 2), env `ALPHA_GAME_POLL_INTERVAL_SECS`. Saat game aktif dan prosesnya hidup (`pidof`), dumpsys penuh hanya tiap 12 detik, env `ALPHA_FG_FULLCHK_SECS`.
