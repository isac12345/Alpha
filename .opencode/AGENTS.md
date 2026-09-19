# AGENTS.md — Global Rules (singkat, padat)

Aturan di bawah berlaku untuk SEMUA sesi dan SEMUA proyek. Aturan paling penting di atas.

## 1. Anti-halusinasi (wajib)

1. Jangan mengarang. Baca file (`read`) atau jalankan perintah (`bash`) dulu sebelum mengklaim apa pun.
2. Jangan mengarang nama fungsi, flag, path, atau API. Cek dengan `grep`/`glob` atau dokumentasi resmi. Kalau tidak yakin, bilang tidak tahu.
3. Sebutkan bukti untuk klaim penting: `file:baris` atau output perintah.
4. Sebelum mengedit file, baca ulang file itu. Jangan mengandalkan ingatan.
5. Sebelum jawaban final, cek ulang jawaban sendiri dan tandai klaim yang belum ada buktinya.

## 2. Verifikasi sebelum klaim selesai

1. Jangan bilang "selesai" sebelum test/build/lint dijalankan dan hasilnya benar.
2. Laporkan apa adanya: apa yang dijalankan, apa yang gagal, apa yang belum diverifikasi.
3. Kalau perbaikan gagal 3x dengan cara yang sama, berhenti: jelaskan yang sudah dicoba, ganti pendekatan atau tanya user.

## 3. pesticide

1. Kalau permintaan ambigu, tanya via `question` sebelum menulis kode.
2. Untuk tugas non-trivial (3+ langkah), tulis rencana singkat via `todowrite` dulu, tepat SATU `in_progress`.

## 4. Sistem anti-lupa (per proyek)

Di awal setiap sesi, baca `PLAN.md`, `STATE.md`, `NOTES.md` kalau ada di proyek.

- `PLAN.md`: checklist langkah tugas besar, centang yang selesai.
- `STATE.md`: sedang mengerjakan apa, file apa yang diubah, apa yang sudah/belum diverifikasi. Update tiap selesai satu langkah.
- `NOTES.md`: keputusan penting, bug yang ketemu (gejala → akar masalah → solusi), hal yang jangan diulang.
- Kerjakan tugas besar per bagian kecil, verifikasi tiap bagian sebelum lanjut.
- Sebelum perubahan besar: `git commit` atau `git stash` supaya bisa rollback. Jangan menimpa file tanpa backup.

## 5. Alur kerja standar

`explorer` → `planner` → implementasi → `tester` → `reviewer` → kalau ada masalah, `debugger` → ulangi sampai lolos.
Delegasikan ke subagent supaya konteks agent utama tetap bersih.

## 6. Batasan Termux/Android

- Cek script dengan `bash -n` dan `shellcheck` sebelum eksekusi.
- Jangan pakai perintah yang tidak ada di Termux. Kalau ragu, cek dengan `command -v <nama>`.
- Perintah destruktif (`rm -rf`, `dd`, `mkfs`, format) wajib konfirmasi user dulu.

## 7. Aturan build modul fusion-v2 (permanen, 2026-09-19)

- DILARANG menjalankan gradle, gradlew, npm install, apktool, atau build/compile apa pun di Termux. Semua kompilasi lewat GitHub Actions.
- Di Termux hanya boleh edit teks, git, dan gh.
- Alur tiap perubahan: edit, commit, push, gh workflow run, gh run watch, download hanya hasil akhirnya (zip/APK).
- Baca STATE.md, PLAN.md, dan NOTES.md di awal setiap sesi. Setelah tiap langkah selesai: update STATE.md, commit, push.
- Hapus APK/zip lama yang sudah tidak dipakai setelah versi baru terpasang.
