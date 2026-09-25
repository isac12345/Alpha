#!/system/bin/sh
# Alpha Fusion - Game Boost Engine (Extreme / Performance / Balanced)
# Modul33 stabil-otomatis: extreme = game stabil (lantai big 75%,
# little 35%, uclamp 60), performance = mild (lantai 35%, uclamp 30,
# tangga panas 75C), restore native (pendinginan). Generic semua device + game.
# Prinsip: pacing stabil > burst max (maximal via HSIN saja).
# GPU min TIDAK dikunci (adem + pacing), fas-rs fast di extreme (burst).
# uscfreq-hold OFF (biang kresek modul23). POSIX sh; semua tulis =
# dua kali tulis-baca-verifikasi.
# Sakelar: DISABLE_GAMEBOOST, NO_CPUSET, GAMEBOOST_NO_VM, GAMEBOOST_LEVEL

CONF_DIR="${ALPHA_CONF_DIR:-/data/adb/alpha}"
LOG_FILE="${ALPHA_LOG_FILE:-/data/adb/alpha/alpha.log}"
NATIVE_CONF="$CONF_DIR/native_boost.conf"

SYSFS_CPU_PREFIX="${SYSFS_CPU_PREFIX:-/sys/devices/system/cpu}"
SYSFS_BLOCK_PREFIX="${SYSFS_BLOCK_PREFIX:-/sys/block}"
SYSFS_DEVFREQ_PREFIX="${SYSFS_DEVFREQ_PREFIX:-/sys/class/devfreq}"
GPU_SYSFS_PREFIX="${GPU_SYSFS_PREFIX:-/sys}"
SYSFS_MODULE_PREFIX="${SYSFS_MODULE_PREFIX:-/sys/module}"
PROC_SYS_PREFIX="${PROC_SYS_PREFIX:-/proc/sys}"
DEV_CPUSET_PREFIX="${DEV_CPUSET_PREFIX:-${DEV_CPUSET_PREFIX:-/dev/cpuset}}"
DEV_CPUCTL_PREFIX="${DEV_CPUCTL_PREFIX:-${DEV_CPUCTL_PREFIX:-/dev/cpuctl}}"
DEV_STUNE_PREFIX="${DEV_STUNE_PREFIX:-${DEV_STUNE_PREFIX:-/dev/stune}}"
SYSFS_DEBUG_PREFIX="${SYSFS_DEBUG_PREFIX:-${SYSFS_DEBUG_PREFIX:-/sys/kernel/debug/sched}}"

# Defaults (di-override bila defaults.conf ada)
GPU_MAX_FREQ="${GPU_MAX_FREQ:-0}"
CPU_POLICIES="${CPU_POLICIES:-}"

# ============================================================
# Logging
# ============================================================
_gb_log() {
    local _s="$1" _d="$2"
    local _ts
    _ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    if [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)] [GAMEBOOST] [$_s] $_d" \
            >> "$LOG_FILE" 2>/dev/null
    fi
}

# ============================================================
# Write-Read-Verify (dua putaran)
# ============================================================
# Kernel sering menormalkan tulisan (cpuset "6 7"→"6-7", uclamp
# "60"→"60.00", scheduler "[mq-deadline] ...", uclamp.max "100"→"max").
# Samakan arti sebelum vonis gagal.
_gb_equiv() {
    local _want="$1" _got="$2"
    [ "$_got" = "$_want" ] && return 0
    # uclamp.max: 100 ≡ max (tanpa cap)
    if [ "$_want" = "100" ] && [ "$_got" = "max" ]; then
        return 0
    fi
    # scheduler: "[mq-deadline] kyber ..." ≡ mq-deadline bila dibracket
    case "$_got" in
        *"[$_want]"*) return 0 ;;
    esac
    # angka desimal kernel: "60.00"/"60.0" ≡ "60"
    local _gwant="$_want" _ggot="$_got"
    case "$_ggot" in
        *.00) _ggot="${_ggot%.00}" ;;
        *.0) _ggot="${_ggot%.0}" ;;
    esac
    [ "$_ggot" = "$_gwant" ] && return 0
    # list cpu: "6 7" ≡ "6-7" ≡ "6,7" (bandingkan sebagai himpunan)
    if _gb_cpuset_eq "$_want" "$_got"; then
        return 0
    fi
    return 1
}

# Normalkan daftar cpu ("0-2,4-7", "0 1 2", "0-5") jadi "0,1,2,4,5,6,7,"
_gb_cpuset_norm() {
    local _in="$1" _tok _a _b _n _out=""
    _in=$(printf '%s' "$_in" | tr ',' ' ')
    for _tok in $_in; do
        case "$_tok" in
            *-*)
                _a="${_tok%%-*}"
                _b="${_tok##*-}"
                case "$_a$_b" in ''|*[!0-9]*) continue ;; esac
                _n="$_a"
                while [ "$_n" -le "$_b" ] 2>/dev/null; do
                    _out="$_out$_n,"
                    _n=$((_n + 1))
                done
                ;;
            *)
                case "$_tok" in ''|*[!0-9]*) continue ;; esac
                _out="$_out$_tok,"
                ;;
        esac
    done
    printf '%s' "$_out" | tr ',' '\n' | grep -E '^[0-9]+$' | sort -n | tr '\n' ','
}

_gb_cpuset_eq() {
    local _nw _ng
    _nw=$(_gb_cpuset_norm "$1")
    _ng=$(_gb_cpuset_norm "$2")
    [ -n "$_nw" ] && [ "$_nw" = "$_ng" ]
}

_gb_write() {
    local _node="$1" _val="$2" _cat="$3"
    [ -e "$_node" ] || { _gb_log "SKIPPED" "$_cat node=$_node (not found)"; return 0; }
    if [ ! -w "$_node" ]; then
        chmod 0644 "$_node" 2>/dev/null
    fi
    [ -w "$_node" ] || { _gb_log "FAILED" "$_cat node=$_node (not writable)"; return 1; }
    local _pass=1 _rb=""
    while [ "$_pass" -le 2 ]; do
        printf '%s' "$_val" > "$_node" 2>/dev/null
        _rb=$(cat "$_node" 2>/dev/null | tr -d '[:space:]')
        if [ "$_rb" = "$_val" ]; then
            _gb_log "APPLIED" "$_cat node=$_node value=$_val"
            return 0
        fi
        if _gb_equiv "$_val" "$_rb"; then
            _gb_log "APPLIED" "$_cat node=$_node value=$_val (kernel: $_rb)"
            return 0
        fi
        _pass=$((_pass + 1))
    done
    _gb_log "FAILED" "$_cat node=$_node value=$_val readback=$_rb"
    return 1
}

# ============================================================
# Level Detection
# _gb_level membaca GAMEBOOST_LEVEL: "extreme" (game), "performance"
# (mild/tangga panas), "balanced" (restore). Default fail-safe =
# "balanced" supaya thermal safety tak pernah jatuh ke mode kencang.
# ============================================================
_gb_level() {
    if [ -f "$CONF_DIR/GAMEBOOST_LEVEL" ]; then
        local _lv
        _lv=$(cat "$CONF_DIR/GAMEBOOST_LEVEL" 2>/dev/null \
              | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        case "$_lv" in
            extreme)     echo "extreme";     return 0 ;;
            performance) echo "performance"; return 0 ;;
            balanced)    echo "balanced";    return 0 ;;
        esac
    fi
    echo "balanced"
}

