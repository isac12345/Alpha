#!/system/bin/sh
# Alpha v1 - Core Execution Engine
# Sintesis fitur teruji dari RaiRin-AI, Uperf, RaiRin-Liquid, fas-rs

LOG_FILE="${ALPHA_LOG_FILE:-/data/adb/alpha/alpha.log}"
SYSFS_CPU_PREFIX="${SYSFS_CPU_PREFIX:-/sys/devices/system/cpu}"
SYSFS_BLOCK_PREFIX="${SYSFS_BLOCK_PREFIX:-/sys/block}"
SYSFS_DEVFREQ_PREFIX="${SYSFS_DEVFREQ_PREFIX:-/sys/class/devfreq}"
SYSFS_THERMAL_PREFIX="${SYSFS_THERMAL_PREFIX:-/sys/devices/virtual/thermal}"
PROC_SYS_PREFIX="${PROC_SYS_PREFIX:-/proc/sys}"
SYSFS_MODULE_PREFIX="${SYSFS_MODULE_PREFIX:-/sys/module}"

# Inisialisasi counter summary
APPLIED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

log_msg() {
    local status="$1"
    local category="$2"
    local detail="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    
    if [ "${ALPHA_DRYRUN:-0}" = "1" ]; then
        echo "[$timestamp] [$category] [$status] (DRY-RUN) $detail"
    fi
    
    if [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "[$timestamp] [$category] [$status] $detail" >> "$LOG_FILE" 2>/dev/null
    fi
}

# --- GATEWAY FUNCTION: apply_tweak ---
# Memastikan semua write aman, divalidasi test -w, dan dicatat ke log
apply_tweak() {
    local category="$1"
    local path="$2"
    local value="$3"
    local policy_skip="${4:-0}"

    if [ "$policy_skip" = "1" ]; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        log_msg "SKIPPED" "$category" "path=$path (profile policy)"
        return 0
    fi
    
    if [ ! -e "$path" ]; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        log_msg "SKIPPED" "$category" "path=$path (node tidak ditemukan)"
        return 0
    fi
    
    # Mode dry-run untuk testing/simulasi tanpa menyentuh kernel
    if [ "${ALPHA_DRYRUN:-0}" = "1" ]; then
        APPLIED_COUNT=$((APPLIED_COUNT + 1))
        log_msg "APPLIED" "$category" "path=$path value=$value"
        return 0
    fi
    
    # Berikan izin tulis jika perlu
    if [ ! -w "$path" ]; then
        chmod 0644 "$path" 2>/dev/null
    fi
    
    if [ -w "$path" ]; then
        if echo "$value" > "$path" 2>/dev/null; then
            APPLIED_COUNT=$((APPLIED_COUNT + 1))
            log_msg "APPLIED" "$category" "path=$path value=$value"
            return 0
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
            log_msg "FAILED" "$category" "path=$path value=$value (write rejected)"
            return 1
        fi
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        log_msg "FAILED" "$category" "path=$path (not writable)"
        return 1
    fi
}

# --- 1. TUNE GOVERNOR ---
# Adaptasi metode Uperf: validasi governor terhadap scaling_available_governors
tune_governor() {
    local category="CPU_GOV"
    for pol in $CPU_POLICIES; do
        local pol_dir="$SYSFS_CPU_PREFIX/cpufreq/$pol"
        local avail_file="$pol_dir/scaling_available_governors"
        local gov_node="$pol_dir/scaling_governor"
        
        if [ ! -f "$avail_file" ]; then
            continue
        fi
        
        local avail_govs
        avail_govs=$(cat "$avail_file" 2>/dev/null)
        
        local selected_gov=""
        for target in $GOVERNOR_PREFERENCE; do
            case " $avail_govs " in
                *" $target "*)
                    selected_gov="$target"
                    break
                    ;;
            esac
        done
        
        if [ -n "$selected_gov" ]; then
            apply_tweak "$category" "$gov_node" "$selected_gov"
        fi
    done
}

# --- 2. TUNE CPU FREQ ---
# Profile max percentage is mapped to the highest valid OPP at or below target.
tune_cpu_freq() {
    local category="CPU_FREQ"
    for pol in $CPU_POLICIES; do
        local pol_dir="$SYSFS_CPU_PREFIX/cpufreq/$pol"
        local avail_freq_file="$pol_dir/scaling_available_frequencies"
        local cpuinfo_max_file="$pol_dir/cpuinfo_max_freq"
        local max_node="$pol_dir/scaling_max_freq"
        local min_node="$pol_dir/scaling_min_freq"
        
        local hardware_max=""
        if [ -f "$avail_freq_file" ]; then
            hardware_max=$(tr ' ' '\n' < "$avail_freq_file" 2>/dev/null | grep -E '^[0-9]+$' | sort -nr | head -n 1)
        fi
        if [ -z "$hardware_max" ] && [ -f "$cpuinfo_max_file" ]; then
            hardware_max=$(cat "$cpuinfo_max_file" 2>/dev/null)
        fi

        local max_percent="${CPU_FREQ_MAX_PERCENT:-100}"
        case "$max_percent" in
            ''|*[!0-9]*) max_percent=100 ;;
        esac
        [ "$max_percent" -gt 100 ] 2>/dev/null && max_percent=100
        local target_max=""
        if [ -n "$hardware_max" ]; then
            # Bagi dulu baru kali, supaya tidak overflow kalau frekuensi
            # dilaporkan kernel dalam Hz (bukan kHz) - lihat kasus sama di GPU.
            target_max=$(( (hardware_max / 100) * max_percent ))
            if [ -f "$avail_freq_file" ]; then
                local max_freqs
                max_freqs=$(tr ' ' '\n' < "$avail_freq_file" 2>/dev/null | grep -E '^[0-9]+$' | sort -n)
                target_max=$(alpha_opp_snap_nearest "$target_max" "$max_freqs")
            fi
        fi

        if [ -n "$target_max" ]; then
            apply_tweak "$category" "$max_node" "$target_max"

            if [ "${CPU_FREQ_MIN_SKIP:-1}" != "1" ]; then
                local min_target="$target_max"
                if [ -n "${CPU_FREQ_MIN_PERCENT:-}" ] && [ "$CPU_FREQ_MIN_PERCENT" -lt 100 ] 2>/dev/null; then
                    min_target=$(( target_max * CPU_FREQ_MIN_PERCENT / 100 ))
                fi
                if [ -f "$avail_freq_file" ]; then
                    local min_freqs
                    min_freqs=$(tr ' ' '\n' < "$avail_freq_file" 2>/dev/null | grep -E '^[0-9]+$' | sort -n)
                    min_target=$(alpha_opp_snap_nearest "$min_target" "$min_freqs")
                fi
                [ -n "$min_target" ] && apply_tweak "$category" "$min_node" "$min_target"
            fi
            
            # Verifikasi pembacaan ulang (pola RaiRin-AI)
            if [ "${ALPHA_DRYRUN:-0}" != "1" ] && [ -f "$max_node" ]; then
                local current_max
                current_max=$(cat "$max_node" 2>/dev/null)
                if [ "$current_max" != "$target_max" ]; then
                    log_msg "WARN" "$category" "verifikasi mismatch: current=$current_max target=$target_max ($pol)"
                fi
            fi
        fi
    done
}

