# Alpha Fusion v1

Modul Magisk: Alpha + Uperf + fas-rs fusion. `versionName=v1`, `versionCode=20`.

Syarat: perangkat ARM64, Magisk terpasang. fas-rs nonaktif bila API <= 30.

## Instalasi

1. Flash `Alpha-Fusion-v1-release-clean.zip` via Magisk, reboot.
2. APK companion dipasang otomatis saat flash; Android mungkin meminta konfirmasi instal manual tergantung setelan device (`companion/AlphaBubble.apk`, Alpha Control v1, `versionCode=20`).
3. Konfigurasi fas-rs: `/sdcard/Android/fas-rs/games.toml` (format: lihat `fasrs/README_EN.md`).

## Kompatibilitas

| Target | Status |
|---|---|
| Unisoc T615 (ums9230), GPU Mali, Android 14 / SDK 34, 720x1600 density 320 | Teruji hardware |
| Adreno / Snapdragon | belum diverifikasi hardware — cap GPU memakai pola Mali, hanya sandbox |
| MediaTek | belum diverifikasi hardware — hanya sandbox |
| PowerVR / Xclipse | belum diverifikasi hardware — di-skip oleh detect (UNKNOWN) |
| Non-ARM64 | Ditolak installer (abort) |
| API <= 30 | Terpasang, fas-rs nonaktif |

## Kredit & Lisensi

- Alpha (kode integrasi: `service.sh`, `customize.sh`, `uninstall.sh`, `common/`, `system.prop`, docs) — GPL-3.0 (`LICENSE`).
- fas-rs — GPL-3.0, upstream shadow3aaa (`fasrs/LICENSE`).
- Uperf — Apache-2.0, upstream Matt Yang, disertakan sesuai lisensi aslinya (`uperf/LICENSE`).

<details>
<summary>Komponen</summary>

- Alpha: hardware detection, profile management, monitor, watchdog, gameboost.
- Uperf: thread/cgroup classifier, config JSON per chipset di `uperf/config/`.
- fas-rs: frame-aware CPU scheduler, biner `fasrs/fas-rs`.

</details>

<details>
<summary>Guard</summary>

- Installer abort bila bukan ARM64.
- fas-rs nonaktif bila API <= 30.

</details>

<details>
<summary>Catatan build</summary>

8 file shell di-encode ke biner aarch64-only (`.bin`) + wrapper `.sh` tipis:

`common/monitor.sh`, `common/watchdog.sh`, `common/apply_now.sh`, `common/game_add.sh`, `common/engine_manager.sh`, `common/game_manager.sh`, `common/sync_uperf_exclusion.sh`, `bin/pgr-log`.

`common/render_manager.sh` tetap plaintext. Biner hanya jalan di ARM64.

</details>
