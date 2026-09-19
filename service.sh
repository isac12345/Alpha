#!/system/bin/sh
# Alpha + Uperf Fusion - Late Start Service Entry Point
MODDIR="${0%/*}"

# Tunggu sampai boot completed sempurna (maksimal 60 detik)
BOOT_WAIT=0
BOOT_TIMEOUT=20
until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$BOOT_WAIT" -ge "$BOOT_TIMEOUT" ]; do
    sleep 3
    BOOT_WAIT=$((BOOT_WAIT + 1))
done

WORK_DIR="${ALPHA_WORK_DIR:-/data/adb/alpha}"
mkdir -p "$WORK_DIR"
LOG_FILE="$WORK_DIR/alpha.log"
export ALPHA_LOG_FILE="$LOG_FILE"
export ALPHA_CONF_DIR="$WORK_DIR"

echo "=== Alpha + Uperf Fusion Starting Boot Service: $(date) ===" >> "$LOG_FILE"
echo "[BOOT] boot service dimulai (MODDIR=$MODDIR WORK_DIR=$WORK_DIR)" >> "$LOG_FILE"

if [ "$(getprop sys.boot_completed)" != "1" ]; then
    echo "[WARN] sys.boot_completed tidak terdeteksi dalam 60 detik, melanjutkan eksekusi..." >> "$LOG_FILE"
else
    sleep 2
fi

# 1. Load Hardware Detection (atau baca cache)
if [ -f "$MODDIR/common/detect.sh" ]; then
    . "$MODDIR/common/detect.sh"
    echo "[BOOT] tahap detect.sh selesai" >> "$LOG_FILE"
else
    echo "[ERROR] detect.sh tidak ditemukan!" >> "$LOG_FILE"
    exit 1
fi

# 2. Load Profiles
if [ -f "$MODDIR/common/profiles.sh" ]; then
    . "$MODDIR/common/profiles.sh"
    echo "[BOOT] tahap profiles.sh selesai" >> "$LOG_FILE"
else
    echo "[ERROR] profiles.sh tidak ditemukan!" >> "$LOG_FILE"
    exit 1
fi

# 3. Load Execution Engine
if [ -f "$MODDIR/common/engine.sh" ]; then
    . "$MODDIR/common/engine.sh"
    echo "[BOOT] tahap engine.sh selesai" >> "$LOG_FILE"
else
    echo "[ERROR] engine.sh tidak ditemukan!" >> "$LOG_FILE"
    exit 1
fi

echo "[INIT] SoC Vendor terdeteksi: $SOC_VENDOR" >> "$LOG_FILE"
echo "[INIT] CPU Policies: $CPU_POLICIES" >> "$LOG_FILE"
echo "[INIT] Storage Devices: $STORAGE_DEVICES" >> "$LOG_FILE"

# 4. Jalankan Tweak Sesuai Arsitektur
# CATATAN MERGE: tune_governor & tune_cpu_freq SENGAJA TIDAK dipanggil di sini.
# Uperf punya warning eksplisit dari developernya sendiri bahwa modul ini akan
# konflik dengan modul limit-freq/optimasi lain, dan melarang user mengubah
# governor sendiri. Supaya fas-rs yang pegang penuh kontrol governor/freq
# tanpa rebutan, fungsi ini tetap ada di engine.sh (referensi) tapi tidak
# dieksekusi di sini.
#
# tune_boost_silencer JUGA SENGAJA TIDAK dipanggil: fungsi ini menulis ke
# mtk_fpsgo/perfmgr/perfmgr_mtk/migt parameters - node yang PERSIS SAMA
# dipegang & dikelola dinamis oleh binary fas-rs sendiri di perangkat MTK.
# Static write sekali boot dari Alpha akan rebutan dengan kontrol real-time
# fas-rs, jadi domain ini diserahkan 100% ke fas-rs.
tune_devfreq
tune_io
tune_vm
tune_thermal
tune_network
tune_gpu