# ============================================================
# OPP Cap Picker (dari engine.sh)
# ============================================================
_alpha_opp_cap_pick() {
    local target="$1"
    local avail="$2"
    case "$target" in
        ''|*[!0-9]*) return 1 ;;
    esac
    local best="" lowest=""
    for f in $avail; do
        case "$f" in ''|*[!0-9]*) continue ;; esac
        if [ -z "$lowest" ] || [ "$f" -lt "$lowest" ]; then
            lowest="$f"
        fi
        if [ "$f" -le "$target" ]; then
            if [ -z "$best" ] || [ "$f" -gt "$best" ]; then
                best="$f"
            fi
        fi
    done
    if [ -n "$best" ]; then
        printf '%s\n' "$best"
    else
        printf '%s\n' "$lowest"
    fi
}

# ============================================================
# Cluster Topology (hsin_cpu_topo_detect)
# ============================================================
_gb_topo_detect() {
    GB_CPU_BIG="" GB_CPU_LITTLE="" GB_CPU_TOPO_UNKNOWN=0
    local _max_all=0 _p _mx _cpus _levels="" _level_count=0
    for _p in "$SYSFS_CPU_PREFIX"/cpufreq/policy*; do
        [ -d "$_p" ] || continue
        _mx=$(cat "$_p/cpuinfo_max_freq" 2>/dev/null | tr -d '[:space:]')
        case "$_mx" in ''|*[!0-9]*) continue ;; esac
        case " $_levels " in
            *" $_mx "*) ;;
            *)
                _levels="$_levels $_mx"
                _level_count=$((_level_count + 1))
                ;;
        esac
        [ "$_mx" -gt "$_max_all" ] 2>/dev/null && _max_all="$_mx"
    done
    [ "$_max_all" -eq 0 ] 2>/dev/null && return 1
    if [ "$_level_count" -gt 2 ]; then
        GB_CPU_TOPO_UNKNOWN=1
        return 1
    fi
    for _p in "$SYSFS_CPU_PREFIX"/cpufreq/policy*; do
        [ -d "$_p" ] || continue
        _mx=$(cat "$_p/cpuinfo_max_freq" 2>/dev/null | tr -d '[:space:]')
        case "$_mx" in ''|*[!0-9]*) continue ;; esac
        _cpus=""
        if [ -f "$_p/related_cpus" ]; then
            _cpus=$(cat "$_p/related_cpus" 2>/dev/null | tr '\n' ' ')
        elif [ -f "$_p/affinity_cpus" ]; then
            _cpus=$(cat "$_p/affinity_cpus" 2>/dev/null | tr '\n' ' ')
        fi
        [ -z "$_cpus" ] && continue
        if [ "$_mx" -ge "$_max_all" ] 2>/dev/null; then
            GB_CPU_BIG="${GB_CPU_BIG} $_cpus"
        else
            GB_CPU_LITTLE="${GB_CPU_LITTLE} $_cpus"
        fi
    done
    GB_CPU_BIG=$(echo "$GB_CPU_BIG" | sed 's/^ *//;s/  */ /g;s/ *$//')
    GB_CPU_LITTLE=$(echo "$GB_CPU_LITTLE" | sed 's/^ *//;s/  */ /g;s/ *$//')
    [ -n "$GB_CPU_BIG" ] && [ -n "$GB_CPU_LITTLE" ] || { GB_CPU_BIG="" GB_CPU_LITTLE=""; return 1; }
    return 0
}

# ============================================================
# Scheduler Latency (backup/restore bila node resolve)
# ============================================================
_GB_SCHED_NODES="sched_latency_ns sched_min_granularity_ns sched_wakeup_granularity_ns sched_migration_cost_ns"
_GB_SCHED_FLOOR=500000

_gb_sched_resolve() {
    local _canon="$1"
    if [ -w "$PROC_SYS_PREFIX/kernel/$_canon" ]; then
        echo "$PROC_SYS_PREFIX/kernel/$_canon"; return 0
    fi
    local _short="${_canon#sched_}"
    if [ -d "${SYSFS_DEBUG_PREFIX:-/sys/kernel/debug/sched}" ] && [ -w "${SYSFS_DEBUG_PREFIX:-/sys/kernel/debug/sched}/$_short" ]; then
        echo "${SYSFS_DEBUG_PREFIX:-/sys/kernel/debug/sched}/$_short"; return 0
    fi
    return 1
}

_gb_sched_native() {
    local _canon="$1"
    [ -f "$NATIVE_CONF" ] || return 1
    grep "^${_canon}=" "$NATIVE_CONF" 2>/dev/null | head -1 | cut -d= -f2
}

# Apply sched latency: 4 parameter persentase (lat, min_gran, wake_gran, migr)
# Dua putaran write + verifikasi akhir (pola HSIN)
_gb_sched_apply_level() {
    local _pct_lat="$1" _pct_min="$2" _pct_wake="$3" _pct_migr="$4"
    local _pass=1 _canon _p _native _target _rb _pct
    while [ "$_pass" -le 2 ]; do
        for _canon in $_GB_SCHED_NODES; do
            _p=$(_gb_sched_resolve "$_canon") || continue
            _native=$(_gb_sched_native "$_canon") || continue
            case "$_canon" in
                sched_latency_ns)           _pct="$_pct_lat" ;;
                sched_min_granularity_ns)   _pct="$_pct_min" ;;
                sched_wakeup_granularity_ns) _pct="$_pct_wake" ;;
                sched_migration_cost_ns)    _pct="$_pct_migr" ;;
                *) continue ;;
            esac
            _target=$((_native / 100 * _pct))
            [ "$_target" -ge "$_GB_SCHED_FLOOR" ] || _target="$_GB_SCHED_FLOOR"
            printf '%s' "$_target" > "$_p" 2>/dev/null
            _rb=$(cat "$_p" 2>/dev/null | tr -d '[:space:]')
            if [ "$_rb" != "$_target" ]; then
                printf '%s' "$_target" > "$_p" 2>/dev/null
            fi
        done
        _pass=$((_pass + 1))
    done
    # Verifikasi akhir
    for _canon in $_GB_SCHED_NODES; do
        _p=$(_gb_sched_resolve "$_canon") || continue
        _native=$(_gb_sched_native "$_canon") || continue
        case "$_canon" in
            sched_latency_ns)           _pct="$_pct_lat" ;;
            sched_min_granularity_ns)   _pct="$_pct_min" ;;
            sched_wakeup_granularity_ns) _pct="$_pct_wake" ;;
            sched_migration_cost_ns)    _pct="$_pct_migr" ;;
            *) continue ;;
        esac
        _target=$((_native / 100 * _pct))
        [ "$_target" -ge "$_GB_SCHED_FLOOR" ] || _target="$_GB_SCHED_FLOOR"
        _rb=$(cat "$_p" 2>/dev/null | tr -d '[:space:]')
        [ "$_rb" != "$_target" ] && \
            _gb_log "WARN" "SCHED drift: $_canon wanted=$_target got=$_rb"
    done
}

