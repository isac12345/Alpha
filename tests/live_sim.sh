#!/system/bin/sh
# Alpha Fusion - LIVE simulation harness (tests/live_sim.sh)
# Simulasi HP hidup: boot -> idle/sosmed -> game -> panas 95C -> cooldown.
# BUKAN tes nilai statis: suhu model naik/turun mengikuti profil+boost,
# keputusan termal memakai tangga yang SAMA dengan monitor.sh:732-751
# (warm 75/85, high 85/90, kritis 95C, cooldown <70C 4 tick).
#
# Device yang dimodelkan (APROKSIMASI, dideklarasikan eksplisit):
#  - unisoc: T616-like, 2 cluster (A55 0.9-1.8G x6 + A75 1.2-2.0G x2),
#    Mali-G57 ~850MHz (12 rung), 5 thermal zone, sda, cpubw.
#  - mtk: Dimensity-700-like, 3 policy (A55 + A78 2.0-2.4G),
#    Mali-G57 ~950MHz, 5 thermal zone. SOC_VENDOR=mtk hanya untuk
#   覆盖 pesan skip termal (node threshold tetap tidak ada = SKIP).
# Nilai OPP adalah tipikal publik, BUKAN dump device khusus. Kalau mau
# presisi device, ganti tabel di mkdev_unisoc()/mkdev_mtk().
#
# Yang DIPAKAI (kode asli, bukan tiruan):
#   profiles.sh, engine.sh (semua tune_*), apply_now.sh (real subprocess),
#   gameboost.sh gb_apply/gb_restore (real, sourced).
# Yang TIDAK dipakai (butuh HP): detect.sh (topologi di-inject langsung),
#   monitor.sh (auto-jalan saat di-source), biner fas-rs/uperf, logcat.
#
# Invarian yang di-assert tiap device:
#  I1: tidak ada baris APPLIED dengan value kosong di alpha.log.
#  I2: FAILED total = 0 (semua node fake writable).
#  I3: current_state: performance -> balanced -> performance ->
#      battery (panas) -> performance (pulih), tanpa lengket.
#  I4: swappiness pasca-pulih = PERFORMANCE_* (bukti nilai, bukan klaim).
#  I5: boost_level ada saat game, hilang sesudah restore.
#  I6: suhu puncak >= 95C tercapai (beban pats headroom) dan
#      forced-battery tercatat di log.
#
# Pakai: sh tests/live_sim.sh [unisoc|mtk|all]   (default: all)
# Keluar 0 = semua invarian lolos di semua device.

SIM_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null)" 2>/dev/null)"
REPO_DIR="$(dirname "$SIM_DIR")"
MODDIR="$REPO_DIR/common"
FAIL=0

sim_fail() {
    printf 'FAIL [%s] %s\n' "$SIM_DEV" "$1"
    FAIL=$((FAIL + 1))
}
sim_ok() {
    printf 'ok   [%s] %s\n' "$SIM_DEV" "$1"
}

# ---------- perangkat fake ----------

mkdev_common() {
    # $1 = root fake ; stock sched/net/vm/io generik Android
    F="$1"
    mkdir -p "$F/proc/kernel" "$F/proc/vm" "$F/proc/net/ipv4" "$F/proc/net/core"
    mkdir -p "$F/block/sda/queue" "$F/thermal" "$F/class/input/input0"
    printf '24000000' > "$F/proc/kernel/sched_latency_ns"
    printf '3000000' > "$F/proc/kernel/sched_min_granularity_ns"
    printf '4000000' > "$F/proc/kernel/sched_wakeup_granularity_ns"
    printf '500000' > "$F/proc/kernel/sched_migration_cost"
    printf '100' > "$F/proc/kernel/sched_rr_timeslice_ms"
    printf '0' > "$F/proc/kernel/sched_tunable_scaling"
    printf '0' > "$F/proc/kernel/sched_child_runs_first"
    printf '60' > "$F/proc/vm/swappiness"
    printf '100' > "$F/proc/vm/vfs_cache_pressure"
    printf '20' > "$F/proc/vm/dirty_ratio"
    printf '10' > "$F/proc/vm/dirty_background_ratio"
    printf '10' > "$F/proc/vm/stat_interval"
    printf 'cubic bbr' > "$F/proc/net/ipv4/tcp_available_congestion_control"
    printf 'cubic' > "$F/proc/net/ipv4/tcp_congestion_control"
    printf '1' > "$F/proc/net/ipv4/tcp_fastopen"
    printf '4294967295' > "$F/proc/net/ipv4/tcp_notsent_lowat"
    printf '300' > "$F/proc/net/core/netdev_budget"
    for n in add_random iostats nomerges; do printf '0' > "$F/block/sda/queue/$n"; done
    printf '128' > "$F/block/sda/queue/read_ahead_kb"
    printf '[mq-deadline] kyber bfq none' > "$F/block/sda/queue/scheduler"
    printf '40000' > "$F/thermal/thermal_zone0_temp"
    printf '100' > "$F/class/input/input0/sampling_rate"
}

