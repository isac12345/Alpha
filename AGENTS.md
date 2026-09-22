# AGENTS.md — Alpha Fusion v1 (fusion-v2)

1. Tim: leader (primary, koordinasi + merge) + dev-apk (subagent,
   APK) + dev-modul (subagent, skrip modul). Skill: writing-plans,
   subagent-driven-development, requesting/receiving-code-review,
   systematic-debugging, verification-before-completion +
   smali-patching, apk-pipeline, shell-sandbox,
   android-static-verify, magisk-module-debug, shell-safety.
2. Kepemilikan: dev-apk = apk-patches/, java/, apk-overlay/,
   workflow APK; dev-modul = common/, uperf/, fasrs/, skrip
   modul di root. Kerja di cabang work/<id>. Master tidak
   disentuh; merge ke fusion-v2 hanya oleh leader.
3. DILARANG sentuh perangkat: tanpa pm install, menjalankan
   aplikasi, input, screenshot, su, tulis /sys|/proc, reboot,
   flash. Tanpa build di Termux (edit teks, git, gh). Versi v1.
4. Alur leader: brief (tujuan, file, kriteria, bukti) → Task ke
   dev → review diff + verifikasi statis → TERIMA / REVISI
   (maks 2) / KOREKSI ≤20 baris. Gagal 2x → catat di NOTES.md.
5. DILARANG mencetak/commit secret (dari config/Actions saja).
   Tanpa force push. Update STATE.md tiap tugas selesai.
6. Gagal model dev (429/tumbang): JANGAN ganti model (baru
   berlaku setelah restart). Hentikan item itu, commit WIP
   di work/<id>, tulis agent + error persis di STATE.md,
   lanjut item lain yg tak bergantung, lalu lapor; user
   yg ganti model + restart. (Pengecualian hanya bila
   instruksi tugas eksplisit mengizinkan + dicatat di NOTES.md.)
7. Pekerja Task berbagi working tree: DILARANG checkout/reset
   cabang di repo utama (28 Sep 2026: reset pekerja menghapus
   edit leader yang belum commit). Gunakan `git worktree` atau
   kerja di cabang tanpa pindah HEAD utama.
8. Arsip fix + verifikasi 2 langkah (aturan permanen 2026-09-22,
   perintah user — user pelupa, jadi ini wajib tiap perbaikan).
   Status tiap perbaikan: TUNGGU -> L1 -> L2 -> ARSIP. Dilarang loncat.
   - L1 = verifikasi teknis oleh leader, WAJIB bukti konkret
     (ID run CI hijau + output: versionCode/grep/test). Tanpa bukti
     = belum selesai, jujur tulis begitu.
   - L2 = user tes di HP + bilang OK ("alhamdulillah", "udah",
     perintah rilis, dsb). Tanpa ini status tetap "tunggu HP test".
   - Hanya item L2 yang masuk: (a) FIXLOG.md lokal (= "otak":
     satu entri per item: tanggal, apa, bukti L1, bukti L2,
     bahasa sederhana), (b) repo arsip isac12345/modulroot
     (remote `arsip`; `git push arsip <cabang>` + FIXLOG.md ikut).
     Yang belum L2 DILARANG masuk arsip.
   - Tanpa force push ke mana pun. Push arsip gagal fast-forward
     = lapor ke user, jangan dipaksa.

## Khusus Alpha (project ini)
- Stack: modul Magisk (Alpha + Uperf + fas-rs Fusion) untuk device root Unisoc + GPU Mali, plus APK Kotlin View/XML (AGP 8.3.2). Kelas utama: MainActivity, RootShell, BubbleService/FloatingBubbleService, ProfileTileService (QS tile), AddGameDialog, GamesFragment.
- Nama produk "Alpha" (BUKAN "Alpha Bubble"): label, nama file APK, notifikasi, service.
- DILARANG: mengganti atau menghapus ikon APK, ikon launcher/notifikasi, dan banner default (sudah final). Semua ikon ikut ikon APK yang ada.
- Target redesign: home dipecah beberapa page/nav, tema hitam-putih ringan (tidak jadul/abu-abu), APK seringan mungkin, background custom tidak stretch (crop/fit), floating bubble profil (Battery/Balanced/Perf) dengan notifikasi persisten profil aktif (tap = munculkan floating, long-press floating = sembunyikan).
- Build: Gradle lokal di Termux gagal (Maven/Google 403). Build/verifikasi lewat GitHub Actions. Jangan sentuh secret keystore dan config signing.
- RootShell: setiap perintah root wajib punya timeout, cek exit code, dan quoting aman.
- Jalur kerja: dev-apk untuk APK, dev-modul untuk modul/backend tweak, leader memeriksa. Fitur baru dianggap belum teruji sampai user test di device.
