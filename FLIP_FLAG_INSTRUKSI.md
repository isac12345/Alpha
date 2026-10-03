# Cara lanjut: aktifkan GB_COOLDOWN_EXTREME (tanpa flash APK)
# 1. Di HP (root):
su -c 'touch /data/adb/alpha/GB_COOLDOWN_EXTREME /data/adb/alpha/GB_FASRS_OWNS_CPU'
# 2. Restart modul (tanpa reboot):
#     su -c 'pkill -9 uperf; kill -STOP $(pidof fas-rs)'; sleep 1; su -c 'sh /data/adb/modules/alpha_uperf_fasrs_fusion/service.sh restart'
# 3. Atau reboot pintar (reset semua): reboot; setelah login kembali, jadikan
#    /data/adb/alpha/GB_COOLDOWN_EXTREME masih ada (persistent di /data/adb).
# 4. Main PGR 30 menit, screenshot FPS (SurfaceFlinger latency)
#
# ARMS A/B (30 menit, baterai >35%, JANGAN pindah app untuk screenshot):
# Arm A (baseline v45):  [saat ini sudah jalan]
# Arm B (NO_CPUSET): touch /data/adb/alpha/NO_CPUSET; main lagi; dibandingkan.