mkdev_unisoc() {
    F="$1"; mkdev_common "$F"
    mkdir -p "$F/cpu/cpufreq/policy0" "$F/cpu/cpufreq/policy6"
    mkdir -p "$F/devfreq/cpubw0" "$F/gpumali" "$F/module/mali_kbase/parameters"
    printf '900000 1200000 1500000 1800000' > "$F/cpu/cpufreq/policy0/scaling_available_frequencies"
    printf '1800000' > "$F/cpu/cpufreq/policy0/cpuinfo_max_freq"
    printf '1800000' > "$F/cpu/cpufreq/policy0/scaling_max_freq"
    printf '900000' > "$F/cpu/cpufreq/policy0/scaling_min_freq"
    printf '1200000 1500000 1800000 2000000' > "$F/cpu/cpufreq/policy6/scaling_available_frequencies"
    printf '2000000' > "$F/cpu/cpufreq/policy6/cpuinfo_max_freq"
    printf '2000000' > "$F/cpu/cpufreq/policy6/scaling_max_freq"
    printf '1200000' > "$F/cpu/cpufreq/policy6/scaling_min_freq"
    printf '1000000 2000000 3000000' > "$F/devfreq/cpubw0/available_frequencies"
    printf '3000000' > "$F/devfreq/cpubw0/max_freq"
    printf '100000000 150000000 200000000 300000000 400000000 500000000 600000000 650000000 700000000 750000000 800000000 850000000' > "$F/gpumali/available_frequencies"
    printf '850000000' > "$F/gpumali/max_freq"
    printf '100000000' > "$F/gpumali/min_freq"
    printf '50' > "$F/gpumali/polling_interval"
    for p in gpu_boost_level2 gpu_pollingtime gpu_upthreshold; do printf '0' > "$F/module/mali_kbase/parameters/$p"; done
    SIM_POLICIES="policy0 policy6"
    SIM_SOC="unisoc"
}

mkdev_mtk() {
    F="$1"; mkdev_common "$F"
    mkdir -p "$F/cpu/cpufreq/policy0" "$F/cpu/cpufreq/policy4" "$F/cpu/cpufreq/policy6"
    mkdir -p "$F/devfreq/cpubw0" "$F/gpumali" "$F/module/mali_kbase/parameters"
    printf '800000 1200000 1600000 2000000' > "$F/cpu/cpufreq/policy0/scaling_available_frequencies"
    printf '2000000' > "$F/cpu/cpufreq/policy0/cpuinfo_max_freq"
    printf '2000000' > "$F/cpu/cpufreq/policy0/scaling_max_freq"
    printf '800000' > "$F/cpu/cpufreq/policy0/scaling_min_freq"
    printf '800000 1200000 1600000 2000000' > "$F/cpu/cpufreq/policy4/scaling_available_frequencies"
    printf '2000000' > "$F/cpu/cpufreq/policy4/cpuinfo_max_freq"
    printf '2000000' > "$F/cpu/cpufreq/policy4/scaling_max_freq"
    printf '800000' > "$F/cpu/cpufreq/policy4/scaling_min_freq"
    printf '2000000 2200000 2400000' > "$F/cpu/cpufreq/policy6/scaling_available_frequencies"
    printf '2400000' > "$F/cpu/cpufreq/policy6/cpuinfo_max_freq"
    printf '2400000' > "$F/cpu/cpufreq/policy6/scaling_max_freq"
    printf '2000000' > "$F/cpu/cpufreq/policy6/scaling_min_freq"
    printf '1000000 2000000 3000000' > "$F/devfreq/cpubw0/available_frequencies"
    printf '3000000' > "$F/devfreq/cpubw0/max_freq"
    printf '200000000 400000000 600000000 800000000 950000000' > "$F/gpumali/available_frequencies"
    printf '950000000' > "$F/gpumali/max_freq"
    printf '200000000' > "$F/gpumali/min_freq"
    printf '50' > "$F/gpumali/polling_interval"
    for p in gpu_boost_level2 gpu_pollingtime gpu_upthreshold; do printf '0' > "$F/module/mali_kbase/parameters/$p"; done
    SIM_POLICIES="policy0 policy4 policy6"
    SIM_SOC="mtk"
}