# --- 3. TUNE GPU ADRENO ---
# Hanya profile yang mengizinkan yang menulis powerlevel numeric.
# Battery/Balanced skip agar default power management tetap berjalan.
tune_gpu_adreno() {
    local category="GPU"
    local kgsl_dir="${GPU_SYSFS_PREFIX:-/sys}/class/kgsl/kgsl-3d0"
    local pwr_node="$kgsl_dir/default_pwrlevel"
    local _cap_rc=0

    if [ "${GPU_ADRENO_SKIP:-1}" = "1" ] || [ "${GPU_ADRENO_MODE:-stock}" = "stock" ]; then
        log_msg "SKIPPED" "$category" "Adreno profile skip enabled"
        return 0
    fi

    if [ ! -d "$kgsl_dir" ]; then
        log_msg "SKIPPED" "$category" "Adreno node tidak ditemukan"
        return 0
    fi

    if [ "${GPU_ADRENO_MODE:-}" = "cap" ]; then
        tune_gpu_adreno_cap "$category" "$kgsl_dir"
        _cap_rc=$?
        # Pola sama seperti Mali: ceiling dulu, baru ramp. Ramp bersifat
        # best-effort (skip aman kalau node tidak ada), jadi rc yang
        # dikembalikan tetap milik ceiling.
        tune_gpu_adreno_kgsl "$category" "$kgsl_dir"
        return "$_cap_rc"
    fi

    if [ -f "$pwr_node" ]; then
        if [ "${GPU_ADRENO_MODE:-}" != "performance" ]; then
            log_msg "SKIPPED" "$category" "unsupported Adreno mode=${GPU_ADRENO_MODE:-empty}"
            return 0
        fi
        case "${GPU_ADRENO_POWERLEVEL:-}" in
            ''|*[!0-9]*)
                log_msg "SKIPPED" "$category" "invalid numeric powerlevel"
                return 0
                ;;
            *)
                apply_tweak "$category" "$pwr_node" "$GPU_ADRENO_POWERLEVEL"
                ;;
        esac
    else
        log_msg "SKIPPED" "$category" "Adreno node tidak ditemukan"
    fi
}

tune_gpu_adreno_kgsl() {
    local category="$1"
    local kgsl_dir="$2"
    local df_dir="$kgsl_dir/devfreq"
    local gov_file="$df_dir/governor"
    local gov=""
    local poll_target=""
    local up_target=""
    local down_target=""

    [ -f "$gov_file" ] || { log_msg "SKIPPED" "$category" "kgsl governor tidak terbaca, ramp tuning skip"; return 0; }
    gov=$(alpha_safe_read "$gov_file" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    [ -n "$gov" ] || { log_msg "SKIPPED" "$category" "kgsl governor kosong, ramp tuning skip"; return 0; }

    case "$gov" in
        *adreno-tz*|*adreno_tz*)
            # msm-adreno-tz TIDAK punya tunable sysfs (dari source
            # governor: hanya get_target_freq + event_handler, tanpa
            # governor_attrs). Satu-satunya knob generik yang aman dan
            # selalu ada di devfreq core: polling_interval (ms).
            case "${ACTIVE_PROFILE:-balanced}" in
                battery) poll_target=100 ;;
                balanced) poll_target=50 ;;
                performance) poll_target=10 ;;
                *) poll_target=50 ;;
            esac
            ;;
        *simple_ondemand*)
            # up_threshold: beban % pemicu naik (rendah = ramp cepat).
            # down_differential: turun kalau beban < up - diff (kecil =
            # downclock agresif/hemat, besar = tahan di clock tinggi).
            case "${ACTIVE_PROFILE:-balanced}" in
                battery) poll_target=100; up_target=90; down_target=3 ;;
                balanced) poll_target=50; up_target=75; down_target=5 ;;
                performance) poll_target=10; up_target=50; down_target=10 ;;
                *) poll_target=50; up_target=75; down_target=5 ;;
            esac
            ;;
        *)
            log_msg "SKIPPED" "$category" "governor=$gov tidak dikenal, ramp tuning skip aman"
            return 0
            ;;
    esac

    # Thermal gate HANYA untuk tier agresif (performance) - filosofi sama
    # seperti Mali (ceiling ditahan saat panas). Threshold Adreno tetap
    # default 65000 (backward-compat, jangan diubah). Tier konservatif
    # balanced/battery selalu diterapkan (aman secara termal).
    if [ "${ACTIVE_PROFILE:-balanced}" = "performance" ] && gpu_thermal_is_hot; then
        log_msg "SKIPPED" "$category" "thermal panas, adreno ramp agresif ditahan"
        return 0
    fi

    if [ -n "$poll_target" ]; then
        if [ -w "$df_dir/polling_interval" ]; then
            apply_tweak "$category" "$df_dir/polling_interval" "$poll_target"
        else
            log_msg "SKIPPED" "$category" "polling_interval tidak writable/tidak ada, skip"
        fi
    fi

    # Tunable simple_ondemand: tulis HANYA kalau node benar-benar ada dan
    # writable. Mainline devfreq TIDAK expose tunable ini via sysfs
    # (nilai dari DT), dan vendor sering strip - jadi jalur SKIPPED di
    # bawah adalah hasil NORMAL, bukan error. Jangan gagalkan apply.
    if [ -n "$up_target" ]; then
        local gov_dir=""
        local cand_dir=""
        for cand_dir in "$df_dir/governor" "$df_dir"; do
            if [ -f "$cand_dir/up_threshold" ] && [ -f "$cand_dir/down_differential" ]; then
                gov_dir="$cand_dir"
                break
            fi
        done
        if [ -n "$gov_dir" ]; then
            [ -w "$gov_dir/up_threshold" ] && apply_tweak "$category" "$gov_dir/up_threshold" "$up_target"
            [ -w "$gov_dir/down_differential" ] && apply_tweak "$category" "$gov_dir/down_differential" "$down_target"
        else
            log_msg "SKIPPED" "$category" "simple_ondemand tunable tidak diexpose kernel ini, skip (normal)"
        fi
    fi
}

