#!/system/bin/sh
# Alpha + Uperf Fusion - Late Start Service Entry Point
MODDIR="${0%/*}"

# M8: Tunggu boot completed, maksimal 120 detik (2x timeout).
# Bila gagal → skip tuning + daemon + log (boot-guard).
BOOT_WAIT=0
BOOT_TIMEOUT=40
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

# modul30: bersihkan state transient boost basi dari modul23/26 yang
# nyangkut di /data/adb/alpha dan ikut kebawa saat flash rilis/garapan
# (boost_level/.gb_active/cooldown/GAMEBOOST_LEVEL basi = boost salah
# level + restore ke nilai boost lama = kresek + ga stabil).
rm -f "$WORK_DIR/boost_level" "$WORK_DIR/.gb_active" "$WORK_DIR/.gb_cooldown_count" "$WORK_DIR/GAMEBOOST_LEVEL" 2>/dev/null
echo "[BOOT] transient boost state dibersihkan (modul30)" >> "$LOG_FILE"

BOOT_COMPLETED_OK=0
# M8: counter boot gagal 2x berturut-turut (file .boot_fail_count).
# Sukses (boot_completed=1) mereset counter ke 0.
BOOT_FAIL_FILE="$WORK_DIR/.boot_fail_count"
BOOT_FAIL_COUNT=$(cat "$BOOT_FAIL_FILE" 2>/dev/null | tr -cd '0-9')
case "$BOOT_FAIL_COUNT" in ''|*[!0-9]*) BOOT_FAIL_COUNT=0 ;; esac
if [ "$(getprop sys.boot_completed)" != "1" ]; then
    BOOT_FAIL_COUNT=$((BOOT_FAIL_COUNT + 1))
    printf '%s\n' "$BOOT_FAIL_COUNT" > "$BOOT_FAIL_FILE" 2>/dev/null
    if [ "$BOOT_FAIL_COUNT" -ge 2 ]; then
        echo "[M8] [WARN] boot gagal $BOOT_FAIL_COUNT x berturut-turut — BOOT-GUARD AKTIF" >> "$LOG_FILE"
        echo "[M8] [WARN] tuning + daemon DILEWATI (boot-guard). Modul tidak melakukan apapun." >> "$LOG_FILE"
    else
        echo "[M8] [INFO] sys.boot_completed tidak terdeteksi dalam 120 detik (gagal $BOOT_FAIL_COUNT x) — boot-guard belum aktif (perlu 2x berturut-turut)" >> "$LOG_FILE"
    fi
    echo "[M8] [INFO] Coba reboot atau cek boot_completed secara manual. Restart service setelah boot_completed=1." >> "$LOG_FILE"
else
    rm -f "$BOOT_FAIL_FILE" 2>/dev/null
    BOOT_COMPLETED_OK=1
    sleep 2
fi

# M8: DISABLE_TWEAKS kill-switch — bila file ini ada ATAU env=1,
# skip SEMUA tuning + daemon. User bisa menonaktifkan modul tanpa uninstall.
DISABLE_TWEAKS_FILE="$WORK_DIR/.disable_tweaks"
if [ "${DISABLE_TWEAKS:-0}" = "1" ] || [ -f "$DISABLE_TWEAKS_FILE" ]; then
    echo "[M8] [WARN] DISABLE_TWEAKS aktif — semua tuning + daemon DILEWATI" >> "$LOG_FILE"
    BOOT_COMPLETED_OK=0
fi

if [ "$BOOT_COMPLETED_OK" = "0" ]; then
    echo "=== Alpha boot-guard: skipped (boot_completed=$BOOT_COMPLETED_OK DISABLE_TWEAKS=${DISABLE_TWEAKS:-0}) ===" >> "$LOG_FILE"
    exit 0
fi

# 0.5 SF_LATCH_UNSIGNALED opt-in (default: OFF).
#     Hanya aktif bila file $WORK_DIR/SF_LATCH_UNSIGNALED ADA.
#     Sengaja dipindah dari system.prop supaya tidak default aktif.
SF_LATCH_FILE="$WORK_DIR/SF_LATCH_UNSIGNALED"
if [ -f "$SF_LATCH_FILE" ]; then
    setprop debug.sf.latch_unsignaled 1 2>/dev/null
    echo "[BOOT] SF_LATCH_UNSIGNALED: ON (file present)" >> "$LOG_FILE"
