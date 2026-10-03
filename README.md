# Alpha Control (com.alphabubble) - rebuild v2

APK companion untuk modul Magisk "Alpha + Uperf + fas-rs Fusion" (v50). Tanpa dependency AndroidX, UI dibuat lewat kode.

## Build
GitHub Actions: `.github/workflows/build.yml` (Gradle 8.7 dari setup-gradle, tidak butuh gradle wrapper).
Secret opsional untuk tanda tangan: KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD.
Tanpa secret, APK ditandatangani debug key (tidak bisa update APK lama yang beda tanda tangan: uninstall dulu).
versionCode = 20 (sama dengan ALPHA_COMPANION_VER di modul).

## Sambungan ke modul (semua lewat root `su`)
- Cari modul: /data/adb/{modules,ksu/modules,ap/modules}/alpha_uperf_fasrs_fusion
- Profil: `sh common/apply_now.sh <battery|balanced|performance> manual`; baca `/data/adb/alpha/current_state`
- Game: `common/game_add.sh add <pkg> <profile> <fps>` / `remove`, daftar dari `game_manager.sh list` + `engine_manager.sh list`
- Render: `common/render_manager.sh get|set <default|skiagl|skiavk>`
- Deteksi: `/data/adb/alpha/detected.conf`, ulang via `ALPHA_FORCE_DETECT=1 sh common/detect.sh`
- Log: `/data/adb/alpha/alpha.log`
- Mesin (flag file di /data/adb/alpha): GB_FASRS_FORCE_ALPHA (fas-rs pegang CPU = tidak ada), GB_COOLDOWN_EXTREME, NO_CPUSET (cpuset dipersempit = tidak ada)
- Status game: thermal_zone, /dev/fas_rs/mode, .game_t0 + /proc/uptime
- Resolusi: `wm size` / `wm density`; Dexopt: `cmd package compile -m speed-profile -f`
