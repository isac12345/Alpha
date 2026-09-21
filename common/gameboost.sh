#!/system/bin/sh
# Alpha Fusion - Game Boost Engine (Extreme / Performance)
# Paritas HSIN extreme + performance; generic untuk semua device + game.
# POSIX sh; semua tulis = dua kali tulis-baca-verifikasi.
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
        _pass=$((_pass + 1))
    done
    _gb_log "FAILED" "$_cat node=$_node value=$_val readback=$_rb"
    return 1
}

# ============================================================
# Level Detection
# ============================================================
_gb_level() {
    if [ -f "$CONF_DIR/GAMEBOOST_LEVEL" ]; then
        local _lv
        _lv=$(cat "$CONF_DIR/GAMEBOOST_LEVEL" 2>/dev/null \
              | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        [ "$_lv" = "performance" ] && { echo "performance"; return 0; }
    fi
    echo "extreme"
}

# ============================================================
# Cluster Topology (hsin_cpu_topo_detect)
# ============================================================
_gb_topo_detect() {
    GB_CPU_BIG="" GB_CPU_LITTLE=""
    local _max_all=0 _p _mx _cpus
    for _p in "$SYSFS_CPU_PREFIX"/cpufreq/policy*; do
        [ -d "$_p" ] || continue
        _mx=$(cat "$_p/cpuinfo_max_freq" 2>/dev/null | tr -d '[:space:]')
        case "$_mx" in ''|*[!0-9]*) continue ;; esac
        [ "$_mx" -gt "$_max_all" ] 2>/dev/null && _max_all="$_mx"
    done
    [ "$_max_all" -eq 0 ] 2>/dev/null && return 1
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
# Scheduler Latency (capture native + apply via persentase)
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
# ============================================================
_gb_backup_native() {
    [ -f "$NATIVE_CONF" ] && return 0
    mkdir -p "$CONF_DIR" 2>/dev/null
    : > "$NATIVE_CONF.tmp" 2>/dev/null || return 1
    local _pol _gov _mn _mx _avail _mx_val
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
    # Sched latency
    local _canon _p _v
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
# CPU Apply (hanya bila CPU_OWNER != fas-rs)
# ============================================================
_gb_apply_cpu() {
    local _level="$1"
    local _pol _pol_dir _avail_file _gov_node _avail_govs _target_gov
    local _hw_max _avail_list _opp_list _target_freq

    for _pol in $CPU_POLICIES; do
        _pol_dir="$SYSFS_CPU_PREFIX/cpufreq/$_pol"
        [ -d "$_pol_dir" ] || continue

        # --- Governor ---
        _avail_file="$_pol_dir/scaling_available_governors"
        _gov_node="$_pol_dir/scaling_governor"
        if [ "$_level" = "extreme" ]; then
            _target_gov="performance"
        else
            _target_gov="schedutil"
        fi
        if [ -f "$_avail_file" ]; then
            _avail_govs=$(cat "$_avail_file" 2>/dev/null)
            case " $_avail_govs " in
                *" $_target_gov "*)
                    _gb_write "$_gov_node" "$_target_gov" "CPU_GOV"
                    ;;
                *)
                    # Cadangan
                    local _fallback=""
                    case "$_level" in
                        extreme)
                            for _fb in schedutil walt interactive; do
                                case "$_avail_govs" in
                                    *" $_fb "*) _fallback="$_fb"; break ;;
                                esac
                            done
                            ;;
                        performance)
                            for _fb in performance schedutil walt; do
                                case "$_avail_govs" in
                                    *" $_fb "*) _fallback="$_fb"; break ;;
                                esac
                            done
                            ;;
                    esac
                    [ -n "$_fallback" ] && _gb_write "$_gov_node" "$_fallback" "CPU_GOV"
                    ;;
            esac
        fi

        # --- Frequency ---
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

        if [ "$_level" = "extreme" ]; then
            # min=max=maksimum bawaan
            if [ -n "$_opp_list" ]; then
                _target_freq=$(echo "$_opp_list" | tail -n 1)
            else
                _target_freq="$_hw_max"
            fi
        else
            # performance: min 35% max, max 100%
            if [ -n "$_opp_list" ]; then
                _target_freq=$(echo "$_opp_list" | tail -n 1)
            else
                _target_freq="$_hw_max"
            fi
            local _min_target=$((_target_freq * 35 / 100))
            if [ -n "$_opp_list" ]; then
                local _best=""
                for _f in $_opp_list; do
                    case "$_f" in ''|*[!0-9]*) continue ;; esac
                    if [ "$_f" -le "$_min_target" ]; then
                        [ -z "$_best" ] || [ "$_f" -gt "$_best" ] && _best="$_f"
                    fi
                done
                [ -n "$_best" ] && _gb_write "$_pol_dir/scaling_min_freq" "$_best" "CPU_FREQ"
            fi
        fi

        # extreme: min=max (lock); performance: max only
        _gb_write "$_pol_dir/scaling_max_freq" "$_target_freq" "CPU_FREQ"
        if [ "$_level" = "extreme" ]; then
            _gb_write "$_pol_dir/scaling_min_freq" "$_target_freq" "CPU_FREQ"
        fi
    done

    # --- Cpuset (skip bila sakelar NO_CPUSET) ---
    if [ ! -f "$CONF_DIR/NO_CPUSET" ]; then
        if [ -d "${DEV_CPUSET_PREFIX:-/dev/cpuset}" ]; then
            _gb_topo_detect
            if [ -n "$GB_CPU_BIG" ] && [ -n "$GB_CPU_LITTLE" ]; then
                local _grp
                for _grp in top-app foreground; do
                    [ -w "${DEV_CPUSET_PREFIX:-/dev/cpuset}/$_grp/cpus" ] && \
                        _gb_write "${DEV_CPUSET_PREFIX:-/dev/cpuset}/$_grp/cpus" "$GB_CPU_BIG" "CPUSET"
                done
                for _grp in background system-background; do
                    [ -w "${DEV_CPUSET_PREFIX:-/dev/cpuset}/$_grp/cpus" ] && \
                        _gb_write "${DEV_CPUSET_PREFIX:-/dev/cpuset}/$_grp/cpus" "$GB_CPU_LITTLE" "CPUSET"
                done
            fi
        fi
    else
        _gb_log "SKIPPED" "NO_CPUSET exists, skip cpuset"
    fi

    # --- uclamp ---
    if [ -d "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}" ]; then
        case "$_level" in
            extreme)     _gb_write "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.min" "60" "UCLAMP"
                         _gb_write "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.max" "100" "UCLAMP" ;;
            performance) _gb_write "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.min" "15" "UCLAMP"
                         _gb_write "${DEV_CPUCTL_PREFIX:-/dev/cpuctl}/foreground/cpu.uclamp.max" "100" "UCLAMP" ;;
        esac
    fi

    # --- stune ---
    if [ -d "${DEV_STUNE_PREFIX:-/dev/stune}" ]; then
        case "$_level" in
            extreme)     _gb_write "${DEV_STUNE_PREFIX:-/dev/stune}/top-app/schedtune.boost" "100" "STUNE" ;;
            performance) _gb_write "${DEV_STUNE_PREFIX:-/dev/stune}/top-app/schedtune.boost" "40" "STUNE" ;;
        esac
    fi

    # --- sched_child_runs_first ---
    _gb_write "$PROC_SYS_PREFIX/kernel/sched_child_runs_first" "1" "SCHED"

    # --- Scheduler latency ---
    case "$_level" in
        extreme)     _gb_sched_apply_level 40 40 30 1000 ;;
        performance) _gb_sched_apply_level 70 70 60 400 ;;
    esac
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
            _govs=$(cat "$_df/available_governors" 2>/dev/null)
            local _want="performance"
            case " $_govs " in
                *" $_want "*)
                    _gb_write "$_df/governor" "$_want" "GPU_GOV"
                    ;;
                *)
                    local _fb=""
                    for _fb in schedutil simple_ondemand ondemand; do
                        case "$_govs" in
                            *" $_fb "*) _gb_write "$_df/governor" "$_fb" "GPU_GOV"; break ;;
                        esac
                    done
                    ;;
            esac
        fi

        # Max freq = GPU_MAX_FREQ bawaan (cap ke OPP tabel)
        _opp_list=""
        if [ -f "$_df/available_frequencies" ]; then
            _opp_list=$(cat "$_df/available_frequencies" 2>/dev/null \
                        | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n)
            _hw_max=$(echo "$_opp_list" | tail -n 1)
        fi
        if [ -z "$_hw_max" ] && [ -f "$_df/cur_freq" ]; then
            _hw_max=$(cat "$_df/cur_freq" 2>/dev/null | tr -d '[:space:]')
        fi
        [ -z "$_hw_max" ] && continue

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
        # extreme: min=max (lock GPU)
        if [ "$_level" = "extreme" ] && [ -w "$_df/min_freq" ]; then
            _gb_write "$_df/min_freq" "$_target" "GPU"
        fi
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
# VM Apply
# ============================================================
_gb_apply_vm() {
    local _level="$1"
    case "$_level" in
        extreme)     _gb_write "$PROC_SYS_PREFIX/vm/swappiness" "10" "VM" ;;
        performance) _gb_write "$PROC_SYS_PREFIX/vm/swappiness" "60" "VM" ;;
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

        # read_ahead_kb
        case "$_level" in
            extreme)     _gb_write "$_dev/queue/read_ahead_kb" "4096" "IO" ;;
            performance) _gb_write "$_dev/queue/read_ahead_kb" "2048" "IO" ;;
        esac
    done
}