else
    setprop debug.sf.latch_unsignaled 0 2>/dev/null
    echo "[BOOT] SF_LATCH_UNSIGNALED: OFF (default)" >> "$LOG_FILE"
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

# 2.1 Load Defaults (M3/M4) — catat hardware defaults bila pertama kali
if [ -f "$MODDIR/common/defaults.sh" ]; then
    . "$MODDIR/common/defaults.sh"
    defaults_ensure
    echo "[BOOT] tahap defaults.sh selesai" >> "$LOG_FILE"
else
    echo "[WARN] defaults.sh tidak ditemukan, M3/M4 defaults skipped" >> "$LOG_FILE"
fi

# 3. Load Execution Engine
if [ -f "$MODDIR/common/engine.sh" ]; then
    . "$MODDIR/common/engine.sh"
    echo "[BOOT] tahap engine.sh selesai" >> "$LOG_FILE"
else
    echo "[ERROR] engine.sh tidak ditemukan!" >> "$LOG_FILE"
    exit 1
fi

# 3.1 Load GameBoost Engine (sumber gameboost.sh)
if [ -f "$MODDIR/common/gameboost.sh" ]; then
    . "$MODDIR/common/gameboost.sh"
    echo "[BOOT] tahap gameboost.sh selesai" >> "$LOG_FILE"
    # Re-read native_boost.conf jika sudah ada (backup asli)
    if [ -f "$WORK_DIR/native_boost.conf" ]; then
        echo "[BOOT] native_boost.conf ditemukan, backup asli siap" >> "$LOG_FILE"
    fi
else
    echo "[WARN] gameboost.sh tidak ditemukan, gameboost disabled" >> "$LOG_FILE"
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

# M2: CPU Ownership — deteksi fas-rs vs Alpha fallback
# Bila fas-rs hidup → powercfg.sh; bila mati → tune_cpu_freq fallback
# dengan minimum 50% hardware_max, Performance = maksimum.
if [ -f "$MODDIR/common/cpu_owner.sh" ]; then
    . "$MODDIR/common/cpu_owner.sh"
    cpu_detect_owner
    echo "[M2] CPU_OWNER=$CPU_OWNER" >> "$LOG_FILE"
else
    echo "[M2] cpu_owner.sh tidak ditemukan, skip CPU ownership detect" >> "$LOG_FILE"
fi

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
    setprop fas-rs-installed true 2>/dev/null

    # M6: until fas-rs ≤60 detik (bukan tak terbatas)
    _fasrs_wait=0
    _fasrs_ok=0
    until [ -d "$FASRS_DIR" ]; do
        sleep 1
        _fasrs_wait=$((_fasrs_wait + 1))
        if [ "$_fasrs_wait" -ge 60 ]; then
            echo "[WARN] M6: fas-rs dir ($FASRS_DIR) tidak muncul dalam 60s, skip" >> "$LOG_FILE"
            _fasrs_ok=1
            break
        fi
    done

    if [ "$_fasrs_ok" = "0" ] && [ -f "$FASRS_MERGE_FLAG" ]; then
        "$MODDIR/fasrs/fas-rs" merge "$MODDIR/fasrs/games.toml" > "$FASRS_DIR/.update_games.toml"
        rm -f "$FASRS_MERGE_FLAG"
        mv -f "$FASRS_DIR/.update_games.toml" "$FASRS_DIR/games.toml"
    fi

    if [ "$_fasrs_ok" = "0" ]; then
        killall fas-rs 2>/dev/null
        RUST_BACKTRACE=1 nohup "$MODDIR/fasrs/fas-rs" run "$MODDIR/fasrs/games.toml" >> "$FASRS_LOG" 2>&1 &
        echo "[INFO] fas-rs scheduler started pid=$!" >> "$LOG_FILE"
    else
        echo "[WARN] fas-rs scheduler tidak dijalankan (FASRS_DIR timeout 60s)" >> "$LOG_FILE"
    fi
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
