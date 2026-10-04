#!/system/bin/sh
# Alpha Fusion - Defaults Manager (M3/M4)
# Catat nilai default hardware sekali saat pertama boot (idempotent).
# File: $CONF_DIR/defaults.conf
# Format key=value, mudah di-source.
#
# M3: GPU_MAX_FREQ — acuan 100% GPU ceiling
# M4: VM_SWAPPINESS, VM_VFS_CACHE_PRESSURE, VM_DIRTY_RATIO — bawaan kernel
#
# Alur: bila defaults.conf belum ada → scan + tulis.
#       Bila sudah ada → source dan verifikasi (baca ulang + log bila berubah).

defaults_ensure() {
    local _conf="${ALPHA_CONF_DIR:-/data/adb/alpha}"
    local _defaults="$_conf/defaults.conf"
    local _log="${LOG_FILE:-/data/adb/alpha/alpha.log}"

    _defaults_log() {
        local _ts
        _ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
        printf '%s\n' "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)] [DEFAULTS] [$1] $2" >> "$_log" 2>/dev/null
    }

    if [ -f "$_defaults" ] && [ -s "$_defaults" ]; then
        . "$_defaults" 2>/dev/null
        _defaults_log "INFO" "defaults.conf dimuat (GPU_MAX_FREQ=${GPU_MAX_FREQ:-unset} SWAP=${VM_SWAPPINESS:-unset} DIRTY=${VM_DIRTY_RATIO:-unset} VFS=${VM_VFS_CACHE_PRESSURE:-unset})"
        _defaults_verify
        return 0
    fi

    _defaults_log "INFO" "defaults.conf belum ada, inisialisasi defaults..."
    _defaults_init
}