# ============================================================
# Network Apply
# ============================================================
_gb_apply_net() {
    local _level="$1"
    local _tcp_node="$PROC_SYS_PREFIX/net/ipv4/tcp_congestion_control"
    local _avail_node="$PROC_SYS_PREFIX/net/ipv4/tcp_available_congestion_control"
    local _tfo_node="$PROC_SYS_PREFIX/net/ipv4/tcp_fastopen"

    # tcp_congestion_control = bbr (jika ada di available)
    if [ -f "$_avail_node" ]; then
        local _avail
        _avail=$(cat "$_avail_node" 2>/dev/null)
        case " $_avail " in
            *" bbr "*) _gb_write "$_tcp_node" "bbr" "NET" ;;
            *)         _gb_write "$_tcp_node" "cubic" "NET" ;;
        esac
    fi

    # tcp_fastopen = 3
    _gb_write "$_tfo_node" "3" "NET"
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

    # 4. CPU (skip bila fas-rs)
    if [ "${CPU_OWNER:-alpha}" != "fas-rs" ]; then
        _gb_apply_cpu "$_level"
    else
        _gb_log "SKIPPED" "CPU_OWNER=fas-rs, skip semua CPU tuning"
    fi

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
}

# ============================================================
# gb_restore — Pulihkan nilai asli
# ============================================================
gb_restore() {
    [ -f "$NATIVE_CONF" ] || { _gb_log "WARN" "no native backup, skip restore"; return 0; }
    _gb_log "INFO" "restore mulai"

    # CPU
    if [ "${CPU_OWNER:-alpha}" != "fas-rs" ]; then
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

        # Sched latency
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
    fi

    # GPU
    local _df _gname _old_gov _old_mx
    for _df in "$SYSFS_DEVFREQ_PREFIX"/*; do
        [ -d "$_df" ] || continue
        _gname=$(basename "$_df")
        case "$_gname" in *gpu*|*mali*|*kgsl*|*adreno*) ;; *) continue ;; esac
        _old_gov=$(_gb_read_native "gpu_${_gname}_governor" "")
        _old_mx=$(_gb_read_native "gpu_${_gname}_max_freq" "")
        local _old_mn
        _old_mn=$(_gb_read_native "gpu_${_gname}_min_freq" "$_old_mx")
        # Tulis min dulu bila max < current min
        if [ -n "$_old_mx" ] && [ -w "$_df/min_freq" ]; then
            local _cur_min
            _cur_min=$(cat "$_df/min_freq" 2>/dev/null | tr -d '[:space:]')
            if [ -n "$_cur_min" ] && [ "$_old_mx" -lt "$_cur_min" ] 2>/dev/null; then
                _gb_write "$_df/min_freq" "$_old_mn" "GPU_RESTORE"
                _gb_write "$_df/max_freq" "$_old_mx" "GPU_RESTORE"
            else
                _gb_write "$_df/max_freq" "$_old_mx" "GPU_RESTORE"
                _gb_write "$_df/min_freq" "$_old_mn" "GPU_RESTORE" 2>/dev/null
            fi
        fi
        [ -n "$_old_gov" ] && _gb_write "$_df/governor" "$_old_gov" "GPU_RESTORE"
    done

    _gb_log "INFO" "gb_restore complete"
    rm -f "$CONF_DIR/boost_level" 2>/dev/null
}

return 0 2>/dev/null || true
