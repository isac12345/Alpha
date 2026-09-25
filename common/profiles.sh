#!/system/bin/sh
# Alpha v1 - Profile data and loader

# DAILY (label Daily, internal battery) profile: conservative clocks and
# memory, safe for all-day use. Internal name remains "battery" for
# backward compat with apply_now / current_state / active_profile files.
BATTERY_GOVERNOR_PREFERENCE="schedutil walt interactive performance"
BATTERY_CPU_FREQ_MAX_PERCENT=75
BATTERY_CPU_FREQ_MIN_PERCENT=0
BATTERY_BOOST_CPU_INPUT=1
BATTERY_BOOST_WALT_INPUT=1
BATTERY_BOOST_MTK_PERFMGR=1
BATTERY_DEVFREQ_MAX_PERCENT=70
BATTERY_IO_ADD_RANDOM=0
BATTERY_IO_IOSTATS=0
BATTERY_IO_NOMERGES=2
BATTERY_IO_READ_AHEAD_KB=128
# DAILY: VM tuned near stock (70/100/20/10) but safer swap for zRAM
BATTERY_VM_SWAPPINESS=80
BATTERY_VM_VFS_CACHE_PRESSURE=100
BATTERY_VM_DIRTY_RATIO=20
BATTERY_VM_DIRTY_BACKGROUND_RATIO=5
BATTERY_VM_STAT_INTERVAL=10
BATTERY_THERMAL_SAFE_OVERRIDE=0
BATTERY_THERMAL_HEADROOM_PERCENT=80
BATTERY_THERMAL_PRESET_SKIP=0
BATTERY_NET_TCP_FASTOPEN=1
BATTERY_NET_TCP_PREFERENCE="cubic"
BATTERY_CPU_FREQ_MIN_SKIP=1
BATTERY_GPU_ADRENO_SKIP=0
BATTERY_GPU_ADRENO_MODE="cap"
BATTERY_GPU_ADRENO_POWERLEVEL=0
BATTERY_GPU_FREQ_MAX_PERCENT=45

# Balanced profile: default compromise between latency, power and heat.
BALANCED_GOVERNOR_PREFERENCE="schedutil walt interactive performance"
BALANCED_CPU_FREQ_MAX_PERCENT=85
# Lantai ringan 30% (SKIP=0) anti-stutter sesi panjang: CPU tidak sering
# jatuh ke OPP bawah tiap frame load, tetap di bawah tier performance.
BALANCED_CPU_FREQ_MIN_PERCENT=30
BALANCED_BOOST_CPU_INPUT=0
BALANCED_BOOST_WALT_INPUT=0
BALANCED_BOOST_MTK_PERFMGR=0
BALANCED_DEVFREQ_MAX_PERCENT=85
BALANCED_IO_ADD_RANDOM=0
BALANCED_IO_IOSTATS=0
BALANCED_IO_NOMERGES=2
BALANCED_IO_READ_AHEAD_KB=128
BALANCED_VM_SWAPPINESS=60
BALANCED_VM_VFS_CACHE_PRESSURE=100
BALANCED_VM_DIRTY_RATIO=20
BALANCED_VM_DIRTY_BACKGROUND_RATIO=10
BALANCED_VM_STAT_INTERVAL=10
BALANCED_THERMAL_SAFE_OVERRIDE=0
BALANCED_THERMAL_HEADROOM_PERCENT=90
BALANCED_THERMAL_PRESET_SKIP=1
BALANCED_NET_TCP_FASTOPEN=1
BALANCED_NET_TCP_PREFERENCE="cubic"
BALANCED_CPU_FREQ_MIN_SKIP=0
BALANCED_GPU_ADRENO_SKIP=0
BALANCED_GPU_ADRENO_MODE="stock"
BALANCED_GPU_ADRENO_POWERLEVEL=0
# Balanced GPU AKTIF (SKIP=0): ceiling 85% + kbase balanced diterapkan.
# Adreno tetap stock karena MODE=stock (skip di tune_gpu_adreno), jadi
# nilai ini efektif untuk jalur Mali.
BALANCED_GPU_FREQ_MAX_PERCENT=85

# Performance profile: raw power, software thermal gate relaxed (HW protection intact).
PERFORMANCE_GOVERNOR_PREFERENCE="performance schedutil walt interactive"
PERFORMANCE_CPU_FREQ_MAX_PERCENT=100
PERFORMANCE_CPU_FREQ_MIN_PERCENT=55
PERFORMANCE_BOOST_CPU_INPUT=0
PERFORMANCE_BOOST_WALT_INPUT=0
PERFORMANCE_BOOST_MTK_PERFMGR=0
PERFORMANCE_DEVFREQ_MAX_PERCENT=100
PERFORMANCE_IO_ADD_RANDOM=0
PERFORMANCE_IO_IOSTATS=0
PERFORMANCE_IO_NOMERGES=2
PERFORMANCE_IO_READ_AHEAD_KB=256
PERFORMANCE_VM_SWAPPINESS=40
PERFORMANCE_VM_VFS_CACHE_PRESSURE=50
PERFORMANCE_VM_DIRTY_RATIO=15
PERFORMANCE_VM_DIRTY_BACKGROUND_RATIO=5
PERFORMANCE_VM_STAT_INTERVAL=10
PERFORMANCE_THERMAL_SAFE_OVERRIDE=0
PERFORMANCE_THERMAL_HEADROOM_PERCENT=95
PERFORMANCE_THERMAL_PRESET_SKIP=0
PERFORMANCE_NET_TCP_FASTOPEN=3
PERFORMANCE_NET_TCP_PREFERENCE="bbr cubic"
PERFORMANCE_CPU_FREQ_MIN_SKIP=0
PERFORMANCE_GPU_ADRENO_SKIP=0
PERFORMANCE_GPU_ADRENO_MODE="cap"
PERFORMANCE_GPU_ADRENO_POWERLEVEL=0
PERFORMANCE_GPU_FREQ_MAX_PERCENT=100