# 5. Tulis Ringkasan Eksekusi
echo "=== Alpha + Uperf Fusion Optimization Complete ===" >> "$LOG_FILE"
echo "Applied: $APPLIED_COUNT | Skipped: $SKIPPED_COUNT | Failed: $FAILED_COUNT" >> "$LOG_FILE"
echo "======================================" >> "$LOG_FILE"
echo "[BOOT] tahap tuning selesai (applied=$APPLIED_COUNT skipped=$SKIPPED_COUNT failed=$FAILED_COUNT)" >> "$LOG_FILE"

# 6. Persist initial manual profile after boot apply
ACTIVE_PROFILE_FILE="$WORK_DIR/active_profile"
CURRENT_STATE_FILE="$WORK_DIR/current_state"
BOOT_PROFILE="balanced"
if [ -f "$ACTIVE_PROFILE_FILE" ]; then
    candidate_profile=$(tr -d '[:space:]' < "$ACTIVE_PROFILE_FILE" 2>/dev/null)
    case "$candidate_profile" in
        battery|balanced|performance) BOOT_PROFILE="$candidate_profile" ;;
    esac
fi
load_profile "$BOOT_PROFILE"
state_tmp="$CURRENT_STATE_FILE.tmp.$$"
if printf '%s\n' "$ACTIVE_PROFILE" > "$state_tmp" && mv -f "$state_tmp" "$CURRENT_STATE_FILE" 2>/dev/null; then
    echo "[INIT] current_state=$ACTIVE_PROFILE" >> "$LOG_FILE"
else
    rm -f "$state_tmp" 2>/dev/null
    echo "[ERROR] gagal menulis current_state awal" >> "$LOG_FILE"
fi

# 7. Start monitor once, without blocking late_start service
MONITOR_PID_FILE="$WORK_DIR/monitor.pid"
monitor_running=0
if [ -f "$MONITOR_PID_FILE" ]; then
    monitor_pid=$(tr -d '[:space:]' < "$MONITOR_PID_FILE" 2>/dev/null)
    if [ -n "$monitor_pid" ] && kill -0 "$monitor_pid" 2>/dev/null && [ -r "/proc/$monitor_pid/cmdline" ]; then
        monitor_cmd=$(tr '\000' ' ' < "/proc/$monitor_pid/cmdline" 2>/dev/null)
        case "$monitor_cmd" in
            *monitor.sh*) monitor_running=1 ;;
        esac
    fi
fi

if [ "$monitor_running" = "1" ]; then
    echo "[INFO] monitor.sh sudah berjalan pid=$monitor_pid" >> "$LOG_FILE"
else
    rm -f "$MONITOR_PID_FILE" 2>/dev/null
    ALPHA_STATE_DIR="$WORK_DIR"
    export ALPHA_STATE_DIR
    nohup sh "$MODDIR/common/monitor.sh" >> "$LOG_FILE" 2>&1 &
    monitor_pid=$!
    printf '%s\n' "$monitor_pid" > "$MONITOR_PID_FILE"
    echo "[INFO] monitor.sh started pid=$monitor_pid" >> "$LOG_FILE"
fi
echo "[BOOT] tahap monitor.sh selesai (pid=$monitor_pid)" >> "$LOG_FILE"

# 7.1 Watchdog ringan untuk monitor.sh (cek tiap ±3 menit, restart
#     otomatis kalau mati di luar skenario normal — bukan nunggu reboot).
WATCHDOG_PID_FILE="$WORK_DIR/watchdog.pid"
watchdog_running=0
if [ -f "$WATCHDOG_PID_FILE" ]; then
    watchdog_pid=$(tr -d '[:space:]' < "$WATCHDOG_PID_FILE" 2>/dev/null)
    if [ -n "$watchdog_pid" ] && kill -0 "$watchdog_pid" 2>/dev/null && [ -r "/proc/$watchdog_pid/cmdline" ]; then
        watchdog_cmd=$(tr '\000' ' ' < "/proc/$watchdog_pid/cmdline" 2>/dev/null)
        case "$watchdog_cmd" in
            *watchdog.sh*) watchdog_running=1 ;;
        esac
    fi