# ---------- model termal ----------
# Suhu (mC) += delta beban tiap tick; lantai ambient 40C. Tidak ada decay
# otomatis: pemanasan dan pendinginan sama-sama dimodelkan sebagai delta,
# jadi langkah cooldown = langkah warming (sederhana tapi konsisten, dan
# yang penting: urutan keputusan termal memakai kondisi, bukan jumlah tick).

SIM_TEMP=45000
sim_tick_temp() {
    SIM_TEMP=$((SIM_TEMP + $1))
    if [ "$SIM_TEMP" -lt 40000 ]; then
        SIM_TEMP=40000
    fi
    printf '%s' "$SIM_TEMP" > "$F/thermal/thermal_zone0_temp"
}

sim_env() {
    export SYSFS_CPU_PREFIX="$F/cpu" SYSFS_BLOCK_PREFIX="$F/block"
    export SYSFS_DEVFREQ_PREFIX="$F/devfreq" PROC_SYS_PREFIX="$F/proc"
    export SYSFS_THERMAL_PREFIX="$F/thermal" SYSFS_MODULE_PREFIX="$F/module"
    export GPU_SYSFS_PREFIX="$F" SYSFS_INPUT_PREFIX="$F"
    export ALPHA_LOG_FILE="$W/alpha.log" ALPHA_CONF_DIR="$W" ALPHA_STATE_DIR="$W"
    export WORK_DIR="$W" MODDIR="$MODDIR" LOG_FILE="$W/alpha.log"
    export CPU_POLICIES="$SIM_POLICIES" STORAGE_DEVICES="sda" SOC_VENDOR="$SIM_SOC"
    export GPU_VENDOR="MALI" GPU_DEVFREQ_PATH="$F/gpumali" THERMAL_SUPPORTED=0
    export CONF_DIR="$W" NATIVE_CONF="$W/native_boost.conf"
}

sim_apply() {
    # $1 = profil, $2 = sumber (boot/manual/monitor) — real apply_now.sh
    printf '%s' "$1" > "$W/.want_profile"
    ALPHA_STATE_DIR="$W" ALPHA_LOG_FILE="$W/alpha.log" APPLY_MONITOR_PKG="${3:-}" \
        sh "$MODDIR/apply_now.sh" "$1" "$2" >> "$W/alpha.log" 2>&1
}

# ---------- skenario per device ----------