# ============================================================
# Backup Originals (sekali, ke native_boost.conf)
# NATIVE_VERSION bump = paksa refresh snapshot basi (modul23 uscfreq
# 5000/3000 + modul26 floor75 yang nyangkut di /data/adb/alpha dan
# ikut kebawa saat flash rilis/garapan). Tanpa ini restore memulihkan
# nilai boost lama, bukan native asli = kresek + ga stabil.
# ============================================================
_gb_backup_native() {
    if [ -z "$CPU_POLICIES" ]; then
        _gb_log "WARN" "CPU_POLICIES unbound/empty; detect.sh harus di-source dulu; backup CPU dilewati"
        return 0
    fi
    if [ -f "$NATIVE_CONF" ]; then
        _nv=$(grep "^NATIVE_VERSION=" "$NATIVE_CONF" 2>/dev/null | head -n 1 | cut -d= -f2)
        [ "$_nv" = "30" ] && return 0
        rm -f "$NATIVE_CONF" 2>/dev/null
    fi
    mkdir -p "$CONF_DIR" 2>/dev/null
    : > "$NATIVE_CONF.tmp" 2>/dev/null || return 1
    local _pol _gov _mn _mx _avail _mx_val _v
    for _pol in $CPU_POLICIES; do
        [ -d "$SYSFS_CPU_PREFIX/cpufreq/$_pol" ] || continue
        [ -f "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_governor" ] && {
            _gov=$(cat "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_governor" 2>/dev/null | tr -d '[:space:]')
            [ -n "$_gov" ] && echo "${_pol}_scaling_governor=$_gov" >> "$NATIVE_CONF.tmp"
        }
        [ -f "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_min_freq" ] && {
            _mn=$(cat "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_min_freq" 2>/dev/null | tr -d '[:space:]')
            [ -n "$_mn" ] && echo "${_pol}_scaling_min_freq=$_mn" >> "$NATIVE_CONF.tmp"
        }
        [ -f "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_max_freq" ] && {
            _mx=$(cat "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_max_freq" 2>/dev/null | tr -d '[:space:]')
            [ -n "$_mx" ] && echo "${_pol}_scaling_max_freq=$_mx" >> "$NATIVE_CONF.tmp"
        }
        # uscfreq down_rate_limit_us asli (Unisoc; absen di governor lain → skip)
        if [ -f "$SYSFS_CPU_PREFIX/cpufreq/$_pol/uscfreq/down_rate_limit_us" ]; then
            _v=$(cat "$SYSFS_CPU_PREFIX/cpufreq/$_pol/uscfreq/down_rate_limit_us" 2>/dev/null | tr -d '[:space:]')
            case "$_v" in ''|*[!0-9]*) ;; *) echo "${_pol}_uscfreq_down_rate=$_v" >> "$NATIVE_CONF.tmp" ;; esac
        fi
        # OPP table
        _avail=""
        if [ -f "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_available_frequencies" ]; then
            _avail=$(cat "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_available_frequencies" 2>/dev/null \
                     | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n | tr '\n' ',')
        fi
        [ -n "$_avail" ] && echo "${_pol}_available_frequencies=$_avail" >> "$NATIVE_CONF.tmp"
        _mx_val=""
        if [ -n "$_avail" ]; then
            _mx_val=$(echo "$_avail" | tr ',' '\n' | grep -E '^[0-9]+$' | sort -n | tail -1)
        fi
        if [ -z "$_mx_val" ] && [ -f "$SYSFS_CPU_PREFIX/cpufreq/$_pol/cpuinfo_max_freq" ]; then
            _mx_val=$(cat "$SYSFS_CPU_PREFIX/cpufreq/$_pol/cpuinfo_max_freq" 2>/dev/null | tr -d '[:space:]')
        fi
        [ -n "$_mx_val" ] && echo "${_pol}_hardware_max=$_mx_val" >> "$NATIVE_CONF.tmp"
    done
    # GPU devfreq
    local _df _gname
    for _df in "$SYSFS_DEVFREQ_PREFIX"/*; do
        [ -d "$_df" ] || continue
        _gname=$(basename "$_df")
        case "$_gname" in *gpu*|*mali*|*kgsl*|*adreno*) ;; *) continue ;; esac
        [ -f "$_df/governor" ] && {
            _gov=$(cat "$_df/governor" 2>/dev/null | tr -d '[:space:]')
            [ -n "$_gov" ] && echo "gpu_${_gname}_governor=$_gov" >> "$NATIVE_CONF.tmp"
        }
        [ -f "$_df/max_freq" ] && {
            _mx=$(cat "$_df/max_freq" 2>/dev/null | tr -d '[:space:]')
            [ -n "$_mx" ] && echo "gpu_${_gname}_max_freq=$_mx" >> "$NATIVE_CONF.tmp"
        }
        [ -f "$_df/min_freq" ] && {
            _mn=$(cat "$_df/min_freq" 2>/dev/null | tr -d '[:space:]')
            [ -n "$_mn" ] && echo "gpu_${_gname}_min_freq=$_mn" >> "$NATIVE_CONF.tmp"
        }
    done
    # GPU_MAX_FREQ dari defaults.conf
    if [ -f "$CONF_DIR/defaults.conf" ]; then
        . "$CONF_DIR/defaults.conf" 2>/dev/null
        [ -n "${GPU_MAX_FREQ:-}" ] && echo "defaults_GPU_MAX_FREQ=$GPU_MAX_FREQ" >> "$NATIVE_CONF.tmp"
    fi
    # Sched latency (hanya bila node resolve)
    local _canon _p
    for _canon in $_GB_SCHED_NODES; do
        _p=$(_gb_sched_resolve "$_canon") || continue
        _v=$(cat "$_p" 2>/dev/null | tr -d '[:space:]')
        case "$_v" in ''|*[!0-9]*) continue ;; esac
        echo "$_canon=$_v" >> "$NATIVE_CONF.tmp"
    done
    # sched_child_runs_first
    if [ -f "$PROC_SYS_PREFIX/kernel/sched_child_runs_first" ]; then
        _v=$(cat "$PROC_SYS_PREFIX/kernel/sched_child_runs_first" 2>/dev/null | tr -d '[:space:]')
        [ -n "$_v" ] && echo "sched_child_runs_first=$_v" >> "$NATIVE_CONF.tmp"
    fi
    # CPuset asli
    local _grp
    for _grp in top-app foreground background system-background; do
        if [ -f "${DEV_CPUSET_PREFIX:-/dev/cpuset}/$_grp/cpus" ]; then
            _v=$(cat "${DEV_CPUSET_PREFIX:-/dev/cpuset}/$_grp/cpus" 2>/dev/null | tr -d '[:space:]')
            [ -n "$_v" ] && echo "cpuset_${_grp}=$_v" >> "$NATIVE_CONF.tmp"
        fi
    done
    # uclamp asli
    if [ -f "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.min" ]; then
        _v=$(cat "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.min" 2>/dev/null | tr -d '[:space:]')
        [ -n "$_v" ] && echo "uclamp_min=$_v" >> "$NATIVE_CONF.tmp"
    fi
    if [ -f "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.max" ]; then
        _v=$(cat "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.max" 2>/dev/null | tr -d '[:space:]')
        [ -n "$_v" ] && echo "uclamp_max=$_v" >> "$NATIVE_CONF.tmp"
    fi
    # stune asli
    if [ -f "${DEV_STUNE_PREFIX:-/dev/stune}/top-app/schedtune.boost" ]; then
        _v=$(cat "${DEV_STUNE_PREFIX:-/dev/stune}/top-app/schedtune.boost" 2>/dev/null | tr -d '[:space:]')
        [ -n "$_v" ] && echo "stune_boost=$_v" >> "$NATIVE_CONF.tmp"
    fi
    # VM asli (backup swappiness, vfs, dirty_ratio, dirty_background_ratio, page-cluster)
    local _proc="$PROC_SYS_PREFIX"
    for _vmkey in vm/swappiness vm/vfs_cache_pressure vm/dirty_ratio vm/dirty_background_ratio vm/page-cluster; do
        [ -f "$_proc/$_vmkey" ] || continue
        _v=$(cat "$_proc/$_vmkey" 2>/dev/null | tr -d '[:space:]')
        case "$_v" in ''|*[!0-9]*) continue ;; esac
        echo "$_vmkey=$_v" >> "$NATIVE_CONF.tmp"
    done
    # Network asli (backup congestion_control, fastopen, backlog, ecn)
    local _netbase="$PROC_SYS_PREFIX/net/ipv4"
    for _nk in tcp_congestion_control tcp_fastopen tcp_ecn; do
        [ -f "$_netbase/$_nk" ] || continue
        _v=$(cat "$_netbase/$_nk" 2>/dev/null | tr -d '[:space:]')
        [ -n "$_v" ] && echo "$_nk=$_v" >> "$NATIVE_CONF.tmp"
    done
    [ -f "$PROC_SYS_PREFIX/net/core/netdev_max_backlog" ] && {
        _v=$(cat "$PROC_SYS_PREFIX/net/core/netdev_max_backlog" 2>/dev/null | tr -d '[:space:]')
        [ -n "$_v" ] && echo "netdev_max_backlog=$_v" >> "$NATIVE_CONF.tmp"
    }
    # kbase asli (Mali)
    local _kbp="${SYSFS_MODULE_PREFIX:-/sys/module}/mali_kbase/parameters"
    if [ -d "$_kbp" ]; then
        for _kb in gpu_boost_level2 gpu_pollingtime gpu_upthreshold; do
            [ -f "$_kbp/$_kb" ] || continue
            _v=$(cat "$_kbp/$_kb" 2>/dev/null | tr -d '[:space:]')
            [ -n "$_v" ] && echo "kbase_$_kb=$_v" >> "$NATIVE_CONF.tmp"
        done
    fi
    # IO asli (scheduler + read_ahead per device utama)
    local _bdev _bname _sq
    for _bdev in "$SYSFS_BLOCK_PREFIX"/sd* "$SYSFS_BLOCK_PREFIX"/mmcblk*; do
        [ -d "$_bdev/queue" ] || continue
        _bname=$(basename "$_bdev")
        case "$_bname" in
            *p[0-9]*|*[0-9]rpmb|*[0-9]boot*) continue ;;
        esac
        [ -f "$_bdev/queue/read_ahead_kb" ] && {
            _v=$(cat "$_bdev/queue/read_ahead_kb" 2>/dev/null | tr -d '[:space:]')
            [ -n "$_v" ] && echo "io_${_bname}_read_ahead_kb=$_v" >> "$NATIVE_CONF.tmp"
        }
        [ -f "$_bdev/queue/scheduler" ] && {
            _sq=$(cat "$_bdev/queue/scheduler" 2>/dev/null \
                | tr ' ' '\n' | grep -E '^\[.*\]$' | tr -d '[]')
            [ -n "$_sq" ] && echo "io_${_bname}_scheduler=$_sq" >> "$NATIVE_CONF.tmp"
        }
    done
    echo "NATIVE_VERSION=30" >> "$NATIVE_CONF.tmp"
    mv "$NATIVE_CONF.tmp" "$NATIVE_CONF" 2>/dev/null
    chmod 0644 "$NATIVE_CONF" 2>/dev/null
    [ -f "$NATIVE_CONF" ] || { _gb_log "FAILED" "backup write failed"; return 1; }
    return 0
}

_gb_read_native() {
    local _key="$1" _def="$2"
    [ -f "$NATIVE_CONF" ] || { echo "$_def"; return 0; }
    local _v
    _v=$(grep "^${_key}=" "$NATIVE_CONF" 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$_v" ] && echo "$_v" || echo "$_def"
}

# ============================================================
# CPU Apply — Lantai asimetris + uclamp + cpuset (TANPA governor)
# CPU_OWNER dicatat di log, lantai TETAP JALAN walau fas-rs aktif.
# Modul33 stabil: cluster big 60% (turun dari 75% modul32: p6 -1 rung,
# adem + pacing; PGR/WuWa pacing-cepat butuh sustained bukan burst),
# cluster little 35% (game dipin ke big via cpuset; little tinggi =
# setrika → throttle/flapping 75C = stutter).
# ============================================================
_gb_apply_cpu() {
    if [ -z "$CPU_POLICIES" ]; then
        _gb_log "WARN" "CPU_POLICIES unbound/empty; detect.sh harus di-source dulu; apply CPU dilewati"
        return 0
    fi
    local _level="$1"
    local _pol _pol_dir _avail_list _opp_list _hw_max _floor _target_min
    local _max_all=0 _mx _topo_unknown=0

    # Cluster tercepat = big (metode sama kayak _gb_topo_detect).
    # >2 level = topologi unknown: cpuset dilewati dan lantai tetap 60%.
    _gb_topo_detect
    _topo_unknown="$GB_CPU_TOPO_UNKNOWN"
    for _pol in $CPU_POLICIES; do
        _mx=$(cat "$SYSFS_CPU_PREFIX/cpufreq/$_pol/cpuinfo_max_freq" 2>/dev/null | tr -d '[:space:]')
        case "$_mx" in ''|*[!0-9]*) continue ;; esac
        [ "$_mx" -gt "$_max_all" ] 2>/dev/null && _max_all="$_mx"
    done

    # --- Frequency Floor (extreme: big 75% / little 35%; performance 35%) ---
    for _pol in $CPU_POLICIES; do
        _pol_dir="$SYSFS_CPU_PREFIX/cpufreq/$_pol"
        [ -d "$_pol_dir" ] || continue

        _avail_list=""
        _opp_list=""
        _hw_max=""
        if [ -f "$_pol_dir/scaling_available_frequencies" ]; then
            _opp_list=$(cat "$_pol_dir/scaling_available_frequencies" 2>/dev/null \
                        | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n)
            _hw_max=$(echo "$_opp_list" | tail -n 1)
        fi
        if [ -z "$_hw_max" ] && [ -f "$_pol_dir/cpuinfo_max_freq" ]; then
            _hw_max=$(cat "$_pol_dir/cpuinfo_max_freq" 2>/dev/null | tr -d '[:space:]')
        fi
        [ -z "$_hw_max" ] && continue

        # Tiap HP ikut OPP sendiri (contoh T615: 60% dulu = 1040000,
        # kini 75% = satu rung di atasnya; little tetap 35%);
        # performance 35% semua; tanpa uscfreq-hold)
        _floor=$((_hw_max * 75 / 100))
        if [ "$_level" = "performance" ]; then
            _floor=$((_hw_max * 35 / 100))
        fi
        # Extreme + topologi dikenal + cluster kecil: turun ke 35%
        # (game dipin ke big; little dikunci tinggi = setrika).
        if [ "$_level" = "extreme" ] && [ "$_topo_unknown" -eq 0 ] 2>/dev/null \
                && [ "$_max_all" -gt 0 ] 2>/dev/null \
                && [ "$_hw_max" -lt "$_max_all" ] 2>/dev/null; then
            _floor=$((_hw_max * 35 / 100))
        fi

        if [ -n "$_opp_list" ]; then
            _target_min=$(_alpha_opp_cap_pick "$_floor" "$_opp_list")
        else
            _target_min="$_floor"
        fi
        [ -n "$_target_min" ] && _gb_write "$_pol_dir/scaling_min_freq" "$_target_min" "CPU_FREQ"
    done

    # --- Cpuset (skip bila sakelar NO_CPUSET) ---
    if [ ! -f "$CONF_DIR/NO_CPUSET" ]; then
        if [ -d "${DEV_CPUSET_PREFIX:-/dev/cpuset}" ]; then
            if [ -n "$GB_CPU_BIG" ]; then
                local _grp _top_app_cpus
                _top_app_cpus=$(_gb_cpuset_norm "$GB_CPU_LITTLE")
                case "$_top_app_cpus" in
                    *,*,*) _top_app_cpus="$GB_CPU_BIG $(printf '%s' "$_top_app_cpus" | cut -d, -f1,2)" ;;
                    *)      _top_app_cpus="$GB_CPU_BIG" ;;
                esac
                _top_app_cpus=$(_gb_cpuset_norm "$_top_app_cpus")
                _top_app_cpus="${_top_app_cpus%,}"
                [ -w "${DEV_CPUSET_PREFIX:-/dev/cpuset}/top-app/cpus" ] && \
                    _gb_write "${DEV_CPUSET_PREFIX:-/dev/cpuset}/top-app/cpus" "$_top_app_cpus" "CPUSET"
                [ -w "${DEV_CPUSET_PREFIX:-/dev/cpuset}/foreground/cpus" ] && \
                    _gb_write "${DEV_CPUSET_PREFIX:-/dev/cpuset}/foreground/cpus" "$GB_CPU_BIG" "CPUSET"
                if [ -n "$GB_CPU_LITTLE" ]; then
                    for _grp in background system-background; do
                        [ -w "${DEV_CPUSET_PREFIX:-/dev/cpuset}/$_grp/cpus" ] && \
                            _gb_write "${DEV_CPUSET_PREFIX:-/dev/cpuset}/$_grp/cpus" "$GB_CPU_LITTLE" "CPUSET"
                    done
                fi
            fi
        fi
    else
        _gb_log "SKIPPED" "NO_CPUSET exists, skip cpuset"
    fi

    # --- uclamp (extreme 60, performance 30) ---
    if [ -d "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}" ]; then
        case "$_level" in
            extreme)     _gb_write "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.min" "60" "UCLAMP"
                         _gb_write "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.max" "100" "UCLAMP" ;;
            performance) _gb_write "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.min" "30" "UCLAMP"
                         _gb_write "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.max" "100" "UCLAMP" ;;
        esac
    fi

    # --- stune (rasa v20: extreme 100, performance 40) ---
    if [ -d "${DEV_STUNE_PREFIX:-/dev/stune}" ]; then
        case "$_level" in
            extreme)     _gb_write "${DEV_STUNE_PREFIX:-/dev/stune}/top-app/schedtune.boost" "100" "STUNE" ;;
            performance) _gb_write "${DEV_STUNE_PREFIX:-/dev/stune}/top-app/schedtune.boost" "40" "STUNE" ;;
        esac
    fi

    # --- sched_child_runs_first ---
    _gb_write "$PROC_SYS_PREFIX/kernel/sched_child_runs_first" "1" "SCHED"

    # --- Scheduler latency (extreme 40/40/30/1000, performance 60/60/50/600) ---
    case "$_level" in
        extreme)     _gb_sched_apply_level 40 40 30 1000 ;;
        performance) _gb_sched_apply_level 60 60 50 600 ;;
    esac
    # NOTE 2026-09-24 modul25: uscfreq down_rate hold (5000/3000) TETAP
    # DIMATIKAN (biang kresek/patah konfirmasi user: sebelum-uscfreq enak,
    # sesudah-uscfreq ga enak banget). Tuning floor/uclamp modul22 yang
    # enak dikembalikan TANPA hold. Blok backup/restore di bawah
    # dipertahankan agar HP modul23 pulih ke native (1000µs) saat restore.
}

# ============================================================
# GPU Apply (SEMUA CPU_OWNER)
# ============================================================
_gb_apply_gpu() {
    local _level="$1"
    local _df _gname _avail_list _hw_max _target _opp_list

    for _df in "$SYSFS_DEVFREQ_PREFIX"/*; do
        [ -d "$_df" ] || continue
        _gname=$(basename "$_df")
        # Scan node gpu/mali/kgsl/adreno
        case "$_gname" in
            *gpu*|*mali*|*kgsl*|*adreno*) ;;
            *) continue ;;
        esac

        # Governor -> performance (cadangan lain)
        if [ -f "$_df/available_governors" ]; then
            local _govs
            _govs=$(cat "$_df/available_governors" 2>/dev/null | tr '\n' ' ')
            local _want="performance"
            local _found=""
            # Cek performance dulu; bila tak ada, fallback: schedutil > sugov_ext > simple_ondemand > ondemand
            case " $_govs " in
                *" $_want "*) _found="$_want" ;;
                *)
                    for _fb in schedutil sugov_ext simple_ondemand ondemand; do
                        case " $_govs " in
                            *" $_fb "*) _found="$_fb"; break ;;
                        esac
                    done
                    ;;
            esac
            [ -n "$_found" ] && _gb_write "$_df/governor" "$_found" "GPU_GOV"
        fi

        # Max freq = GPU_MAX_FREQ bawaan (cap ke OPP tabel)
        _opp_list=""
        _hw_max=""
        if [ -f "$_df/available_frequencies" ]; then
            _opp_list=$(cat "$_df/available_frequencies" 2>/dev/null \
                        | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n)
            _hw_max=$(echo "$_opp_list" | tail -n 1)
        fi
        if [ -z "$_hw_max" ] && [ -f "$_df/max_freq" ]; then
            _hw_max=$(cat "$_df/max_freq" 2>/dev/null | tr -d '[:space:]')
        fi
        case "$_hw_max" in
            ''|*[!0-9]*) continue ;;
        esac

        local _cap="${GPU_MAX_FREQ:-0}"
        case "$_cap" in ''|*[!0-9]*) _cap=0 ;; esac
        if [ "$_cap" -gt 0 ] 2>/dev/null && [ "$_cap" -le "$_hw_max" ] 2>/dev/null; then
            _target="$_cap"
        else
            _target="$_hw_max"
        fi

        # Cap ke OPP
        if [ -n "$_opp_list" ]; then
            local _best=""
            for _f in $_opp_list; do
                case "$_f" in ''|*[!0-9]*) continue ;; esac
                if [ "$_f" -le "$_target" ]; then
                    [ -z "$_best" ] || [ "$_f" -gt "$_best" ] && _best="$_f"
                fi
            done
            [ -n "$_best" ] && _target="$_best"
        fi

        _gb_write "$_df/max_freq" "$_target" "GPU"
        # Modul33 stabil: min TIDAK dikunci (biarkan governor turun saat
        # idle → adem + pacing; kunci min=max = setrika + throttle).
    done

    # --- Mali ext nodes ---
    local _mali=""
    if [ -n "${GPU_DEVFREQ_PATH:-}" ] && [ -d "$GPU_DEVFREQ_PATH" ]; then
        _mali="$GPU_DEVFREQ_PATH"
    fi
    if [ -z "$_mali" ]; then
        local _cand
        for _cand in "$GPU_SYSFS_PREFIX"/class/misc/mali0/device/devfreq/*.gpu \
                     "$GPU_SYSFS_PREFIX"/class/misc/mali0/device/devfreq/*.mali; do
            if [ -d "$_cand" ]; then _mali="$_cand"; break; fi
        done
    fi
    if [ -z "$_mali" ]; then
        for _cand in "$GPU_SYSFS_PREFIX"/class/devfreq/*mali*; do
            if [ -d "$_cand" ]; then _mali="$_cand"; break; fi
        done
    fi
    if [ -n "$_mali" ] && [ -d "$_mali" ]; then
        # power_policy=always_on
        if [ -w "$_mali/power_policy" ]; then
            _gb_write "$_mali/power_policy" "always_on" "GPU_MALI"
        fi
        # dvfs_governor=2
        if [ -w "$_mali/dvfs_governor" ]; then
            _gb_write "$_mali/dvfs_governor" "2" "GPU_MALI"
        fi
        # js_scheduling_period=1
        if [ -w "$_mali/js_scheduling_period" ]; then
            _gb_write "$_mali/js_scheduling_period" "1" "GPU_MALI"
        fi
    fi

    # --- kbase ---
    local _kbase="$SYSFS_MODULE_PREFIX/mali_kbase/parameters"
    if [ -d "$_kbase" ]; then
        [ -w "$_kbase/gpu_boost_level2" ] && \
            _gb_write "$_kbase/gpu_boost_level2" "1" "GPU_KBASE"
        [ -w "$_kbase/gpu_pollingtime" ] && \
            _gb_write "$_kbase/gpu_pollingtime" "1" "GPU_KBASE"
        [ -w "$_kbase/gpu_upthreshold" ] && \
            _gb_write "$_kbase/gpu_upthreshold" "30" "GPU_KBASE"
    fi

    # --- MTK ged_dvfs_boost ---
    if [ "${SOC_VENDOR:-}" = "mtk" ]; then
        local _ged="${SYSFS_MODULE_PREFIX:-/sys/module}/ged/parameters/ged_dvfs_boost"
        if [ -w "$_ged" ]; then
            local _old_val
            _old_val=$(cat "$_ged" 2>/dev/null | tr -d '[:space:]')
            _gb_write "$_ged" "1" "GPU_MTK_GED"
            local _rb
            _rb=$(cat "$_ged" 2>/dev/null | tr -d '[:space:]')
            if [ "$_rb" = "1" ]; then
                # Tulis balik nilai lama
                [ -n "$_old_val" ] && printf '%s' "$_old_val" > "$_ged" 2>/dev/null
                _rb=$(cat "$_ged" 2>/dev/null | tr -d '[:space:]')
                [ "$_rb" != "$_old_val" ] && \
                    _gb_log "WARN" "MTK GED restore: wanted=$_old_val got=$_rb"
            fi
        fi
    fi
}

# ============================================================
# VM Apply — Nilai HSIN aktual (bukan dead config)
# ============================================================
_gb_apply_vm() {
    local _level="$1"
    local _proc="$PROC_SYS_PREFIX"
    case "$_level" in
        extreme)
            # Modul33 stabil: swappiness=40, vfs=100 (cache awet, kurang IO-stutter), dirty=10, dirty_bg=1, page-cluster=0
            _gb_write "$_proc/vm/swappiness" "40" "VM"
            _gb_write "$_proc/vm/vfs_cache_pressure" "100" "VM"
            _gb_write "$_proc/vm/dirty_ratio" "10" "VM"
            _gb_write "$_proc/vm/dirty_background_ratio" "1" "VM"
            _gb_write "$_proc/vm/page-cluster" "0" "VM"
            ;;
        performance)
            # Performance mild rasa v20: swappiness=60, vfs=50, dirty=15, dirty_bg=5, page-cluster=0
            _gb_write "$_proc/vm/swappiness" "60" "VM"
            _gb_write "$_proc/vm/vfs_cache_pressure" "50" "VM"
            _gb_write "$_proc/vm/dirty_ratio" "15" "VM"
            _gb_write "$_proc/vm/dirty_background_ratio" "5" "VM"
            _gb_write "$_proc/vm/page-cluster" "0" "VM"
            ;;
    esac
    # zRAM tetap aktif, jangan sentuh zram/disksize
}

# ============================================================
# IO Apply
# ============================================================
_gb_apply_io() {
    local _level="$1"
    local _dev _name _sched_list
    for _dev in "$SYSFS_BLOCK_PREFIX"/sd* "$SYSFS_BLOCK_PREFIX"/mmcblk*; do
        [ -d "$_dev/queue" ] || continue
        _name=$(basename "$_dev")
        # Hanya device utama, bukan partisi
        case "$_name" in
            *p[0-9]*|*[0-9]rpmb|*[0-9]boot*) continue ;;
        esac

        # Scheduler: coba mq-deadline
        if [ -f "$_dev/queue/scheduler" ]; then
            _sched_list=$(cat "$_dev/queue/scheduler" 2>/dev/null)
            case "$_sched_list" in
                *"mq-deadline"*)
                    _gb_write "$_dev/queue/scheduler" "mq-deadline" "IO"
                    ;;
            esac
        fi

        # read_ahead_kb (modul33 stabil: extreme 2048, performance 2048)
        case "$_level" in
            extreme)     _gb_write "$_dev/queue/read_ahead_kb" "2048" "IO" ;;
            performance) _gb_write "$_dev/queue/read_ahead_kb" "2048" "IO" ;;
        esac
    done
}

# ============================================================
# Network Apply — best-effort bbr, backlog=16384, ecn=1
# ============================================================
_gb_apply_net() {
    local _level="$1"
    local _tcp_node="$PROC_SYS_PREFIX/net/ipv4/tcp_congestion_control"
    local _avail_node="$PROC_SYS_PREFIX/net/ipv4/tcp_available_congestion_control"
    local _tfo_node="$PROC_SYS_PREFIX/net/ipv4/tcp_fastopen"
    local _backlog_node="$PROC_SYS_PREFIX/net/core/netdev_max_backlog"
    local _ecn_node="$PROC_SYS_PREFIX/net/ipv4/tcp_ecn"

    # tcp_congestion_control = bbr (jika ada di available), else biarkan
    if [ -f "$_avail_node" ]; then
        local _avail
        _avail=$(cat "$_avail_node" 2>/dev/null)
        case " $_avail " in
            *" bbr "*) _gb_write "$_tcp_node" "bbr" "NET" ;;
            *)         _gb_log "INFO" "NET bbr unavailable, keeping current" ;;
        esac
    fi

    # tcp_fastopen = 3
    _gb_write "$_tfo_node" "3" "NET"

    # netdev_max_backlog = 16384
    _gb_write "$_backlog_node" "16384" "NET"

    # tcp_ecn = 1
    _gb_write "$_ecn_node" "1" "NET"
}

# ============================================================
# gb_apply — Terapkan game boost
# ============================================================
gb_apply() {
    # 0. Sakelar DISABLE_GAMEBOOST
    if [ -f "$CONF_DIR/DISABLE_GAMEBOOST" ]; then
        _gb_log "DISABLED" "DISABLE_GAMEBOOST file exists, skip"
        return 0
    fi

    # 1. Backup asli SEKALI
    _gb_backup_native || _gb_log "WARN" "backup incomplete, proceed anyway"

    # 2. Load defaults.conf
    if [ -f "$CONF_DIR/defaults.conf" ]; then
        . "$CONF_DIR/defaults.conf" 2>/dev/null
        GPU_MAX_FREQ="${GPU_MAX_FREQ:-0}"
    fi

    # 3. Detect level
    local _level
    _level=$(_gb_level)
    _gb_log "INFO" "level=$_level"

    # Balanced = pendinginannya device: kembali ke snapshot native
    # (restore CPU floor → native, GPU lock → native, cpuset → native,
    #  stune/uclamp → native), set fas-rs ke balance, selesai.
    # TIDAK panggil _gb_apply_cpu/gpu/vm/io/net supaya tidak
    # meninggalkan lantai.
    if [ "$_level" = "balanced" ]; then
        _gb_log "INFO" "balanced: restoring native snapshot (pendinginan)"
        gb_restore
        printf '%s\n' "balanced" > "$CONF_DIR/boost_level" 2>/dev/null
        _gb_set_fasrs_mode "balanced"
        _gb_log "INFO" "gb_apply complete level=balanced (restore-only)"
        return 0
    fi

    # 4. CPU — lantai tetap jalan walau fas-rs aktif (lantai ≠ mematikan fas-rs)
    local _cpu_owner="${CPU_OWNER:-alpha}"
    _gb_log "INFO" "CPU_OWNER=$_cpu_owner (lantai tetap dijalankan)"
    _gb_apply_cpu "$_level"

    # 5. GPU (SEMUA CPU_OWNER)
    _gb_apply_gpu "$_level"

    # 6. Memori (skip bila sakelar)
    if [ ! -f "$CONF_DIR/GAMEBOOST_NO_VM" ]; then
        _gb_apply_vm "$_level"
    else
        _gb_log "SKIPPED" "GAMEBOOST_NO_VM exists, skip VM tuning"
    fi

    # 7. IO
    _gb_apply_io "$_level"

    # 8. Jaringan
    _gb_apply_net "$_level"

    _gb_log "INFO" "gb_apply complete level=$_level"
    printf '%s\n' "$_level" > "$CONF_DIR/boost_level" 2>/dev/null
    _gb_set_fasrs_mode "$_level"
}

# Mode fas-rs mengikuti boost (tidak kill apa pun):
# extreme → fast (burst agresif buat game berat), performance → performance,
# balanced → balance.
_gb_set_fasrs_mode() {
    local _want=""
    case "$1" in
        extreme)     _want="fast" ;;
        performance) _want="performance" ;;
        balanced)    _want="balance" ;;
        *) return 0 ;;
    esac
    [ -r "/dev/fas_rs/mode" ] || return 0
    local _pcfg=""
    local _cand
    for _cand in /data/powercfg.sh \
        "${MODDIR:-/data/adb/modules/alpha_uperf_fasrs_fusion}/fasrs/powercfg.sh"; do
        if [ -f "$_cand" ] 2>/dev/null; then
            _pcfg="$_cand"
            break
        fi
    done
    [ -n "$_pcfg" ] || return 0
    sh "$_pcfg" "$_want" 2>/dev/null
    _gb_log "INFO" "fas-rs mode=$_want (boost)"
}

# ============================================================
# gb_restore — Pulihkan nilai asli
# ============================================================
gb_restore() {
    if [ -z "$CPU_POLICIES" ]; then
        _gb_log "WARN" "CPU_POLICIES unbound/empty; detect.sh harus di-source dulu; restore CPU dilewati"
    fi
    [ -f "$NATIVE_CONF" ] || { _gb_log "WARN" "no native backup, skip restore"; return 0; }
    _gb_log "INFO" "restore mulai"

    # CPU
    local _pol _gov _mn _mx
    for _pol in $CPU_POLICIES; do
        [ -d "$SYSFS_CPU_PREFIX/cpufreq/$_pol" ] || continue
        _gov=$(_gb_read_native "${_pol}_scaling_governor" "")
        _mn=$(_gb_read_native "${_pol}_scaling_min_freq" "")
        _mx=$(_gb_read_native "${_pol}_scaling_max_freq" "")
        # Tulis min dulu bila max < current min (pola HSIN restore)
        if [ -n "$_mx" ] && [ -n "$_mn" ]; then
            local _cur_min
            _cur_min=$(cat "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_min_freq" 2>/dev/null \
                       | tr -d '[:space:]')
            if [ -n "$_cur_min" ] && [ "$_mx" -lt "$_cur_min" ] 2>/dev/null; then
                _gb_write "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_min_freq" "$_mn" "CPU_RESTORE"
                _gb_write "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_max_freq" "$_mx" "CPU_RESTORE"
            else
                _gb_write "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_max_freq" "$_mx" "CPU_RESTORE"
                _gb_write "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_min_freq" "$_mn" "CPU_RESTORE"
            fi
        fi
        [ -n "$_gov" ] && _gb_write "$SYSFS_CPU_PREFIX/cpufreq/$_pol/scaling_governor" "$_gov" "CPU_RESTORE"
    done

    # Cpuset
    local _grp _val
    for _grp in top-app foreground background system-background; do
        _val=$(_gb_read_native "cpuset_${_grp}" "")
        [ -n "$_val" ] && _gb_write "${DEV_CPUSET_PREFIX:-/dev/cpuset}/$_grp/cpus" "$_val" "CPUSET_RESTORE"
    done

    # uclamp
    _val=$(_gb_read_native "uclamp_min" "")
    [ -n "$_val" ] && _gb_write "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.min" "$_val" "UCLAMP_RESTORE"
    _val=$(_gb_read_native "uclamp_max" "")
    [ -n "$_val" ] && _gb_write "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.max" "$_val" "UCLAMP_RESTORE"

    # stune
    _val=$(_gb_read_native "stune_boost" "")
    [ -n "$_val" ] && _gb_write "${DEV_STUNE_PREFIX:-/dev/stune}/top-app/schedtune.boost" "$_val" "STUNE_RESTORE"

    # Sched latency (hanya bila resolve berhasil)
    local _canon _p _v
    for _canon in $_GB_SCHED_NODES; do
        _v=$(_gb_read_native "$_canon" "")
        [ -z "$_v" ] && continue
        _p=$(_gb_sched_resolve "$_canon") || continue
        _gb_write "$_p" "$_v" "SCHED_RESTORE"
    done
    # sched_child_runs_first
    _v=$(_gb_read_native "sched_child_runs_first" "")
    [ -n "$_v" ] && _gb_write "$PROC_SYS_PREFIX/kernel/sched_child_runs_first" "$_v" "SCHED_RESTORE"

    # uscfreq down_rate hold (kembalikan native per policy; tanpa node → skip)
    local _upol _uv
    for _upol in $CPU_POLICIES; do
        _uv=$(_gb_read_native "${_upol}_uscfreq_down_rate" "")
        [ -n "$_uv" ] && _gb_write "$SYSFS_CPU_PREFIX/cpufreq/$_upol/uscfreq/down_rate_limit_us" "$_uv" "USCFREQ_RESTORE"
    done

    # GPU
    local _df _gname _old_gov _old_mx _old_mn
    for _df in "$SYSFS_DEVFREQ_PREFIX"/*; do
        [ -d "$_df" ] || continue
        _gname=$(basename "$_df")
        case "$_gname" in *gpu*|*mali*|*kgsl*|*adreno*) ;; *) continue ;; esac
        _old_gov=$(_gb_read_native "gpu_${_gname}_governor" "")
        _old_mx=$(_gb_read_native "gpu_${_gname}_max_freq" "")
        _old_mn=$(_gb_read_native "gpu_${_gname}_min_freq" "")
        # Tulis min dulu bila max < current min, hanya bila backup min ada.
        if [ -n "$_old_mx" ] && [ -w "$_df/max_freq" ]; then
            if [ -n "$_old_mn" ] && [ -w "$_df/min_freq" ]; then
                local _cur_min
                _cur_min=$(cat "$_df/min_freq" 2>/dev/null | tr -d '[:space:]')
                if [ -n "$_cur_min" ] && [ "$_old_mx" -lt "$_cur_min" ] 2>/dev/null; then
                    _gb_write "$_df/min_freq" "$_old_mn" "GPU_RESTORE"
                    _gb_write "$_df/max_freq" "$_old_mx" "GPU_RESTORE"
                else
                    _gb_write "$_df/max_freq" "$_old_mx" "GPU_RESTORE"
                    _gb_write "$_df/min_freq" "$_old_mn" "GPU_RESTORE"
                fi
            else
                _gb_write "$_df/max_freq" "$_old_mx" "GPU_RESTORE"
            fi
        fi
        [ -n "$_old_gov" ] && _gb_write "$_df/governor" "$_old_gov" "GPU_RESTORE"
    done

    # VM
    local _proc="$PROC_SYS_PREFIX"
    local _vmkey _v
    for _vmkey in vm/swappiness vm/vfs_cache_pressure vm/dirty_ratio vm/dirty_background_ratio vm/page-cluster; do
        _v=$(_gb_read_native "$_vmkey" "")
        [ -z "$_v" ] && continue
        _gb_write "$_proc/$_vmkey" "$_v" "VM_RESTORE"
    done

    # Network
    local _netbase="$PROC_SYS_PREFIX/net/ipv4"
    _v=$(_gb_read_native "tcp_congestion_control" "")
    [ -n "$_v" ] && _gb_write "$_netbase/tcp_congestion_control" "$_v" "NET_RESTORE"
    _v=$(_gb_read_native "tcp_fastopen" "")
    [ -n "$_v" ] && _gb_write "$_netbase/tcp_fastopen" "$_v" "NET_RESTORE"
    _v=$(_gb_read_native "tcp_ecn" "")
    [ -n "$_v" ] && _gb_write "$_netbase/tcp_ecn" "$_v" "NET_RESTORE"
    _v=$(_gb_read_native "netdev_max_backlog" "")
    [ -n "$_v" ] && _gb_write "$PROC_SYS_PREFIX/net/core/netdev_max_backlog" "$_v" "NET_RESTORE"

    # kbase (Mali)
    local _kbp="${SYSFS_MODULE_PREFIX:-/sys/module}/mali_kbase/parameters"
    if [ -d "$_kbp" ]; then
        for _kb in gpu_boost_level2 gpu_pollingtime gpu_upthreshold; do
            _v=$(_gb_read_native "kbase_$_kb" "")
            [ -n "$_v" ] && _gb_write "$_kbp/$_kb" "$_v" "KBASE_RESTORE"
        done
    fi

    # IO (scheduler + read_ahead per device utama)
    local _bdev _bname
    for _bdev in "$SYSFS_BLOCK_PREFIX"/sd* "$SYSFS_BLOCK_PREFIX"/mmcblk*; do
        [ -d "$_bdev/queue" ] || continue
        _bname=$(basename "$_bdev")
        case "$_bname" in
            *p[0-9]*|*[0-9]rpmb|*[0-9]boot*) continue ;;
        esac
        _v=$(_gb_read_native "io_${_bname}_read_ahead_kb" "")
        [ -n "$_v" ] && _gb_write "$_bdev/queue/read_ahead_kb" "$_v" "IO_RESTORE"
        _v=$(_gb_read_native "io_${_bname}_scheduler" "")
        [ -n "$_v" ] && _gb_write "$_bdev/queue/scheduler" "$_v" "IO_RESTORE"
    done

    _gb_log "INFO" "gb_restore complete"
    rm -f "$CONF_DIR/boost_level" 2>/dev/null
    _gb_restore_fasrs_mode
}

# Kembalikan mode fas-rs sesuai current_state (battery→powersave,
# balanced→balance, performance→performance). Best-effort.
_gb_restore_fasrs_mode() {
    [ -r "/dev/fas_rs/mode" ] || return 0
    local _st=""
    [ -f "$CONF_DIR/current_state" ] && \
        _st=$(tr -d '[:space:]' < "$CONF_DIR/current_state" 2>/dev/null)
    local _want=""
    case "$_st" in
        battery) _want="powersave" ;;
        balanced) _want="balance" ;;
        performance) _want="performance" ;;
        *) return 0 ;;
    esac
    local _pcfg=""
    local _cand
    for _cand in /data/powercfg.sh \
        "${MODDIR:-/data/adb/modules/alpha_uperf_fasrs_fusion}/fasrs/powercfg.sh"; do
        if [ -f "$_cand" ] 2>/dev/null; then
            _pcfg="$_cand"
            break
        fi
    done
    [ -n "$_pcfg" ] || return 0
    sh "$_pcfg" "$_want" 2>/dev/null
    _gb_log "INFO" "fas-rs mode=$_want (restore, state=$_st)"
}

return 0 2>/dev/null || true
