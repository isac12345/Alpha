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
