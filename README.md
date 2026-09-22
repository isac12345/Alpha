# Alpha Fusion v1

Magisk/Zygisk module: Alpha + Uperf + fas-rs fusion.

## Teruji hardware

- Unisoc T615 (ums9230), GPU Mali, Android 14 / SDK 34, 720x1600 density 320.

## Kompatibilitas chipset lain

- MediaTek modern (terdeteksi otomatis via chipset dengan devfreq GPU, tanpa
  /proc/ppm): NILAI TUNING sudah disesuaikan proporsional (persentase dari
  cpuinfo_max_freq, snap ke tabel OPP, devfreq generik *.gpu/*.mali), TAPI
  baru diverifikasi lewat simulasi/sandbox — BELUM pernah dites
  tulis-baca-restore langsung di hardware MTK asli. Silakan coba dan laporkan
  Issue kalau ada masalah (freq tidak berubah, crash, overheat, dll),
  sertakan output getprop dan ls /sys/class/thermal/.
- MediaTek legacy (masih ada /proc/ppm atau /proc/gpufreq): belum didukung
  (jatuh ke fallback aman, tuning gameboost dilewati).
- Adreno / Snapdragon: cap GPU pakai pola Mali (sandbox saja).
- PowerVR / Xclipse: kode di-skip (detect mengembalikan UNKNOWN).

## Guard

- Installer abort bila bukan ARM64.
- fas-rs nonaktif bila API <= 30 (Android < 12).

## APK pendamping

- Alpha Control (AlphaBubble.apk): versionName v1, versionCode internal = 20.

## Komponen

- **Alpha**: hardware detection, profile management, monitor, watchdog, gameboost.
- **Uperf**: thread/cgroup classifier (config JSON per chipset).
- **fas-rs**: frame-aware CPU scheduler, eBPF, pemegang tunggal governor/freq.

## Lisensi

- Uperf: Apache-2.0 (Matt Yang) — lihat `uperf/LICENSE`.
- fas-rs: GPL-3.0 (shadow3aaa) — lihat `fasrs/LICENSE`.

## Catatan Build

8 file shell di-encode ke binary aarch64-only (`.bin`):
`common/monitor.sh`, `common/watchdog.sh`, `common/apply_now.sh`,
`common/game_add.sh`, `common/engine_manager.sh`, `common/game_manager.sh`,
`common/sync_uperf_exclusion.sh`, `bin/pgr-log`.

`common/render_manager.sh` tetap plain text (shc+mksh tidak kompatibel
untuk source-engine di dalam fungsi — binary menghasilkan error
"restricted").

Wrapper tipis tetap menggunakan nama `.sh` asli.
Binary hanya bisa dijalankan di perangkat ARM64.
