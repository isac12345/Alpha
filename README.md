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

## Perubahan UI (pembersihan)
- Tag NEW dan border mint dibuang; teks penjelasan kecil dibuang, sisa hanya yang fungsional.
- Teks lebih besar, kontras default 85.
- Dash: peringatan bila versi modul != versi app atau modul tidak punya alphactl; label "Dikunci game" saat game aktif.
- Tutup semua app: konfirmasi lebih tegas, opsi app sistem default mati, Termux dan manager root dilindungi.
- Workflow: `mkdir -p module/companion` (folder kosong tidak ikut git).

## Perubahan setelah uji di HP
- Suhu di Dash, notifikasi, dan bubble = suhu baterai (`temp_mc`). Suhu sensor terpanas (`soc_temp_mc`) hanya dipakai di layar Proteksi thermal karena batasnya dibandingkan ke sensor itu.
- Bubble: panel pilih profil vertikal di samping bubble (seperti rancangan awal), bukan pil horizontal.
- Notifikasi: judul "Profil aktif: X", isi baterai dan suhu baterai, baris game saat game jalan, tombol profil aktif diberi tanda ●.
- Modul (`engine.sh` apply_tweak): kernel menolak nilai / node tidak bisa ditulis / node tulis-saja tidak lagi dicatat FAILED. Jadi SKIPPED atau APPLIED agar filter ERROR bersih dan counter failed jujur.

## Perbaikan dari log perangkat (Unisoc T606)
- engine.sh `alpha_rd`: pembacaan ulang pakai `cat`, bukan builtin `read`. Di kernel ini `read` dari /proc/sys cuma mengembalikan 1 karakter (300 terbaca 3), sehingga muncul FAILED dan WARN palsu padahal nilai sudah masuk.
- engine.sh: node pilihan seperti scheduler ("mq-deadline kyber [bfq] none") dianggap berhasil bila nilai target ada di dalam tanda [ ].
- service.sh (M2b): fas-rs baru hidup setelah tahap tuning, jadi boot jatuh ke fallback Alpha (CPU dibatasi 75%). Sekarang pemilik CPU dievaluasi ulang begitu /dev/fas_rs/mode siap.
- autoctl.sh: puncak suhu sesi memakai suhu baterai (sebelumnya sensor terpanas).