alpha_safe_read() {
    # cat biasa, tapi dikasih timeout kalau tersedia - beberapa driver
    # thermal vendor bisa nge-block selamanya pas node sensornya lagi
    # bermasalah, dan itu bikin apply_now.sh (dan pemanggil yang nunggunya)
    # ikut hang total. Timeout bikin node yang macet dianggap gak terbaca
    # (aman, di-skip) daripada nge-freeze semuanya.
    if command -v timeout >/dev/null 2>&1; then
        timeout 2 cat "$1" 2>/dev/null
    else
        cat "$1" 2>/dev/null
    fi
}

ALPHA_GPU_HOT_THRESHOLD_PERFORMANCE=75000

gpu_thermal_is_hot() {
    local gpu_hot=0
    local threshold="${1:-65000}"
    local found_specific=0
    # Cache-first: baca NILAI live dari sensor yang sudah divalidasi
    # detect.sh (path dari cache, bukan scan ulang). Nilai suhu tetap live.
    if [ "${THERMAL_SUPPORTED:-0}" = "1" ] && [ -r "${THERMAL_PATH:-}" ]; then
        local cached_temp
        cached_temp=$(alpha_safe_read "$THERMAL_PATH" | tr -d '[:space:]')
        case "$cached_temp" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$cached_temp" -ge "$threshold" ] 2>/dev/null; then
                    return 0
                fi
                return 1
                ;;
        esac
    fi
    for gpu_zone in "$SYSFS_THERMAL_PREFIX"/thermal_zone*; do
        [ -d "$gpu_zone" ] || continue
        local type_file="$gpu_zone/type"
        [ -f "$type_file" ] || continue
        local zone_type
        zone_type=$(alpha_safe_read "$type_file" | tr '[:upper:]' '[:lower:]')
        case "$zone_type" in
            *gpu*|*soc*|*tsens*|*cpu*)
                found_specific=1
                local gpu_temp
                gpu_temp=$(alpha_safe_read "$gpu_zone/temp" | tr -d '[:space:]')
                case "$gpu_temp" in
                    ''|*[!0-9]*) continue ;;
                esac
                if [ "$gpu_temp" -ge "$threshold" ] 2>/dev/null; then
                    gpu_hot=1
                    break
                fi
                ;;
        esac
    done
    if [ "$found_specific" = "0" ]; then
        # fallback lama: scan semua zona, tapi tetap pakai threshold yang dikirim
        for gpu_zone in "$SYSFS_THERMAL_PREFIX"/thermal_zone*/temp; do
            [ -f "$gpu_zone" ] || continue
            local gpu_temp
            gpu_temp=$(alpha_safe_read "$gpu_zone" | tr -d '[:space:]')
            case "$gpu_temp" in
                ''|*[!0-9]*) continue ;;
            esac
            if [ "$gpu_temp" -ge "$threshold" ] 2>/dev/null; then
                gpu_hot=1
                break
            fi
        done
    fi
    [ "$gpu_hot" = "1" ]
}