profile_warn() {
    profile_warn_message="$1"
    printf '%s\n' "[WARN] $profile_warn_message" >&2
    if [ -n "${ALPHA_LOG_FILE:-}" ] && [ -d "$(dirname "$ALPHA_LOG_FILE")" ]; then
        printf '%s\n' "[WARN] [PROFILE] $profile_warn_message" >> "$ALPHA_LOG_FILE" 2>/dev/null
    fi
}

load_profile() {
    local profile_name="$1"
    case "$profile_name" in
        battery|balanced|performance)
            ;;
        *)
            profile_warn "Profil tidak dikenali: ${profile_name:-empty}; fallback ke balanced"
            profile_name="balanced"
            ;;
    esac

    ACTIVE_PROFILE="$profile_name"
    local profile_upper
    profile_upper=$(printf '%s' "$profile_name" | tr '[:lower:]' '[:upper:]')

    GOVERNOR_PREFERENCE=$(eval "printf '%s' \"\${${profile_upper}_GOVERNOR_PREFERENCE}\"")
    CPU_FREQ_MAX_PERCENT=$(eval "printf '%s' \"\${${profile_upper}_CPU_FREQ_MAX_PERCENT}\"")
    CPU_FREQ_MIN_PERCENT=$(eval "printf '%s' \"\${${profile_upper}_CPU_FREQ_MIN_PERCENT}\"")
    BOOST_CPU_INPUT=$(eval "printf '%s' \"\${${profile_upper}_BOOST_CPU_INPUT}\"")
    BOOST_WALT_INPUT=$(eval "printf '%s' \"\${${profile_upper}_BOOST_WALT_INPUT}\"")
    BOOST_MTK_PERFMGR=$(eval "printf '%s' \"\${${profile_upper}_BOOST_MTK_PERFMGR}\"")
    DEVFREQ_MAX_PERCENT=$(eval "printf '%s' \"\${${profile_upper}_DEVFREQ_MAX_PERCENT}\"")
    IO_ADD_RANDOM=$(eval "printf '%s' \"\${${profile_upper}_IO_ADD_RANDOM}\"")
    IO_IOSTATS=$(eval "printf '%s' \"\${${profile_upper}_IO_IOSTATS}\"")
    IO_NOMERGES=$(eval "printf '%s' \"\${${profile_upper}_IO_NOMERGES}\"")
    IO_READ_AHEAD_KB=$(eval "printf '%s' \"\${${profile_upper}_IO_READ_AHEAD_KB}\"")
    VM_SWAPPINESS=$(eval "printf '%s' \"\${${profile_upper}_VM_SWAPPINESS}\"")
    VM_VFS_CACHE_PRESSURE=$(eval "printf '%s' \"\${${profile_upper}_VM_VFS_CACHE_PRESSURE}\"")
    VM_DIRTY_RATIO=$(eval "printf '%s' \"\${${profile_upper}_VM_DIRTY_RATIO}\"")
    VM_DIRTY_BACKGROUND_RATIO=$(eval "printf '%s' \"\${${profile_upper}_VM_DIRTY_BACKGROUND_RATIO}\"")
    VM_STAT_INTERVAL=$(eval "printf '%s' \"\${${profile_upper}_VM_STAT_INTERVAL}\"")
    THERMAL_SAFE_OVERRIDE=$(eval "printf '%s' \"\${${profile_upper}_THERMAL_SAFE_OVERRIDE}\"")
    THERMAL_HEADROOM_PERCENT=$(eval "printf '%s' \"\${${profile_upper}_THERMAL_HEADROOM_PERCENT}\"")
    THERMAL_PRESET_SKIP=$(eval "printf '%s' \"\${${profile_upper}_THERMAL_PRESET_SKIP}\"")
    NET_TCP_FASTOPEN=$(eval "printf '%s' \"\${${profile_upper}_NET_TCP_FASTOPEN}\"")
    NET_TCP_PREFERENCE=$(eval "printf '%s' \"\${${profile_upper}_NET_TCP_PREFERENCE}\"")
    CPU_FREQ_MIN_SKIP=$(eval "printf '%s' \"\${${profile_upper}_CPU_FREQ_MIN_SKIP}\"")
    GPU_ADRENO_SKIP=$(eval "printf '%s' \"\${${profile_upper}_GPU_ADRENO_SKIP}\"")
    GPU_ADRENO_MODE=$(eval "printf '%s' \"\${${profile_upper}_GPU_ADRENO_MODE}\"")
    GPU_ADRENO_POWERLEVEL=$(eval "printf '%s' \"\${${profile_upper}_GPU_ADRENO_POWERLEVEL}\"")
    GPU_FREQ_MAX_PERCENT=$(eval "printf '%s' \"\${${profile_upper}_GPU_FREQ_MAX_PERCENT}\"")

    # Legacy ceiling remains available until engine devfreq becomes percentage-based.
    DEVFREQ_MAX_FREQ_VAL=9999000000
}