fi

if [ "$watchdog_running" = "1" ]; then
    echo "[INFO] watchdog.sh sudah berjalan pid=$watchdog_pid" >> "$LOG_FILE"
else
    rm -f "$WATCHDOG_PID_FILE" 2>/dev/null
    ALPHA_STATE_DIR="$WORK_DIR"
    export ALPHA_STATE_DIR
    nohup sh "$MODDIR/common/watchdog.sh" >> "$LOG_FILE" 2>&1 &
    watchdog_pid=$!
    printf '%s\n' "$watchdog_pid" > "$WATCHDOG_PID_FILE"
    echo "[INFO] watchdog.sh started pid=$watchdog_pid" >> "$LOG_FILE"
fi
echo "[BOOT] tahap watchdog.sh selesai (pid=$watchdog_pid)" >> "$LOG_FILE"

# 7.5 Sinkronkan [game_list] fas-rs games.toml -> exclusion rule uperf.json.
#     Package yang sudah didaftarkan ke fas-rs (edit langsung di games.toml)
#     otomatis dilewati oleh classifier cpuset uperf, jadi user cukup atur di
#     satu tempat: ADA di [game_list] = dipegang fas-rs, TIDAK ADA = tetap uperf.
UPERF_USER_PATH="/sdcard/Android/yc/uperf"
if [ -f "$MODDIR/common/sync_uperf_exclusion.sh" ]; then
    sync_wait=0
    while [ ! -f "$UPERF_USER_PATH/uperf.json" ] && [ "$sync_wait" -lt 15 ]; do
        sleep 1
        sync_wait=$((sync_wait + 1))
    done
    sh "$MODDIR/common/sync_uperf_exclusion.sh" "$MODDIR/fasrs/games.toml" "$UPERF_USER_PATH/uperf.json"
    echo "[INFO] sync_uperf_exclusion selesai (game_list -> exclusion uperf)" >> "$LOG_FILE"
fi
echo "[BOOT] tahap sync_uperf_exclusion selesai" >> "$LOG_FILE"

# 7.6 One-shot install AsoulOpt (thread-affinity daemon) saat boot pertama.
#     Ditunda ke sini (bukan customize.sh) supaya tidak nested-install di
#     tengah proses instalasi modul ini sendiri, dan supaya boot sudah
#     completed (syarat ksud module install). Flag mencegah percobaan ulang.
if [ -f "$MODDIR/common/asoulopt_install.sh" ]; then
    . "$MODDIR/common/asoulopt_install.sh"
    asoulopt_msg() { echo "[AsoulOpt] $1" >> "$LOG_FILE"; }
    asoulopt_install_once "$MODDIR/uperf/asoulopt-staged.zip" "$WORK_DIR/.asoulopt_installed" ||
        echo "[AsoulOpt] percobaan gagal, akan dicoba lagi saat boot berikutnya" >> "$LOG_FILE"
else
    echo "[AsoulOpt] helper asoulopt_install.sh tidak ditemukan, dilewati" >> "$LOG_FILE"
fi
echo "[BOOT] tahap asoulopt selesai" >> "$LOG_FILE"

# 7.7 One-shot install Companion APK (Alpha Control) kalau customize.sh
#     belum sempat (flash via recovery: pm tidak tersedia saat instalasi).
#     Guard versi: skip kalau sudah current, tidak pernah downgrade,
#     tidak mengganggu preferensi user. Flag mencegah percobaan ulang
#     setelah sukses.
if [ -f "$MODDIR/common/companion_install.sh" ]; then
    . "$MODDIR/common/companion_install.sh"
    if alpha_companion_install_once "$MODDIR/companion/AlphaBubble.apk" "$WORK_DIR/.companion_installed"; then
        echo "[BOOT] tahap companion app selesai (terpasang/up-to-date)" >> "$LOG_FILE"
    else
        echo "[BOOT] tahap companion app ditunda (pm belum siap, coba boot berikut)" >> "$LOG_FILE"
    fi
