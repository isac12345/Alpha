# TESTING — Alpha Fusion v1 (versionCode 20)

Checklist uji rilis publik. Perangkat: ARM64 sudah root, Magisk terpasang.
APK pendamping ada di zip rilis di bawah `companion/`, versionCode 20.

## 1. Flash + reboot
1. Flash zip rilis di Magisk, lalu reboot.
   Hasil yang diharapkan: modul tampil aktif di Magisk setelah reboot.
2. Periksa log modul di direktori log perangkat (`alpha.log`).
   Hasil yang diharapkan: log ada dan menunjukkan engine jalan tanpa abort.

## 2. Profil
1. Ganti profil Battery -> Balanced -> Performance.
   Hasil yang diharapkan: nama profil aktif berubah; notifikasi mengikuti.
2. Terapkan ulang profil yang sama.
   Hasil yang diharapkan: tanpa error; governor/freq tetap satu pemilik.

## 3. Daftar game + PID fas-rs
1. Tambah satu game, catat PID fas-rs, lalu hapus game tersebut.
   Hasil yang diharapkan: PID fas-rs berubah setelah tambah maupun hapus.
2. Tambah game saat game sedang berjalan (live add).
   Hasil yang diharapkan: daftar berubah tanpa reboot dan tanpa crash.

## 4. Background kustom Fill / Fit (ringkasan)
1. Pilih gambar kustom, buka editor background.
   Hasil yang diharapkan: hanya lingkaran Fill yang terisi default; simpan sukses, tanpa FC.
2. Ketuk Fit, lalu Fill lagi, simpan di tiap mode.
   Hasil yang diharapkan: hanya mode yang diketuk yang tetap terisi; gambar tersimpan di keduanya.
3. Periksa log untuk baris fallback metrics-nol `cropRatio`.
   Hasil yang diharapkan: tanpa fallback metrics-nol; Fill penuh sampai sudut, Fit utuh.

## 5. Aplikasi pendamping
1. APK companion dari zip rilis (terpasang otomatis saat flash; konfirmasi manual bila diminta Android).
   Hasil yang diharapkan: versionCode terpasang 20; kartu, bubble, GameBoost jalan.
2. Periksa resolusi, dexopt, tampil/sembunyi floating bubble.
   Hasil yang diharapkan: semua normal; ketuk notifikasi persisten memunculkan floating.

## 6. Uninstall
1. Hapus modul di Magisk (atau via jalur uninstall.sh), lalu reboot.
   Hasil yang diharapkan: modul hilang; perilaku config/governor bawaan pulih.