# --- M3: Simpan GPU max_freq sebagai acuan 100% ---
_defaults_init_gpu() {
    local _gpu_max=""
    # Adreno: kgsl
    if [ -d "${SYSFS_GPU_PREFIX:-/sys}/class/kgsl/kgsl-3d0" ]; then
        local _avail="${SYSFS_GPU_PREFIX:-/sys}/class/kgsl/kgsl-3d0/devfreq/available_frequencies"
        [ ! -f "$_avail" ] && _avail="${SYSFS_GPU_PREFIX:-/sys}/class/kgsl/kgsl-3d0/gpu_available_frequencies"
        if [ -f "$_avail" ]; then
            _gpu_max=$(tr ' ' '\n' < "$_avail" 2>/dev/null | grep -E '^[0-9]+$' | sort -nr | head -n 1)
        fi
        if [ -z "$_gpu_max" ]; then
            local _maxf="${SYSFS_GPU_PREFIX:-/sys}/class/kgsl/kgsl-3d0/max_gpuclk"
            [ -f "$_maxf" ] && _gpu_max=$(cat "$_maxf" 2>/dev/null | tr -d '[:space:]')
        fi
    fi
    # Mali via devfreq
    if [ -z "$_gpu_max" ] && [ -n "${GPU_DEVFREQ_PATH:-}" ] && [ -f "$GPU_DEVFREQ_PATH/max_freq" ]; then
        _gpu_max=$(cat "$GPU_DEVFREQ_PATH/max_freq" 2>/dev/null | tr -d '[:space:]')
    fi
    # Mali fallback: glob
    if [ -z "$_gpu_max" ]; then
        local _cand
        for _cand in "${GPU_SYSFS_PREFIX:-/sys}"/class/misc/mali0/device/devfreq/*.gpu \
                     "${GPU_SYSFS_PREFIX:-/sys}"/class/misc/mali0/device/devfreq/*.mali; do
            if [ -f "$_cand/max_freq" ]; then
                _gpu_max=$(cat "$_cand/max_freq" 2>/dev/null | tr -d '[:space:]')
                [ -n "$_gpu_max" ] && break
            fi
        done
    fi
    # MTK GED/gpufreq: TULIS-BACA-KEMBALIKAN hanya bila node writable
    if [ -z "$_gpu_max" ] && [ "${SOC_VENDOR:-}" = "mtk" ]; then
        _defaults_mtk_gpu_probe
        _gpu_max="${MTK_GPU_MAX_FREQ:-}"
    fi
    case "$_gpu_max" in ''|*[!0-9]*) _gpu_max=0 ;; esac
    GPU_MAX_FREQ="$_gpu_max"
    _defaults_log "INFO" "GPU_MAX_FREQ terdeteksi: $GPU_MAX_FREQ"
}

# M3: MTK — tulis baca-kembalikan untuk validasi node gpu/GED
# Contoh: MT6878/K6.1/KSU (bukan tebakan — hanya bila write-readback OK).
_defaults_mtk_gpu_probe() {
    local _ged="/sys/module/ged/parameters/gpu_cust_boost_freq"
    local _gpufreq="/proc/gpufreq/gpufreq_opp_dump"
    local _val=""
    MTK_GPU_MAX_FREQ=0

    # MTK GED: tulis test bila writable
    if [ -w "$_ged" ] 2>/dev/null; then
        _val=$(cat "$_ged" 2>/dev/null | tr -d '[:space:]')
        case "$_val" in ''|*[!0-9]*) return ;; esac
        # Tulis nilai yang sama (idempotent) lalu baca ulang
        echo "$_val" > "$_ged" 2>/dev/null
        local _readback
        _readback=$(cat "$_ged" 2>/dev/null | tr -d '[:space:]')
        if [ "$_readback" = "$_val" ]; then
            # Write-readback OK → node bisa dipakai
            MTK_GPU_MAX_FREQ="$_val"
            _defaults_log "INFO" "MTK GED gpu_cust_boost_freq tulis-baca OK: $_val"
        else
            _defaults_log "WARN" "MTK GED gpu_cust_boost_freq write-readback mismatch ($_val vs $_readback), skip"
        fi
    fi

    # MTK gpufreq opp_dump: baca-only probe (tidak tulis, hanya verifikasi readable)
    if [ -r "$_gpufreq" ] 2>/dev/null && [ "$MTK_GPU_MAX_FREQ" = "0" ]; then
        local _opp
        _opp=$(cat "$_gpufreq" 2>/dev/null | grep -E '^\s*[0-9]+' | head -n 1 | awk '{print $1}')
        case "$_opp" in ''|*[!0-9]*) return ;; esac
        MTK_GPU_MAX_FREQ="$_opp"
        _defaults_log "INFO" "MTK gpufreq_opp_dump max: $_opp"
    fi
}

# --- M3/M4: Simpan bawaan kernel ---
_defaults_init_vm() {
    local _proc="${PROC_SYS_PREFIX:-/proc/sys}"
    VM_SWAPPINESS=$(cat "$_proc/vm/swappiness" 2>/dev/null | tr -d '[:space:]')
    VM_VFS_CACHE_PRESSURE=$(cat "$_proc/vm/vfs_cache_pressure" 2>/dev/null | tr -d '[:space:]')
    VM_DIRTY_RATIO=$(cat "$_proc/vm/dirty_ratio" 2>/dev/null | tr -d '[:space:]')
    case "${VM_SWAPPINESS:-}" in ''|*[!0-9]*) VM_SWAPPINESS=0 ;; esac
    case "${VM_VFS_CACHE_PRESSURE:-}" in ''|*[!0-9]*) VM_VFS_CACHE_PRESSURE=0 ;; esac
    case "${VM_DIRTY_RATIO:-}" in ''|*[!0-9]*) VM_DIRTY_RATIO=0 ;; esac
    _defaults_log "INFO" "VM bawaan: swappiness=$VM_SWAPPINESS vfs=$VM_VFS_CACHE_PRESSURE dirty=$VM_DIRTY_RATIO"
}

_defaults_init() {
    _defaults_init_gpu
    _defaults_init_vm

    local _conf="${ALPHA_CONF_DIR:-/data/adb/alpha}"
    local _defaults="$_conf/defaults.conf"
    cat <<EOF > "$_defaults"
# Alpha Fusion Hardware Defaults (auto-generated, jangan edit manual)
GPU_MAX_FREQ="${GPU_MAX_FREQ:-0}"
VM_SWAPPINESS="${VM_SWAPPINESS:-0}"
VM_VFS_CACHE_PRESSURE="${VM_VFS_CACHE_PRESSURE:-0}"
VM_DIRTY_RATIO="${VM_DIRTY_RATIO:-0}"
EOF
    chmod 0644 "$_defaults"
    _defaults_log "INFO" "defaults.conf ditulis ke $_defaults"
}

# --- M3/M4: Verifikasi bila sudah ada (baca ulang + log bila berubah) ---
_defaults_verify() {
    local _proc="${PROC_SYS_PREFIX:-/proc/sys}"
    local _changed=0

    # M3: verifikasi GPU_MAX_FREQ — baca ulang dari hardware
    local _gpu_now=""
    if [ -n "${GPU_DEVFREQ_PATH:-}" ] && [ -f "$GPU_DEVFREQ_PATH/max_freq" ]; then
        _gpu_now=$(cat "$GPU_DEVFREQ_PATH/max_freq" 2>/dev/null | tr -d '[:space:]')
    fi
    if [ -n "$_gpu_now" ] && [ -n "${GPU_MAX_FREQ:-}" ] && [ "$_gpu_now" != "$GPU_MAX_FREQ" ] 2>/dev/null; then
        _defaults_log "WARN" "GPU_MAX_FREQ berubah: stored=${GPU_MAX_FREQ} live=${_gpu_now}"
        _changed=1
    fi

    # M4: verifikasi VM
    local _swap_now _vfs_now _dirty_now
    _swap_now=$(cat "$_proc/vm/swappiness" 2>/dev/null | tr -d '[:space:]')
    _vfs_now=$(cat "$_proc/vm/vfs_cache_pressure" 2>/dev/null | tr -d '[:space:]')
    _dirty_now=$(cat "$_proc/vm/dirty_ratio" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$_swap_now" ] && [ "${VM_SWAPPINESS:-}" != "$_swap_now" ] 2>/dev/null; then
        _defaults_log "WARN" "VM_SWAPPINESS berubah: stored=${VM_SWAPPINESS} live=$_swap_now"
        _changed=1
    fi
    if [ -n "$_vfs_now" ] && [ "${VM_VFS_CACHE_PRESSURE:-}" != "$_vfs_now" ] 2>/dev/null; then
        _defaults_log "WARN" "VM_VFS_CACHE_PRESSURE berubah: stored=${VM_VFS_CACHE_PRESSURE} live=$_vfs_now"
        _changed=1
    fi
    if [ -n "$_dirty_now" ] && [ "${VM_DIRTY_RATIO:-}" != "$_dirty_now" ] 2>/dev/null; then
        _defaults_log "WARN" "VM_DIRTY_RATIO berubah: stored=${VM_DIRTY_RATIO} live=$_dirty_now"
        _changed=1
    fi

    [ "$_changed" = "0" ] && _defaults_log "INFO" "defaults.conf verifikasi: semua nilai konsisten"
}