fi

# 8. Jalankan backend Uperf (thread/cgroup classifier only) di background.
#    Terpisah dari alur di atas supaya wait_until_login miliknya (nunggu
#    /sdcard bisa diakses) tidak memblokir monitor Alpha.
if [ -f "$MODDIR/uperf/script/run_uperf.sh" ]; then
    nohup sh "$MODDIR/uperf/script/run_uperf.sh" >> "$LOG_FILE" 2>&1 &
    echo "[INFO] uperf backend runner started pid=$!" >> "$LOG_FILE"
fi
echo "[BOOT] tahap uperf distart" >> "$LOG_FILE"

# 9. Jalankan fas-rs (frame-aware CPU scheduler, eBPF). Ini SATU-SATUNYA
#    komponen yang boleh mengendalikan governor/scaling freq di modul ini -
#    Alpha & Uperf sudah dikonfigurasi untuk tidak menyentuh domain tersebut.
#    Logika persis mengikuti service.sh asli fas-rs (merge config, dsb),
#    cuma path-nya di-namespace ke $MODDIR/fasrs/.
FASRS_DIR="/sdcard/Android/fas-rs"
FASRS_MERGE_FLAG="$FASRS_DIR/.need_merge"
FASRS_LOG="$FASRS_DIR/fas_log.txt"

FASRS_API="$(getprop ro.build.version.sdk)"
FASRS_KREL="$(uname -r)"
FASRS_KERNEL_OK=1
if echo "$FASRS_KREL" | awk -F. '{exit !( $1 < 5 || ($1 == 5 && $2 < 8) )}'; then
    FASRS_KERNEL_OK=0
fi

if [ -x "$MODDIR/fasrs/fas-rs" ] && [ "${FASRS_API:-0}" -gt 30 ] 2>/dev/null && [ "$FASRS_KERNEL_OK" = "1" ]; then
    sh "$MODDIR/fasrs/init_vtools.sh" "$(realpath "$MODDIR/module.prop")" 2>/dev/null
    resetprop fas-rs-installed true 2>/dev/null

    until [ -d "$FASRS_DIR" ]; do
        sleep 1
    done

    if [ -f "$FASRS_MERGE_FLAG" ]; then
        "$MODDIR/fasrs/fas-rs" merge "$MODDIR/fasrs/games.toml" > "$FASRS_DIR/.update_games.toml"
        rm -f "$FASRS_MERGE_FLAG"
        mv -f "$FASRS_DIR/.update_games.toml" "$FASRS_DIR/games.toml"
    fi

    killall fas-rs 2>/dev/null
    RUST_BACKTRACE=1 nohup "$MODDIR/fasrs/fas-rs" run "$MODDIR/fasrs/games.toml" >> "$FASRS_LOG" 2>&1 &
    echo "[INFO] fas-rs scheduler started pid=$!" >> "$LOG_FILE"
else
    echo "[WARN] fas-rs dilewati (binary tidak ada, atau syarat API/kernel tidak terpenuhi: API=$FASRS_API kernel=$FASRS_KREL)." >> "$LOG_FILE"
fi
echo "[BOOT] tahap fas-rs distart" >> "$LOG_FILE"

# 10. Re-apply render backend pilihan user (persist di render_backend.conf).
if [ -f "$MODDIR/common/render_manager.sh" ]; then
    sh "$MODDIR/common/render_manager.sh" apply >> "$LOG_FILE" 2>&1
    echo "[INFO] render backend re-apply selesai" >> "$LOG_FILE"
fi
echo "[BOOT] boot service selesai penuh" >> "$LOG_FILE"

exit 0
