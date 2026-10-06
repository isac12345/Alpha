# Alpha Fusion

Modul root untuk mengatur performa HP Android. Isinya gabungan Alpha, Uperf, dan fas-rs, dengan tiga profil: **Daily** (hemat), **Balanced**, dan **Perf**. Pengaturannya lewat aplikasi **Alpha Control** yang ikut terpasang.

Diuji di Unisoc T606. Di chipset lain belum dites.

## Syarat
- HP sudah root (Magisk, KernelSU, atau APatch)
- Android 8 ke atas (fas-rs butuh Android 12 ke atas, kalau tidak didukung otomatis dilewati)

## Pasang
1. Unduh `Alpha-Fusion-v2.zip` dari [Releases](../../releases).
2. Flash lewat Magisk/KernelSU/APatch, lalu reboot.
3. Buka **Alpha Control**, beri izin root.

Kalau aplikasinya tidak muncul, pasang `AlphaControl-v2.apk` dari Releases secara manual.

## Pemakaian
- **Ganti profil**: dari aplikasi, bubble mengambang, notifikasi, atau tile Quick Settings.
- **Game**: tambahkan di tab Games. Saat game dibuka, profil game dipakai otomatis.
- **Auto-profile**: pindah profil sendiri saat baterai rendah atau sedang dicas.
- **Proteksi suhu**: turunkan profil kalau HP terlalu panas.
- **Alat lain**: ganti render, resolusi, dexopt, tutup semua app, dan lihat log.

## Update
Flash zip versi baru, reboot. Kalau aplikasinya tidak ikut ter-update, pasang APK-nya manual.

## Kalau bermasalah
- Bootloop: setelah 2 kali gagal boot, tuning dilewati otomatis. Bisa juga hapus modul lewat recovery.
- Aplikasi tidak bisa dipasang karena tanda tangan beda: uninstall dulu, lalu pasang lagi.
- Salin log dari Alpha Control (Tools > Salin) saat melapor.

## Hapus
Hapus modul di manager root, lalu reboot.

## Kredit
Alpha oleh somwan. Uperf oleh Matt Yang dan yinwanxi. fas-rs oleh shadow3 dan shadow3aaa.

Catatan teknis untuk pengembang ada di [docs/DEV.md](docs/DEV.md). Lisensi: lihat `LICENSE`.