tune_gpu_adreno_cap() {
    local category="$1"
    local kgsl_dir="$2"
    local gpu_table=""
    if [ -f "$kgsl_dir/devfreq/available_frequencies" ]; then
        gpu_table=$(alpha_safe_read "$kgsl_dir/devfreq/available_frequencies" | tr ' ' '\n' | grep -E '^[0-9]+$')
    fi
    if [ -z "$gpu_table" ] && [ -f "$kgsl_dir/gpu_available_frequencies" ]; then
        gpu_table=$(alpha_safe_read "$kgsl_dir/gpu_available_frequencies" | tr ' ' '\n' | grep -E '^[0-9]+$')
    fi
    if [ -z "$gpu_table" ]; then
        log_msg "SKIPPED" "$category" "cap mode but no readable GPU frequency table"
        return 0
    fi
    local gpu_hw_max
    gpu_hw_max=$(printf '%s\n' "$gpu_table" | sort -nr | head -n 1)
    # M3: bila defaults.conf mencatat GPU_MAX_FREQ valid dan <= tabel,
    # pakai itu sebagai acuan 100% (bawaan perangkat, bukan tabel OPP).
    if [ -n "${GPU_MAX_FREQ:-}" ]; then
        case "$GPU_MAX_FREQ" in ''|*[!0-9]*) ;;
            *)
                if [ "$GPU_MAX_FREQ" -gt 0 ] 2>/dev/null && [ "$GPU_MAX_FREQ" -le "$gpu_hw_max" ] 2>/dev/null; then
                    log_msg "INFO" "$category" "M3: acuan GPU_MAX_FREQ=$GPU_MAX_FREQ (defaults.conf)"
                    gpu_hw_max="$GPU_MAX_FREQ"
                fi
                ;;
        esac
    fi
    local gpu_percent="${GPU_FREQ_MAX_PERCENT:-100}"
    case "$gpu_percent" in
        ''|*[!0-9]*) gpu_percent=100 ;;
    esac
    [ "$gpu_percent" -gt 100 ] 2>/dev/null && gpu_percent=100
    local gpu_target=$(( (gpu_hw_max / 100) * gpu_percent ))
    gpu_target=$(alpha_opp_cap_pick "$gpu_target" "$(printf '%s\n' "$gpu_table" | sort -n)")
    if [ -z "$gpu_target" ]; then
        log_msg "SKIPPED" "$category" "cap target invalid"
        return 0
    fi
    if [ "$gpu_percent" -ge 100 ] && gpu_thermal_is_hot; then
        log_msg "SKIPPED" "$category" "thermal sedang panas, performance cap ditahan"
        return 0
    fi
    local gpu_level=0
    local gpu_idx=0
    local gpu_best=""
    local gpu_best_freq=""
    for gpu_freq in $gpu_table; do
        case "$gpu_freq" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$gpu_freq" -le "$gpu_target" ]; then
                    if [ -z "$gpu_best" ] || [ "$gpu_freq" -gt "$gpu_best_freq" ]; then
                        gpu_best="$gpu_idx"
                        gpu_best_freq="$gpu_freq"
                    fi
                fi
                ;;
        esac
        gpu_idx=$((gpu_idx + 1))
    done
    if [ -z "$gpu_best" ]; then
        log_msg "SKIPPED" "$category" "no pwrlevel maps to target=$gpu_target"
        return 0
    fi
    if [ -f "$kgsl_dir/num_pwrlevels" ]; then
        local gpu_num
        gpu_num=$(tr -d '[:space:]' < "$kgsl_dir/num_pwrlevels" 2>/dev/null)
        case "$gpu_num" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$gpu_best" -ge "$gpu_num" ] 2>/dev/null; then
                    log_msg "SKIPPED" "$category" "level=$gpu_best di luar num_pwrlevels=$gpu_num"
                    return 0
                fi
                ;;
        esac
    fi
    if [ "$gpu_percent" -ge 100 ]; then
        log_msg "WARN" "$category" "performance ceiling level=$gpu_best freq=$gpu_best_freq (floor dibiarkan default, thermal dicek sesaat sebelum apply)"
    fi
    apply_tweak "$category" "$kgsl_dir/min_pwrlevel" "$gpu_best"
}

tune_gpu_mali_kbase() {
    local category="GPU"
    local kbase="${SYSFS_MODULE_PREFIX:-/sys/module}/mali_kbase/parameters"
    [ -d "$kbase" ] || { log_msg "SKIPPED" "$category" "mali_kbase/parameters tidak ada, skip aman"; return 0; }

    local boost pollingtime upthreshold
    case "${ACTIVE_PROFILE:-balanced}" in
        battery)
            boost=0; pollingtime=8; upthreshold=88 ;;
        balanced)
            boost=0; pollingtime=4; upthreshold=65 ;;
        performance)
            boost=1; pollingtime=1; upthreshold=15 ;;
        *)
            boost=0; pollingtime=4; upthreshold=75 ;;
    esac

    [ -w "$kbase/gpu_boost_level2" ]  && apply_tweak "$category" "$kbase/gpu_boost_level2" "$boost"
    [ -w "$kbase/gpu_pollingtime" ]   && apply_tweak "$category" "$kbase/gpu_pollingtime" "$pollingtime"
    [ -w "$kbase/gpu_upthreshold" ]   && apply_tweak "$category" "$kbase/gpu_upthreshold" "$upthreshold"
}