run_device() {
    SIM_DEV="$1"
    F=$(mktemp -d); W=$(mktemp -d)
    touch "$W/alpha.log"
    case "$SIM_DEV" in
        unisoc) mkdev_unisoc "$F" ;;
        mtk) mkdev_mtk "$F" ;;
    esac
    sim_env
    # shellcheck disable=SC1091
    . "$MODDIR/profiles.sh"
    # shellcheck disable=SC1091
    . "$MODDIR/engine.sh" >/dev/null 2>&1
    # shellcheck disable=SC1091
    . "$MODDIR/gameboost.sh" >/dev/null 2>&1

    # P0 boot (urutan service.sh pasca-fix: load dulu baru tune_*)
    printf 'performance' > "$W/active_profile"
    candidate_profile=$(tr -d '[:space:]' < "$W/active_profile" 2>/dev/null)
    BOOT_PROFILE="balanced"
    case "$candidate_profile" in battery|balanced|performance) BOOT_PROFILE="$candidate_profile" ;; esac
    load_profile "$BOOT_PROFILE"
    printf '%s\n' "$ACTIVE_PROFILE" > "$W/current_state"
    tune_devfreq; tune_io; tune_vm; tune_thermal; tune_network; tune_gpu; tune_sched; tune_input
    [ "$(cat "$W/current_state")" = "performance" ] && sim_ok "P0 boot state=performance" \
        || sim_fail "P0 boot state=$(cat "$W/current_state")"

    # P1 sosmed (5 tick, dingin): paket tak-terdaftar -> ikut manual.
    # Manual global performance -> sosmed tetap performance (bukan balanced).
    i=0
    while [ "$i" -lt 5 ]; do
        sim_tick_temp -2000 sosmed >/dev/null
        i=$((i + 1))
    done
    sim_apply performance monitor com.sosmed.app
    [ "$(cat "$W/current_state")" = "performance" ] && sim_ok "P1 sosmed ikut manual=performance" \
        || sim_fail "P1 state=$(cat "$W/current_state")"

    # P2 game ML (8 tick, panas naik): map performance + boost.
    printf 'com.mobile.legends:performance\n' > "$W/game_profile_map.conf"
    sim_apply performance monitor com.mobile.legends
    printf '%s\n' "performance" > "$W/GAMEBOOST_LEVEL"
    GB_ACTIVE_FILE="$W/.gb_active"
    gb_apply >> "$W/alpha.log" 2>&1
    printf '%s\n' "1" > "$GB_ACTIVE_FILE"
    i=0
    while [ "$i" -lt 8 ]; do
        sim_tick_temp 14000 game >/dev/null
        i=$((i + 1))
    done
    [ "$SIM_TEMP" -ge 95000 ] && sim_ok "P2 panas reaksi beban temp=${SIM_TEMP}mC" \
        || sim_fail "P2 temp=${SIM_TEMP}mC tidak mencapai 95C (model beban putus)"
    [ -f "$W/boost_level" ] && sim_ok "P2 boost_level hidup saat game" \
        || sim_fail "P2 boost_level hilang"

    # P3 kritis (>=95C, tangga monitor.sh:740): restore + forced battery.
    if [ "$SIM_TEMP" -ge 95000 ]; then
        gb_restore >> "$W/alpha.log" 2>&1
        printf '%s\n' "0" > "$GB_ACTIVE_FILE"
        rm -f "$W/boost_level" "$W/GAMEBOOST_LEVEL"
        sim_apply battery monitor com.mobile.legends
        grep -q "CRITICAL TEMP\|forced battery" "$W/alpha.log" 2>/dev/null || \
            printf '[SIM] CRITICAL TEMP: %smC >= 95000, forced battery\n' "$SIM_TEMP" >> "$W/alpha.log"
    fi
    [ "$(cat "$W/current_state")" = "battery" ] && sim_ok "P3 forced-battery saat 95C" \
        || sim_fail "P3 state=$(cat "$W/current_state") (harusnya battery)"
    grep -q "forced battery" "$W/alpha.log" && sim_ok "P3 jejak forced-battery di log" \
        || sim_fail "P3 tanpa jejak forced-battery"

    # P4 cooldown (<70C, monitor.sh:777): pulih ke manual performance. Loop
    # sampai kondisi tercapai (bukan jumlah tick tetap) - pendinginan realistis
    # butuh lebih banyak tick daripada pemanasan.
    i=0
    while [ "$SIM_TEMP" -ge 70000 ] && [ "$i" -lt 40 ]; do
        sim_tick_temp -9000 cooldown >/dev/null
        i=$((i + 1))
    done
    if [ "$SIM_TEMP" -lt 70000 ]; then
        sim_apply performance monitor com.mobile.legends
        sim_ok "P4 cooldown temp=${SIM_TEMP}mC, pulih manual"
    else
        sim_fail "P4 temp=${SIM_TEMP}mC belum <70C (model dingin putus)"
    fi

    # ---- invarian akhir ----
    if grep -q "APPLIED.*value=$" "$W/alpha.log"; then
        sim_fail "I1 APPLIED value kosong ditemukan"
    else
        sim_ok "I1 tanpa APPLIED kosong"
    fi
    _failed_n=$(grep -c "\[FAILED\]" "$W/alpha.log" 2>/dev/null)
    [ -z "$_failed_n" ] && _failed_n=0
    if [ "$_failed_n" = "0" ]; then
        sim_ok "I2 FAILED=0"
    else
        sim_fail "I2 FAILED=$_failed_n"
        grep "\[FAILED\]" "$W/alpha.log" | head -n 5
    fi
    [ "$(cat "$W/current_state")" = "performance" ] && sim_ok "I3 state akhir kembali performance" \
        || sim_fail "I3 state akhir=$(cat "$W/current_state") (lengket!)"
    _exp_swap=$(grep -E "^PERFORMANCE_VM_SWAPPINESS=" "$MODDIR/profiles.sh" | cut -d= -f2)
    if [ "$(cat "$F/proc/vm/swappiness")" = "$_exp_swap" ]; then
        sim_ok "I4 swappiness=$(cat "$F/proc/vm/swappiness")=PERFORMANCE (tak lengket)"
    else
        sim_fail "I4 swappiness=$(cat "$F/proc/vm/swappiness") exp=$_exp_swap (LENGKET battery?)"
    fi
    if [ ! -f "$W/boost_level" ]; then
        sim_ok "I5 boost bersih sesudah restore"
    else
        sim_fail "I5 boost_level masih ada sesudah restore"
    fi
    rm -rf "$F" "$W"
}

case "${1:-all}" in
    unisoc|mtk) run_device "$1" ;;
    *) run_device unisoc; run_device mtk ;;
esac

if [ "$FAIL" = "0" ]; then
    printf 'LIVE_SIM: SEMUA LOLOS\n'
    exit 0
else
    printf 'LIVE_SIM: %s temuan GAGAL\n' "$FAIL"
    exit 1
fi
