#!/system/bin/sh
# Alpha Fusion - CPU Ownership Detection (M2)
# Deteksi siapa yang menguasai CPU governor/freq: fas-rs atau Alpha fallback.
# Dipanggil dari service.sh / apply_now.sh SETELAH detect.sh + profiles.sh load.
#
# Output global:
#   CPU_OWNER = "fas-rs" | "alpha"
#   (dan memanggil fas-rs powercfg.sh bila fas-rs aktif)
#
# Mekanisme:
#   1. Cek /dev/fas_rs/mode (node kontrol fas-rs) — bila node ada DAN
#      executable, anggap fas-rs aktif.
#   2. Fallback: cek proses fas-rs via pidof/killall (bila binary ada tapi
#      node belum ready — race saat boot awal).
#   3. Bila kedua-duanya mati → Alpha memegang CPU freq via tune_cpu_freq.

_cpu_owner_log() {
    local _status="$1"
    local _msg="$2"
    local _ts
    _ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    printf '%s\n' "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)] [CPU_OWNER] [$_status] $_msg" >> "$LOG_FILE" 2>/dev/null
}

cpu_detect_owner() {
    local fasrs_mode="/dev/fas_rs/mode"
    local fasrs_binary=""

    # Cari binary fas-rs (beberapa path umum)
    for _cand in /system/bin/fas-rs /data/adb/modules/*/fasrs/fas-rs \
                 /data/adb/ksu/modules/*/fasrs/fas-rs \
                 "${MODDIR:-/data/adb/modules/alpha_uperf_fasrs_fusion}/fasrs/fas-rs"; do
        if [ -x "$_cand" ] 2>/dev/null; then
            fasrs_binary="$_cand"
            break
        fi
    done

    # Prioritas 1: node /dev/fas_rs/mode ada & readable
    if [ -r "$fasrs_mode" ]; then
        CPU_OWNER="fas-rs"
        _cpu_owner_log "INFO" "fas-rs aktif (node $fasrs_mode readable)"
        _cpu_apply_powercfg
        return 0
    fi

    # Prioritas 2: proses fas-rs hidup
    if pidof fas-rs >/dev/null 2>&1 || killall -0 fas-rs 2>/dev/null; then
        CPU_OWNER="fas-rs"
        _cpu_owner_log "INFO" "fas-rs aktif (proses berjalan)"
        _cpu_apply_powercfg
        return 0
    fi

    # Fallback: Alpha memegang CPU freq
    CPU_OWNER="alpha"
    _cpu_owner_log "INFO" "fas-rs tidak aktif, Alpha mengambil alih CPU freq (fallback)"
    _cpu_apply_alpha_freq
    return 0
}

# Mapp profil Alpha → mode fas-rs via powercfg.sh:
#   battery → powersave, balanced → balance,
#   performance + boost aktif → fast, performance tanpa boost → performance
# "boost aktif" = file $STATE_DIR/boost_level ada (ditulis oleh gb_apply).
_cpu_apply_powercfg() {
    local _mode=""
    local _conf_dir="${ALPHA_STATE_DIR:-${ALPHA_CONF_DIR:-/data/adb/alpha}}"
    case "${ACTIVE_PROFILE:-balanced}" in
        battery)
            _mode="powersave"
            ;;
        balanced)
            _mode="balance"
            ;;
        performance)
            if [ -f "$_conf_dir/boost_level" ]; then
                _mode="fast"
            else
                _mode="performance"
            fi
            ;;
        *)
            _mode="balance"
            ;;
    esac

    # Cari powercfg.sh — path fas-rs standar
    local _pcfg=""
    for _cand in /data/powercfg.sh \
                 "${MODDIR:-/data/adb/modules/alpha_uperf_fasrs_fusion}/fasrs/powercfg.sh"; do
        if [ -f "$_cand" ] 2>/dev/null; then
            _pcfg="$_cand"
            break
        fi
    done

    if [ -n "$_pcfg" ] && [ -r "/dev/fas_rs/mode" ] 2>/dev/null; then
        sh "$_pcfg" "$_mode" 2>/dev/null
        _cpu_owner_log "INFO" "powercfg.sh $_mode applied (via $_pcfg)"
    else
        _cpu_owner_log "WARN" "powercfg.sh tidak ditemukan atau node /dev/fas_rs/mode belum ready, skip"
    fi
}

# Alpha fallback: pakai tune_cpu_freq dari engine.sh dengan persentase profiles.sh
# Aturan M2:
#   - min 50% hardware_max (jamin minimal performa dasar)
#   - Performance profile → paksa 100% (maximum)
#   - baca-ulang verifikasi
#   - node tak-writable → skip + log
_cpu_apply_alpha_freq() {
    # tune_cpu_freq sudah di-engine.sh, panggil langsung.
    # Pastikan profile sudah load supaya CPU_FREQ_MAX_PERCENT benar.
    if [ "${ACTIVE_PROFILE:-}" = "performance" ]; then
        # Performance = maksimum penuh
        CPU_FREQ_MAX_PERCENT=100
    fi
    # Jamin minimum 50% hardware_max
    if [ -n "${CPU_FREQ_MAX_PERCENT:-}" ] && [ "${CPU_FREQ_MAX_PERCENT}" -lt 50 ] 2>/dev/null; then
        _cpu_owner_log "WARN" "CPU_FREQ_MAX_PERCENT=${CPU_FREQ_MAX_PERCENT} < 50%, dikoreksi ke 50% (min M2)"
        CPU_FREQ_MAX_PERCENT=50
    fi
    tune_cpu_freq 2>/dev/null
    _cpu_owner_log "INFO" "tune_cpu_freq fallback applied (percent=${CPU_FREQ_MAX_PERCENT:-100})"
}

# --- Auto-detect saat source langsung (tanpa panggil eksplisit) ---
# Jangan auto-detect bila di-source dari service.sh/apply_now.sh
# (mereka akan panggil cpu_detect_owner sendiri setelah load_profile).
# Auto-detect hanya bila di-source langsung untuk testing.
if [ "${_CPU_OWNER_SOURCED:-0}" != "1" ]; then
    _CPU_OWNER_SOURCED=1
fi