tune_gpu_mali() {
    local category="GPU"
    local mali_dev=""
    local mali_candidates=""
    # Cache-first: pakai hasil detect.sh. Glob di bawah cuma fallback
    # kalau cache kosong (DETECT_VERSION lama / GPU path tak ketemu).
    if [ -n "${GPU_DEVFREQ_PATH:-}" ] && [ -f "$GPU_DEVFREQ_PATH/available_frequencies" ] && [ -f "$GPU_DEVFREQ_PATH/max_freq" ]; then
        mali_dev="$GPU_DEVFREQ_PATH"
    fi
    if [ -z "$mali_dev" ]; then
        [ -n "${GPU_DEVFREQ_PATH:-}" ] || log_msg "SKIPPED" "$category" "GPU_DEVFREQ_PATH kosong di cache, pakai fallback scan"
        for mali_cand in "${GPU_SYSFS_PREFIX:-/sys}"/class/misc/mali0/device/devfreq/*.gpu "${GPU_SYSFS_PREFIX:-/sys}"/class/misc/mali0/device/devfreq/*.mali; do
            if [ -f "$mali_cand/available_frequencies" ] && [ -f "$mali_cand/max_freq" ]; then
                [ -z "$mali_dev" ] && mali_dev="$mali_cand"
                mali_candidates="$mali_candidates $mali_cand"
            fi
        done
    fi
    if [ -z "$mali_dev" ]; then
        for mali_cand in "${GPU_SYSFS_PREFIX:-/sys}"/devices/platform/*.mali*/devfreq/* "${GPU_SYSFS_PREFIX:-/sys}"/devices/*/*.mali*/devfreq/*; do
            if [ -f "$mali_cand/available_frequencies" ] && [ -f "$mali_cand/max_freq" ]; then
                [ -z "$mali_dev" ] && mali_dev="$mali_cand"
                mali_candidates="$mali_candidates $mali_cand"
            fi
        done
    fi
    if [ -z "$mali_dev" ]; then
        for mali_cand in "$SYSFS_DEVFREQ_PREFIX"/*mali*; do
            if [ -f "$mali_cand/available_frequencies" ] && [ -f "$mali_cand/max_freq" ]; then
                [ -z "$mali_dev" ] && mali_dev="$mali_cand"
                mali_candidates="$mali_candidates $mali_cand"
            fi
        done
    fi
    if [ -z "$mali_dev" ]; then
        log_msg "SKIPPED" "$category" "Mali terdeteksi tapi node tuning devfreq tidak ditemukan (0 kandidat), skip aman"
        return 0
    fi
    # Log semua kandidat bila >1 ditemukan; pakai yang pertama.
    local _n_cand
    _n_cand=$(echo "$mali_candidates" | wc -w)
    if [ "${_n_cand:-0}" -gt 1 ] 2>/dev/null; then
        log_msg "INFO" "$category" "devfreq kandidat=$_n_cand, pakai pertama=$mali_dev semua=$mali_candidates"
    fi
    if [ "${GPU_ADRENO_SKIP:-1}" = "1" ]; then
        log_msg "SKIPPED" "$category" "Mali profile skip enabled (stock)"
        return 0
    fi
    local mali_table
    mali_table=$(alpha_safe_read "$mali_dev/available_frequencies" | tr ' ' '\n' | grep -E '^[0-9]+$')
    if [ -z "$mali_table" ]; then
        log_msg "SKIPPED" "$category" "Mali frequency table tidak terbaca"
        return 0
    fi
    local mali_hw_max
    mali_hw_max=$(printf '%s\n' "$mali_table" | sort -nr | head -n 1)
    # M3: bila defaults.conf mencatat GPU_MAX_FREQ valid dan <= tabel,
    # pakai itu sebagai acuan 100% (bawaan perangkat, bukan tabel OPP).
    if [ -n "${GPU_MAX_FREQ:-}" ]; then
        case "$GPU_MAX_FREQ" in ''|*[!0-9]*) ;;
            *)
                if [ "$GPU_MAX_FREQ" -gt 0 ] 2>/dev/null && [ "$GPU_MAX_FREQ" -le "$mali_hw_max" ] 2>/dev/null; then
                    log_msg "INFO" "$category" "M3: acuan GPU_MAX_FREQ=$GPU_MAX_FREQ (defaults.conf)"
                    mali_hw_max="$GPU_MAX_FREQ"
                fi
                ;;
        esac
    fi
    local mali_percent="${GPU_FREQ_MAX_PERCENT:-100}"
    case "$mali_percent" in
        ''|*[!0-9]*) mali_percent=100 ;;
    esac
    [ "$mali_percent" -gt 100 ] 2>/dev/null && mali_percent=100
    # Bagi dulu baru kali - GPU freq biasanya dalam Hz (ratusan juta), jadi
    # kali dulu baru bagi bisa overflow arithmetic shell dan balik jadi
    # angka negatif -> gpu_target invalid -> selalu SKIPPED walau node valid.
    local mali_target=$(( (mali_hw_max / 100) * mali_percent ))
    mali_target=$(alpha_opp_cap_pick "$mali_target" "$(printf '%s\n' "$mali_table" | sort -n)")
    if [ -z "$mali_target" ]; then
        log_msg "SKIPPED" "$category" "Mali cap target invalid"
        return 0
    fi
    if [ "$mali_percent" -ge 100 ] && gpu_thermal_is_hot 75000; then
        log_msg "SKIPPED" "$category" "thermal sedang panas, performance cap ditahan"
        return 0
    fi
    if [ "$mali_percent" -ge 100 ]; then
        log_msg "WARN" "$category" "performance cap freq=$mali_target (thermal dicek sesaat sebelum apply)"
    fi
    tune_gpu_mali_kbase
    apply_tweak "$category" "$mali_dev/max_freq" "$mali_target"
}

tune_gpu_powervr() {
    log_msg "SKIPPED" "GPU" "PowerVR terdeteksi, tuning belum didukung di versi ini"
    return 0
}

tune_gpu_xclipse() {
    log_msg "SKIPPED" "GPU" "Xclipse terdeteksi, tuning belum didukung di versi ini"
    return 0
}

tune_gpu() {
    case "${GPU_VENDOR:-UNKNOWN}" in
        ADRENO) tune_gpu_adreno ;;
        MALI) tune_gpu_mali ;;
        POWERVR) tune_gpu_powervr ;;
        XCLIPSE) tune_gpu_xclipse ;;
        *)
            log_msg "SKIPPED" "GPU" "GPU_VENDOR=${GPU_VENDOR:-UNKNOWN}, vendor tidak dikenali (cek detected.conf)"
            return 0
            ;;
    esac
}

# --- 3. TUNE KERNEL BOOST SILENCER ---
# Mengurangi spike throttling saat input touch (pola Uperf)
tune_boost_silencer() {
    local category="KERNEL_BOOST"
    # Qualcomm cpu_boost
    if [ "${BOOST_CPU_INPUT:-1}" = "0" ]; then
        apply_tweak "$category" "$SYSFS_MODULE_PREFIX/cpu_boost/parameters/input_boost_enabled" "0"
        apply_tweak "$category" "$SYSFS_MODULE_PREFIX/cpu_boost/parameters/input_boost_freq" "0"
    else
        apply_tweak "$category" "$SYSFS_MODULE_PREFIX/cpu_boost/parameters/input_boost_enabled" "0" "1"
        apply_tweak "$category" "$SYSFS_MODULE_PREFIX/cpu_boost/parameters/input_boost_freq" "0" "1"
    fi
    
    # WALT input boost
    if [ "${BOOST_WALT_INPUT:-1}" = "0" ]; then
        apply_tweak "$category" "$PROC_SYS_PREFIX/walt/input_boost/input_boost_freq" "0"
        apply_tweak "$category" "$PROC_SYS_PREFIX/walt/sched_busy_hysteresis_enable_cpus" "0"
    else
        apply_tweak "$category" "$PROC_SYS_PREFIX/walt/input_boost/input_boost_freq" "0" "1"
        apply_tweak "$category" "$PROC_SYS_PREFIX/walt/sched_busy_hysteresis_enable_cpus" "0" "1"
    fi
    
    # MediaTek FPSGO & PerfMgr touch boosts (jika MTK)
    if [ "$SOC_VENDOR" = "mtk" ]; then
        if [ "${BOOST_MTK_PERFMGR:-1}" = "0" ]; then
            apply_tweak "$category" "$SYSFS_MODULE_PREFIX/mtk_fpsgo/parameters/perfmgr_enable" "0"
            apply_tweak "$category" "$SYSFS_MODULE_PREFIX/perfmgr/parameters/perfmgr_enable" "0"
            apply_tweak "$category" "$SYSFS_MODULE_PREFIX/perfmgr_mtk/parameters/perfmgr_enable" "0"
        else
            apply_tweak "$category" "$SYSFS_MODULE_PREFIX/mtk_fpsgo/parameters/perfmgr_enable" "0" "1"
            apply_tweak "$category" "$SYSFS_MODULE_PREFIX/perfmgr/parameters/perfmgr_enable" "0" "1"
            apply_tweak "$category" "$SYSFS_MODULE_PREFIX/perfmgr_mtk/parameters/perfmgr_enable" "0" "1"
        fi
    fi
}

# --- 4. TUNE DEVFREQ BUS ---
# Unlock bandwidth bus memori DDR/LLCC/L3 dengan validasi available frequencies jika ada
tune_devfreq() {
    local category="DEVFREQ"
    local _devfreq_matched=0
    # Qualcomm bus_dcvs & generic devfreq
    for max_node in "$SYSFS_DEVFREQ_PREFIX"/*cpubw*/max_freq \
                    "$SYSFS_DEVFREQ_PREFIX"/*gpubw*/max_freq \
                    "$SYSFS_DEVFREQ_PREFIX"/*llccbw*/max_freq \
                    "$SYSFS_CPU_PREFIX"/bus_dcvs/DDR/*/max_freq \
                    "$SYSFS_CPU_PREFIX"/bus_dcvs/LLCC/*/max_freq \
                    "$SYSFS_CPU_PREFIX"/bus_dcvs/L3/*/max_freq; do
        if [ -f "$max_node" ]; then
            _devfreq_matched=$((_devfreq_matched + 1))
            local bus_dir
            bus_dir=$(dirname "$max_node")
            local avail_node="$bus_dir/available_frequencies"
            local target_freq=""

            if [ -f "$avail_node" ]; then
                local available_freqs
                available_freqs=$(alpha_safe_read "$avail_node" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n)
                local hardware_max
                hardware_max=$(printf '%s\n' "$available_freqs" | tail -n 1)
                local max_percent="${DEVFREQ_MAX_PERCENT:-100}"
                case "$max_percent" in
                    ''|*[!0-9]*) max_percent=100 ;;
                esac
                [ "$max_percent" -gt 100 ] 2>/dev/null && max_percent=100
                if [ -n "$hardware_max" ]; then
                    target_freq=$(( (hardware_max / 100) * max_percent ))
                    target_freq=$(alpha_opp_cap_pick "$target_freq" "$available_freqs")
                fi
            fi

            # Fallback ke nilai ceiling profil jika available_frequencies tidak disediakan kernel
            if [ -z "$target_freq" ]; then
                target_freq="$DEVFREQ_MAX_FREQ_VAL"
            fi

            apply_tweak "$category" "$max_node" "$target_freq"
        fi
    done
    [ "$_devfreq_matched" -eq 0 ] 2>/dev/null && \
        log_msg "SKIPPED" "$category" "0 devfreq bus node ditemukan, skip aman"
}

# --- 5. TUNE BLOCK I/O ---
# Gabungan I/O optimal dari RaiRin-AI & Uperf
tune_io() {
    local category="IO"
    for dev in $STORAGE_DEVICES; do
        local q_dir="$SYSFS_BLOCK_PREFIX/$dev/queue"
        apply_tweak "$category" "$q_dir/add_random" "$IO_ADD_RANDOM"
        apply_tweak "$category" "$q_dir/iostats" "$IO_IOSTATS"
        apply_tweak "$category" "$q_dir/nomerges" "$IO_NOMERGES"
        apply_tweak "$category" "$q_dir/read_ahead_kb" "$IO_READ_AHEAD_KB"
    done
}

# --- 6. TUNE VIRTUAL MEMORY (VM) ---
# Tweak VM standard Linux yang aman dan teruji
# M4: battery profile — swap>=stock bila zRAM aktif
tune_vm() {
    local category="VM"
    local vm_swap="$VM_SWAPPINESS"

    # M4: bila profile battery DAN zRAM aktif, pastikan swappiness >= stock
    if [ "${ACTIVE_PROFILE:-balanced}" = "battery" ] && [ -n "${VM_SWAPPINESS:-}" ]; then
        local zram_active=0
        _zram_dir="${SYSFS_BLOCK_PREFIX:-/sys/block}/zram0"
        if [ -d "$_zram_dir" ] 2>/dev/null || command -v zramctl >/dev/null 2>&1; then
            local zram_size
            zram_size=$(cat "$_zram_dir/disksize" 2>/dev/null | tr -d '[:space:]')
            case "$zram_size" in ''|*[!0-9]*) zram_size=0 ;; esac
            [ "$zram_size" -gt 0 ] 2>/dev/null && zram_active=1
        fi
        if [ "$zram_active" = "1" ] && [ -n "${VM_SWAPPINESS:-}" ]; then
            local stock_swap="${VM_SWAPPINESS:-60}"
            # defaults.conf bawaan; fallback 60 bila belum ada
            local conf_dir="${ALPHA_CONF_DIR:-/data/adb/alpha}"
            if [ -f "$conf_dir/defaults.conf" ]; then
                local stock_from_conf
                stock_from_conf=$(grep '^VM_SWAPPINESS=' "$conf_dir/defaults.conf" 2>/dev/null | cut -d= -f2)
                case "$stock_from_conf" in ''|*[!0-9]*) stock_from_conf=60 ;; esac
                stock_swap="$stock_from_conf"
            fi
            if [ "$vm_swap" -lt "$stock_swap" ] 2>/dev/null; then
                vm_swap="$stock_swap"
                log_msg "INFO" "$category" "M4: battery swap=$VM_SWAPPINESS < stock=$stock_swap, raised to $stock_swap (zRAM active)"
            fi
        fi
    fi

    apply_tweak "$category" "$PROC_SYS_PREFIX/vm/swappiness" "$vm_swap"
    apply_tweak "$category" "$PROC_SYS_PREFIX/vm/vfs_cache_pressure" "$VM_VFS_CACHE_PRESSURE"
    apply_tweak "$category" "$PROC_SYS_PREFIX/vm/dirty_ratio" "$VM_DIRTY_RATIO"
    apply_tweak "$category" "$PROC_SYS_PREFIX/vm/dirty_background_ratio" "$VM_DIRTY_BACKGROUND_RATIO"
    apply_tweak "$category" "$PROC_SYS_PREFIX/vm/stat_interval" "$VM_STAT_INTERVAL"
}

# --- 7. TUNE THERMAL ---
# Preset per profile HANYA untuk vendor yang node-nya terverifikasi writable.
# Xiaomi/HyperOS: thermal_message/cpu_limits ("cpuX safe_freq").
# Vendor lain (termasuk MTK): trip_point generic RO di kernel modern dan
# tidak ada node threshold writable yang terverifikasi publik -> skip aman.
# Tidak pernah menonaktifkan thermal protection (headroom selalu <= 100%).
tune_thermal() {
    local category="THERMAL"
    local xiaomi_limits="$SYSFS_THERMAL_PREFIX/thermal_message/cpu_limits"

    if [ "${THERMAL_PRESET_SKIP:-1}" = "1" ]; then
        log_msg "SKIPPED" "$category" "profile stock (tidak override)"
        return 0
    fi

    if [ -f "$xiaomi_limits" ] && [ "${THERMAL_SAFE_OVERRIDE:-0}" = "1" ]; then
        local percent="${THERMAL_HEADROOM_PERCENT:-90}"
        case "$percent" in
            ''|*[!0-9]*) percent=90 ;;
        esac
        [ "$percent" -gt 100 ] 2>/dev/null && percent=100
        [ "$percent" -lt 50 ] 2>/dev/null && percent=50
        for pol in $CPU_POLICIES; do
            local pol_dir="$SYSFS_CPU_PREFIX/cpufreq/$pol"
            local max_file="$pol_dir/cpuinfo_max_freq"
            if [ -f "$max_file" ]; then
                local max_freq
                max_freq=$(cat "$max_file" 2>/dev/null)
                local safe_freq
                safe_freq=$(( (max_freq / 100) * percent ))
                local cpu_idx
                cpu_idx=$(basename "$pol" | sed 's/policy//')
                apply_tweak "$category" "$xiaomi_limits" "cpu$cpu_idx $safe_freq"
            fi
        done
        return 0
    fi

    if [ ! -f "$xiaomi_limits" ]; then
        if [ "${SOC_VENDOR:-unknown}" = "mtk" ]; then
            log_msg "SKIPPED" "$category" "MTK terdeteksi tapi node threshold writable belum terverifikasi, skip aman"
        else
            log_msg "SKIPPED" "$category" "vendor ${SOC_VENDOR:-unknown}: preset thermal belum didukung, skip aman"
        fi
        return 0
    fi
    log_msg "SKIPPED" "$category" "THERMAL_SAFE_OVERRIDE=0 (default-OFF, override mati)"
    return 0
}

# --- 7b. TUNE RENDER BACKEND ---
# Preferensi manual, BUKAN bagian switch profile battery/balanced/performance.
# Dibaca dari render_backend.conf (ditulis APK), dipanggil dari
# render_manager.sh dan service.sh (re-apply saat boot).
tune_render() {
    local category="RENDER"
    local render_conf="${ALPHA_RENDER_CONF:-/data/adb/alpha/render_backend.conf}"
    local render_want=""
    [ -f "$render_conf" ] && render_want=$(tr -d '[:space:]' < "$render_conf" 2>/dev/null)
    [ -z "$render_want" ] && render_want="default"
    case "$render_want" in
        default|skiagl|skiavk) ;;
        *)
            log_msg "SKIPPED" "$category" "value tidak valid: $render_want"
            return 0
            ;;
    esac
    if [ "$render_want" = "skiavk" ]; then
        local render_api
        render_api=$(getprop ro.build.version.sdk 2>/dev/null)
        case "$render_api" in
            ''|*[!0-9]*)
                log_msg "SKIPPED" "$category" "skiavk butuh API level terbaca"
                return 0
                ;;
        esac
        if [ "$render_api" -lt 31 ] 2>/dev/null; then
            log_msg "SKIPPED" "$category" "skiavk butuh API 31+, device API=$render_api"
            return 0
        fi
        if [ "$(getprop ro.hwui.use_vulkan 2>/dev/null)" != "true" ]; then
            log_msg "SKIPPED" "$category" "device tidak expose Vulkan renderer"
            return 0
        fi
    fi
    local render_prop="debug.hwui.renderer"
    # M7: pakai setprop (bukan resetprop) untuk semua debug.* property.
    # setprop tidak bisa menghapus property secara sempurna, jadi untuk
    # nilai default: log "perlu reboot" + beri tahu aplikasi.
    if ! command -v setprop >/dev/null 2>&1; then
        log_msg "SKIPPED" "$category" "setprop tidak tersedia"
        return 0
    fi
    if [ "$render_want" = "default" ]; then
        # M7: resetprop -d diganti — setprop tidak bisa hapus debug.* prop.
        # Log bahwa reboot + restart aplikasi diperlukan.
        log_msg "INFO" "$category" "$render_prop=default → log 'perlu reboot' + restart aplikasi (setprop tidak bisa hapus prop secara sempurna)"
        echo "[M7] RENDER: $render_prop=dipulihkan ke default → perlu reboot + restart aplikasi" >> "${ALPHA_LOG_FILE:-/data/adb/alpha/alpha.log}" 2>/dev/null
        return 0
    fi
    if setprop "$render_prop" "$render_want" 2>/dev/null; then
        local render_cur
        render_cur=$(getprop "$render_prop" 2>/dev/null)
        if [ "$render_cur" = "$render_want" ]; then
            log_msg "APPLIED" "$category" "$render_prop=$render_want (efek setelah restart aplikasi)"
            return 0
        fi
        log_msg "WARN" "$category" "readback belum update: $render_cur != $render_want (efek setelah restart aplikasi)"
        return 0
    fi
    log_msg "FAILED" "$category" "setprop $render_prop=$render_want gagal"
    return 1
}

# --- 8. OPP SNAP-NEAREST (Helper untuk tuning frekuensi) ---
# Pilih frekuensi dengan selisih absolut terkecil ke target; seri → pilih
# yang LEBIH RENDAH.  Driver cpufreq sering menolak/membulatkan nilai yang
# tidak ada di tabel OPP, jadi nearest lebih aman daripada cap_pick yang
# hanya mencari <= target.
alpha_opp_snap_nearest() {
    local target="$1"
    local avail="$2"

    case "$target" in
        ''|*[!0-9]*) return 1 ;;
    esac

    local best="" best_diff=""
    for f in $avail; do
        case "$f" in
            ''|*[!0-9]*) continue ;;
        esac
        local diff
        if [ "$f" -ge "$target" ]; then
            diff=$(( f - target ))
        else
            diff=$(( target - f ))
        fi
        if [ -z "$best" ] || [ "$diff" -lt "$best_diff" ] 2>/dev/null || \
           { [ "$diff" -eq "$best_diff" ] 2>/dev/null && [ "$f" -lt "$best" ] 2>/dev/null; }; then
            best="$f"
            best_diff="$diff"
        fi
    done

    if [ -n "$best" ]; then
        printf '%s\n' "$best"
    else
        return 1
    fi
}

# --- 9. OPP CAP PICKER (Helper untuk tuning frekuensi berbasis persentase) ---
# Memilih frekuensi terdekat yang <= target dari daftar frekuensi kernel yang valid
# Murni POSIX integer arithmetic tanpa awk/bc/python
alpha_opp_cap_pick() {
    local target="$1"
    local avail="$2"
    
    case "$target" in
        ''|*[!0-9]*) return 1 ;;
    esac
    
    local best=""
    local lowest=""
    
    for f in $avail; do
        case "$f" in
            ''|*[!0-9]*) continue ;;
        esac
        
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

# --- 9. TUNE NETWORK (Adaptasi HSIN: TCP Congestion selection & TCP Fast Open) ---
# M5: respek NET_TCP_PREFERENCE — pilih HANYA dari daftar available.
# Urutan prioritas: NET_TCP_PREFERENCE → bbr (jika ada) → cubic fallback.
tune_network() {
    local category="NET"
    local tcp_node="$PROC_SYS_PREFIX/net/ipv4/tcp_congestion_control"
    local avail_node="$PROC_SYS_PREFIX/net/ipv4/tcp_available_congestion_control"
    local tfo_node="$PROC_SYS_PREFIX/net/ipv4/tcp_fastopen"
    
    # 1. Baca available congestion control
    local avail_cc=""
    if [ -f "$avail_node" ]; then
        avail_cc=$(cat "$avail_node" 2>/dev/null)
    fi

    local selected_cc=""
    # M5: pilih pertama dari NET_TCP_PREFERENCE yang ada di available list
    local _pref="${NET_TCP_PREFERENCE:-bbr cubic}"
    for _try in $_pref; do
        case " $avail_cc " in
            *" $_try "*)
                selected_cc="$_try"
                break
                ;;
        esac
    done
    
    # Fallback: bbr jika ada, lalu cubic
    if [ -z "$selected_cc" ]; then
        case " $avail_cc " in
            *" bbr "*) selected_cc="bbr" ;;
            *) selected_cc="cubic" ;;
        esac
    fi
    log_msg "INFO" "$category" "NET_TCP_PREFERENCE=$_pref available='$avail_cc' selected=$selected_cc"

    # Always use the gateway so missing/unwritable nodes are logged as SKIPPED/FAILED.
    apply_tweak "$category" "$tcp_node" "$selected_cc"
    
    # 2. Aktifkan TCP Fast Open
    apply_tweak "$category" "$tfo_node" "$NET_TCP_FASTOPEN"
}
