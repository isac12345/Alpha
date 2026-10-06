#!/system/bin/sh
# Alpha v1 - Screen-aware foreground profile monitor

MODDIR="${0%/*}"
STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
PID_FILE="$STATE_DIR/monitor.pid"
MAP_FILE="$STATE_DIR/game_profile_map.conf"
ACTIVE_PROFILE_FILE="$STATE_DIR/active_profile"
CURRENT_STATE_FILE="$STATE_DIR/current_state"
LOG_FILE="${ALPHA_LOG_FILE:-$STATE_DIR/alpha.log}"
# Hemat CPU: saat game aktif dan prosesnya masih hidup, dumpsys (layar + app depan) hanya
# dijalankan penuh tiap FG_FULLCHK_SECS detik; di antaranya cukup pidof (murah).
FG_FULLCHK_SECS="${ALPHA_FG_FULLCHK_SECS:-12}"
case "$FG_FULLCHK_SECS" in ''|*[!0-9]*) FG_FULLCHK_SECS=12 ;; esac
monitor_fg_cache_pkg=""
monitor_fg_cache_ts=0
SCREEN_ON_INTERVAL="${ALPHA_SCREEN_ON_INTERVAL:-7}"
SCREEN_OFF_INTERVAL="${ALPHA_SCREEN_OFF_INTERVAL:-60}"
GAME_POLL_INTERVAL_SECS="${ALPHA_GAME_POLL_INTERVAL_SECS:-4}"
case "$GAME_POLL_INTERVAL_SECS" in
    ''|*[!0-9]*) GAME_POLL_INTERVAL_SECS="$SCREEN_ON_INTERVAL" ;;
    *) [ "$GAME_POLL_INTERVAL_SECS" -gt 0 ] 2>/dev/null || GAME_POLL_INTERVAL_SECS="$SCREEN_ON_INTERVAL" ;;
esac
MAX_CYCLES="${ALPHA_MONITOR_MAX_CYCLES:-0}"
# Health-check event stream: kalau layar sudah nyala selama
# EVENT_HEALTH_SECS tapi NOL event ter-parse jadi package, filter event
# dianggap tidak cocok dengan ROM ini -> turun ke polling permanen
# untuk sisa proses (satu keputusan per boot, hemat resource).
EVENT_HEALTH_SECS="${ALPHA_EVENT_HEALTH_SECS:-45}"
EVENT_PRECHECK_LINES="${ALPHA_EVENT_PRECHECK_LINES:-100}"
EVENT_COUNT_FILE="$STATE_DIR/.foreground-events.$$.count"
EVENT_ON_SECS=0
EVENT_FALLBACK_DONE=0
EVENT_HEALTH_LOGGED=0
# Satu sumber tag untuk reader dan pre-check. Separator koma menjaga
# tiap token bisa dipakai sebagai glob `case` sekaligus ERE `grep -E`.
EVENT_TAG_PATTERN='wm_set_resumed_activity,wm_set_top_resumed_activity,wm_top_resumed,wm_resume_activity,wm_on_resume_called,wm_on_top_resumed_called,am_focused_activity,am_on_resume_called,minimalResumeActivityLocked,Focus[ ]entering'
# MAX_CYCLES hanya berlaku di mode polling fallback (run_polling_loop).
# Di mode event-driven variabel ini DIABAIKAN; untuk menghentikan monitor
# saat testing mode event-driven, pakai kill <pid> langsung (trap akan
# membersihkan stream logcat/reader lewat stop_event_stream).
STOP_MONITOR=0
NOTIFY_MODE_SWITCH="${ALPHA_NOTIFY_MODE_SWITCH:-1}"
NOTIFY_TAG="alpha_mode_switch"
NOTIFY_AVAILABLE=0
MONITOR_METHOD="polling"
LOGCAT_PID=""
READER_PID=""
EVENT_FIFO=""
LAST_EVENT_PKG_FILE="$STATE_DIR/.foreground_last_pkg"
HUD_FOREGROUND_FILE="$STATE_DIR/.hud_foreground_pkg"

# GameBoost integration
GB_GRACE="${ALPHA_GB_GRACE:-12}"
GB_PENDING_FILE="$STATE_DIR/.gb_pending"
GB_ACTIVE_FILE="$STATE_DIR/.gb_active"
GB_SAFETY_INTERVAL=15
GB_SAFETY_LAST=0
GB_FORCED_LEVEL=""
# Level boost karena batas baterai 15-30% (flag GB_WARN_BOOST). Terpisah dari
# GB_FORCED_LEVEL (termal) supaya cabang cooldown termal tidak menyentuhnya.
GB_BATT_LEVEL=""
GB_COOLDOWN_SECS=60

# GAME-SNAPSHOT: 1x per sesi game, GAME_SNAP_AFTER_SECS detik sejak game
# jadi foreground. Murni baca + log (nol perubahan perilaku).
GAME_T0_FILE="$STATE_DIR/.game_t0"
GAME_SNAP_DONE_FILE="$STATE_DIR/.game_snap_done"
GAME_SNAP_AFTER_SECS=60
# Snapshot berulang tiap N dtk selama game foreground (visibilitas sesi panjang:
# tren suhu, step-down termal, frekuensi, mode fas-rs). 0 = hanya sekali.
GAME_SNAP_EVERY_SECS="${ALPHA_GAME_SNAP_EVERY_SECS:-300}"
case "$GAME_SNAP_EVERY_SECS" in ''|*[!0-9]*) GAME_SNAP_EVERY_SECS=300 ;; esac

# Kadensi loop: default 2 dtk (perilaku lama). Override: env ALPHA_EVENT_LOOP_SECS
# atau file $STATE_DIR/MONITOR_LOOP_SECS (angka 1-8, dibaca tiap putaran).
# Maks 8 supaya cek termal tiap 15 dtk tidak melambat jauh (termal tetap menang).
EVENT_LOOP_SECS_DEFAULT="${ALPHA_EVENT_LOOP_SECS:-2}"
case "$EVENT_LOOP_SECS_DEFAULT" in ''|*[!0-9]*) EVENT_LOOP_SECS_DEFAULT=2 ;; esac
[ "$EVENT_LOOP_SECS_DEFAULT" -ge 1 ] 2>/dev/null || EVENT_LOOP_SECS_DEFAULT=2
[ "$EVENT_LOOP_SECS_DEFAULT" -le 8 ] 2>/dev/null || EVENT_LOOP_SECS_DEFAULT=8
MONITOR_LOOP_FILE="$STATE_DIR/MONITOR_LOOP_SECS"
MONITOR_LOOP_OVR=""
GB_COOLDOWN_COUNT_FILE="$STATE_DIR/.gb_cooldown_count"

# DAILY anti-lag guard: loadavg threshold tracking
DAILY_LOADHIGH_FILE="$STATE_DIR/.daily_loadhigh_count"
DAILY_LOADBAL_FILE="$STATE_DIR/.daily_loadbalanced"

monitor_log() {
    monitor_log_status="$1"
    monitor_log_message="$2"
    monitor_log_time=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    printf '%s\n' "[$monitor_log_time] [MONITOR] [$monitor_log_status] $monitor_log_message" >> "$LOG_FILE" 2>/dev/null
}

# Source gameboost.sh for gb_apply/gb_restore/gb_safety_check functions.
# MODDIR = common/ (this script's directory), so gameboost.sh is a sibling.
_gb_monitor_save_log="$LOG_FILE"
if [ -f "$MODDIR/gameboost.sh" ]; then
    . "$MODDIR/gameboost.sh" 2>/dev/null
else
    monitor_log "GAMEBOOST" "WARN: gameboost.sh not found at $MODDIR/gameboost.sh, gb_apply/gb_restore unavailable"
fi
# Restore monitor.sh LOG_FILE (gameboost.sh redefines it).
LOG_FILE="$_gb_monitor_save_log"
# CPU_POLICIES untuk gb_apply: service.sh tidak mengekspornya ke proses
# ini; tanpa ini lantai CPU diam-diam skip (for kosong, tanpa log).
# detected.conf murni assignment (dari detect.sh sendiri) jadi aman.
if [ -z "$CPU_POLICIES" ] && [ -f "${ALPHA_CONF_DIR:-/data/adb/alpha}/detected.conf" ]; then
    . "${ALPHA_CONF_DIR:-/data/adb/alpha}/detected.conf" 2>/dev/null
    LOG_FILE="$_gb_monitor_save_log"
fi
if [ -z "$CPU_POLICIES" ]; then
    for _gb_pol_dir in "${SYSFS_CPU_PREFIX:-/sys/devices/system/cpu}"/cpufreq/policy*; do
        [ -d "$_gb_pol_dir" ] || continue
        CPU_POLICIES="$CPU_POLICIES ${_gb_pol_dir##*/}"
    done
    CPU_POLICIES=$(printf '%s' "$CPU_POLICIES" | sed 's/^ *//;s/  */ /g;s/ *$//')
    unset _gb_pol_dir
fi
export CPU_POLICIES
unset _gb_monitor_save_log
monitor_log "GAMEBOOST" "INIT CPU_POLICIES=$CPU_POLICIES"

monitor_cleanup() {
    if [ -f "$PID_FILE" ] && [ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ]; then
        rm -f "$PID_FILE"
    fi
    stop_event_stream
    STOP_MONITOR=1
}

trap monitor_cleanup TERM INT HUP
trap monitor_cleanup EXIT

mkdir -p "$STATE_DIR" 2>/dev/null || exit 1

if [ -f "$PID_FILE" ]; then
    monitor_existing_pid=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null)
    if [ -n "$monitor_existing_pid" ] && [ "$monitor_existing_pid" != "$$" ] &&
       [ -r "/proc/$monitor_existing_pid/cmdline" ]; then
        monitor_existing_cmd=$(tr '\000' ' ' < "/proc/$monitor_existing_pid/cmdline" 2>/dev/null)
        case "$monitor_existing_cmd" in
            *monitor.sh*)
                monitor_log "SKIPPED" "monitor already running pid=$monitor_existing_pid"
                exit 0
                ;;
        esac
    fi
    rm -f "$PID_FILE"
fi

rm -f "$STATE_DIR/.foreground-events."*.fifo 2>/dev/null
rm -f "$STATE_DIR/.foreground-events."*.count 2>/dev/null
rm -f "$LAST_EVENT_PKG_FILE" 2>/dev/null

printf '%s\n' "$$" > "$PID_FILE" || exit 1
monitor_log "START" "monitor pid=$$ interval_on=${SCREEN_ON_INTERVAL}s interval_off=${SCREEN_OFF_INTERVAL}s"

run_dumpsys() {
    monitor_dump_file="$STATE_DIR/.monitor-dumpsys.$$"
    if command -v timeout >/dev/null 2>&1; then
        timeout 5 dumpsys "$@" > "$monitor_dump_file" 2>/dev/null
    else
        dumpsys "$@" > "$monitor_dump_file" 2>/dev/null
    fi
    monitor_dump_rc=$?
    if [ "$monitor_dump_rc" -ne 0 ] || [ ! -s "$monitor_dump_file" ]; then
        rm -f "$monitor_dump_file"
        return 1
    fi
    return 0
}

get_screen_state() {
    if ! run_dumpsys power; then
        return 1
    fi

    if grep -qiE 'mWakefulness[=:][[:space:]]*Awake|Wakefulness[=:][[:space:]]*Awake' "$monitor_dump_file"; then
        rm -f "$monitor_dump_file"
        printf '%s\n' ON
        return 0
    fi

    rm -f "$monitor_dump_file"
    printf '%s\n' OFF
    return 0
}

get_foreground_package() {
    if run_dumpsys activity activities; then
        monitor_foreground_package=$(sed -n -E 's/.*mResumedActivity:.* ([A-Za-z0-9_]+\.[A-Za-z0-9_.]+)\/.*$/\1/p; s/.*ResumedActivity:.* ([A-Za-z0-9_]+\.[A-Za-z0-9_.]+)\/.*$/\1/p; s/.*topResumedActivity=ActivityRecord\{[^ ]+ u[0-9]+ ([A-Za-z0-9_]+\.[A-Za-z0-9_.]+)\/.*$/\1/p' "$monitor_dump_file" | tail -n 1)
        rm -f "$monitor_dump_file"
        if [ -n "$monitor_foreground_package" ]; then
            printf '%s\n' "$monitor_foreground_package"
            return 0
        fi
    fi

    if run_dumpsys window windows; then
        monitor_foreground_package=$(sed -n -E 's/.*mCurrentFocus=Window\{[^ ]+ u[0-9]+ ([A-Za-z0-9_]+\.[A-Za-z0-9_.]+)\/.*$/\1/p; s/.*mFocusedApp=.* ([A-Za-z0-9_]+\.[A-Za-z0-9_.]+)\/.*$/\1/p' "$monitor_dump_file" | tail -n 1)
        rm -f "$monitor_dump_file"
        if [ -n "$monitor_foreground_package" ]; then
            printf '%s\n' "$monitor_foreground_package"
            return 0
        fi
    fi

    rm -f "$monitor_dump_file"
    if [ "${ALPHA_DEBUG_MONITOR:-0}" = "1" ]; then
        monitor_log "DEBUG" "gagal ekstrak foreground pkg, raw dump 5 baris pertama tersimpan"
        head -n 5 "$monitor_dump_file" >> "$LOG_FILE" 2>/dev/null
    fi
    return 1
}

get_manual_profile() {
    monitor_manual_profile="balanced"
    if [ -f "$ACTIVE_PROFILE_FILE" ]; then
        monitor_manual_candidate=$(tr -d '[:space:]' < "$ACTIVE_PROFILE_FILE" 2>/dev/null)
        case "$monitor_manual_candidate" in
            battery|balanced|performance) monitor_manual_profile="$monitor_manual_candidate" ;;
        esac
    fi
    printf '%s\n' "$monitor_manual_profile"
}

get_game_profile() {
    monitor_lookup_package="$1"
    monitor_lookup_profile=""
    [ -f "$MAP_FILE" ] || return 1

    while IFS= read -r monitor_map_line || [ -n "$monitor_map_line" ]; do
        # Trim spasi depan/belakang TANPA fork (sebelumnya printf|sed per baris,
        # tiap panggilan = puluhan subproses). Hasil identik dengan sed [[:space:]].
        while :; do
            case "$monitor_map_line" in [[:space:]]*) monitor_map_line=${monitor_map_line#?} ;; *) break ;; esac
        done
        while :; do
            case "$monitor_map_line" in *[[:space:]]) monitor_map_line=${monitor_map_line%?} ;; *) break ;; esac
        done
        case "$monitor_map_line" in ''|'#'*) continue ;; esac
        monitor_map_package=${monitor_map_line%%:*}
        monitor_map_profile=${monitor_map_line#*:}
        case "$monitor_map_package" in
            ''|*[!A-Za-z0-9._]*) continue ;;
        esac
        case "$monitor_map_profile" in
            battery|balanced|performance) ;;
            *) continue ;;
        esac
        if [ "$monitor_map_package" = "$monitor_lookup_package" ]; then
            monitor_lookup_profile="$monitor_map_profile"
        fi
    done < "$MAP_FILE"

    [ -n "$monitor_lookup_profile" ] && printf '%s\n' "$monitor_lookup_profile"
}

check_notify_available() {
    NOTIFY_AVAILABLE=0
    command -v cmd >/dev/null 2>&1 || return 0
    if cmd -l 2>/dev/null | grep -qw notification; then
        NOTIFY_AVAILABLE=1
    fi
    return 0
}

# Check if package is transient (should be ignored)
is_transient_package() {
    local pkg="$1"
    case "$pkg" in
        com.android.systemui) return 0 ;;
        *inputmethod*) return 0 ;;
        com.alphabubble) return 0 ;;
        *permissioncontroller*) return 0 ;;
    esac
    return 1
}

# GameBoost safety check function (b23: timeout + range filter)
# Zona yang punya trip point "critical" = zona yang KERNEL sendiri pantau dan
# matikan sistem bila terlampaui, jadi bacaan tingginya sah (tidak pernah dibuang
# sebagai outlier). Zona tanpa trip (mis. pa-thmzone) harus lolos korroborasi.
_gb_zone_has_critical_trip() {
    local _t
    for _t in "$1"/trip_point_*_type; do
        [ -f "$_t" ] || continue
        monitor_rd "$_t" && [ "$MONITOR_RD" = "critical" ] && return 0
    done
    return 1
}

# THERMAL-USER: ambang suhu bisa diatur dari aplikasi Alpha Control lewat
# file $STATE_DIR/THERMAL_WARM_C (60-90, derajat C; default 75) dan sakelar
# $STATE_DIR/THERMAL_GUARD_OFF (matikan step-down warm/high). Batas KRITIS 95C
# TIDAK bisa digeser atau dimatikan. Default (tanpa file) = perilaku lama:
# warm 75 / high 85, profil manual performance 85/90, lepas di 70.
thermal_user_thr() {
    TH_BASE_WARM=75000
    if [ -f "$STATE_DIR/THERMAL_WARM_C" ]; then
        _tw=$(tr -cd '0-9' < "$STATE_DIR/THERMAL_WARM_C" 2>/dev/null)
        case "$_tw" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$_tw" -ge 60 ] 2>/dev/null && [ "$_tw" -le 90 ] 2>/dev/null; then
                    TH_BASE_WARM=$((_tw * 1000))
                fi
                ;;
        esac
    fi
    TH_REL=$((TH_BASE_WARM - 5000))
    TH_GUARD_OFF=0
    [ -f "$STATE_DIR/THERMAL_GUARD_OFF" ] && TH_GUARD_OFF=1
}

gb_safety_check() {
    local current_temp=0
    local max_temp=0
    local valid_count=0
    local kept="" kept_z="" kept_n=0 kept_i kept_zn median="" drop_list=""
    local zbase="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
    # Gerbang outlier = ambang KRITIS milik modul sendiri (95000): zona di bawah
    # ini tidak bisa memicu kill-boost-kritis, jadi tidak perlu dibuang; zona di
    # atasnya HARUS lolos korroborasi. (110000/105000 membiarkan bacaan palsu
    # 95-110C, mis. zona konstan 100C di Poco, tetap memicu CRITICAL.)
    # Gerbang hanya bisa di-override lewat FILE $STATE_DIR/GB_OUTLIER_MIN_MC
    # (isi: angka mC). Env ALPHA_GB_OUTLIER_MIN_MC sengaja DIBUANG (v46):
    # env tidak pernah sampai ke proses monitor di device (dijalankan dari
    # service.sh), dan knob yang sama sudah ada lewat file — jadi env cuma
    # entry mati yang menyesatkan (user set env, tidak ada efek, tidak tahu).
    local outlier_min=95000
    if [ -f "${STATE_DIR:-/data/adb/alpha}/GB_OUTLIER_MIN_MC" ] && \
        monitor_rd "${STATE_DIR:-/data/adb/alpha}/GB_OUTLIER_MIN_MC"; then
        outlier_min="$MONITOR_RD"
    fi
    case "$outlier_min" in ''|*[!0-9]*) outlier_min=95000 ;; esac
    # Override hanya boleh MELONGGARKAN filter (naikkan gerbang). Menurunkannya di
    # bawah ambang kritis modul bisa membuang panas asli (zona >median+25C) dan
    # melemahkan proteksi termal; flag user tidak boleh melakukan itu.
    [ "$outlier_min" -ge 95000 ] 2>/dev/null || outlier_min=95000
    [ "$outlier_min" -le 150000 ] 2>/dev/null || outlier_min=150000

    # Read thermal zones
    if [ -d "$zbase" ]; then
        for zone in "$zbase"/thermal_zone*; do
            [ -r "$zone/temp" ] || continue
            local temp_val
            # b23: timeout 2s per zone to prevent hang on unresponsive sysfs
            if command -v timeout >/dev/null 2>&1; then
                temp_val=$(timeout 2 cat "$zone/temp" 2>/dev/null | tr -d '[:space:]')
            else
                temp_val=$(tr -d '[:space:]' < "$zone/temp" 2>/dev/null)
            fi
            # Validate numeric (empty/non-numeric → skip)
            case "$temp_val" in
                ''|*[!0-9-]*) continue ;;
            esac
            # Convert to milliC: if |val| <= 1000 assume °C, multiply by 1000
            if [ "${temp_val#-}" -le 1000 ] 2>/dev/null; then
                current_temp=$((temp_val * 1000))
            else
                current_temp=$temp_val
            fi
            # Filter kasar: buang nilai yang secara fisik mustahil. Batas bawah
            # -20000 mC (bukan -50000): sensor termal tidak pernah -20C di HP
            # yang menyala, nilai seperti -39742 = node rusak (P6: tanpa state).
            [ "$current_temp" -ge -20000 ] 2>/dev/null && \
                [ "$current_temp" -le 150000 ] 2>/dev/null || continue
            kept="$kept $current_temp"
            kept_z="$kept_z ${zone##*/}"
            kept_n=$((kept_n + 1))
            valid_count=$((valid_count + 1))
        done
    fi

    if [ "$kept_n" -ge 2 ] 2>/dev/null; then
        # Median (bawah) murni shell: nilai terkecil yang punya >= (n+1)/2
        # nilai <= dirinya. Tanpa sort/awk: kalau awk tidak ada di PATH,
        # median jatuh ke 0 dan SEMUA zona >outlier_min (panas merata
        # asli) ikut dibuang -> max=0 dilaporkan "dingin" = gagal ke
        # arah berbahaya. Zona yang punya trip "critical" = zona yang
        # kernel sendiri matikan sistem bila terlampaui, jadi bacaan
        # tingginya sah (tidak pernah dibuang).
        local mc_a mc_b mc_c mc_t=$(((kept_n + 1) / 2))
        for mc_a in $kept; do
            mc_c=0
            for mc_b in $kept; do
                [ "$mc_b" -le "$mc_a" ] 2>/dev/null && mc_c=$((mc_c + 1))
            done
            if [ "$mc_c" -ge "$mc_t" ] 2>/dev/null; then
                if [ -z "$median" ] || [ "$mc_a" -lt "$median" ] 2>/dev/null; then
                    median=$mc_a
                fi
            fi
        done
    fi

    if [ -n "$median" ]; then
        # Outlier = >outlier_min DAN >median+25000 DAN zona tanpa trip critical.
        # Elemen median tidak mungkin terbuang, jadi max_temp >= median.
        set -- $kept_z
        for kept_i in $kept; do
            kept_zn="$1"; shift
            if [ "$kept_i" -gt "$outlier_min" ] 2>/dev/null && \
               [ "$((kept_i - median))" -gt 25000 ] 2>/dev/null && \
               ! _gb_zone_has_critical_trip "$zbase/$kept_zn"; then
                monitor_rd "$zbase/$kept_zn/type"
                drop_list="$drop_list ${MONITOR_RD:-$kept_zn}=$kept_i"
                continue
            fi
            [ "$kept_i" -gt "$max_temp" ] 2>/dev/null && max_temp=$kept_i
        done
        if [ -n "$drop_list" ]; then
            monitor_log "GAMEBOOST" "SENSOR-FAULT: dibuang (>${outlier_min} dan >median+25000, median=${median}mC, tanpa trip critical):${drop_list} ; max sah=${max_temp}mC"
        fi
    elif [ "$kept_n" -eq 1 ] 2>/dev/null; then
        for kept_i in $kept; do max_temp=$kept_i; done
    fi

    # No valid thermal zones: warm sentinel memilih performance, bukan 0
    # (yang akan terlihat sebagai extreme). Sensor valid <70C tetap
    # diperlukan untuk cooldown/unforce.
    if [ "$valid_count" -eq 0 ]; then
        monitor_log "GAMEBOOST" "UNKNOWN: thermal sensor-absen/invalid; forcing performance (sentinel=75000mC)"
        echo "75000"
        return 0
    fi

    echo "$max_temp"
    return 0
}

# Check battery status
check_battery_status() {
    local capacity=0
    local status=""
    local capacity_file="${SYSFS_POWER_PREFIX:-/sys/class/power_supply}/battery/capacity"
    local status_file="${SYSFS_POWER_PREFIX:-/sys/class/power_supply}/battery/status"
    
    # Check if files exist
    if [ ! -r "$capacity_file" ] || [ ! -r "$status_file" ]; then
        echo "OK"
        return 0
    fi
    
    capacity=$(tr -d '[:space:]' < "$capacity_file" 2>/dev/null)
    status=$(tr -d '[:space:]' < "$status_file" 2>/dev/null)
    
    # Skip if invalid
    case "$capacity" in ''|*[!0-9]*) echo "OK"; return 0 ;; esac
    
    # Battery critical (<15%) without charging — reject boost
    if [ "$capacity" -lt 15 ] 2>/dev/null && [ "$status" != "Charging" ]; then
        echo "LOW"
        return 0
    fi
    
    # Battery low (<30%) without charging — force performance-level boost
    if [ "$capacity" -lt 30 ] 2>/dev/null && [ "$status" != "Charging" ]; then
        echo "WARNING"
        return 0
    fi
    
    echo "OK"
    return 0
}

notify_mode_change() {
    notify_pkg="$1"
    notify_profile="$2"
    [ "$NOTIFY_MODE_SWITCH" = "1" ] || return 0
    [ "$NOTIFY_AVAILABLE" = "1" ] || return 0
    if [ -n "$notify_pkg" ]; then
        notify_title="Alpha: $notify_profile"
        notify_text="$notify_pkg aktif - profile $notify_profile"
    else
        notify_title="Alpha: $notify_profile"
        notify_text="Keluar dari game - kembali ke manual ($notify_profile)"
    fi
    if cmd notification post -S bigtext -t "$notify_title" "$NOTIFY_TAG" "$notify_text" >/dev/null 2>&1; then
        return 0
    fi
    monitor_log "WARNING" "notification failed tag=$NOTIFY_TAG profile=$notify_profile"
    return 0
}

stop_event_stream() {
    if [ -n "$READER_PID" ]; then
        kill "$READER_PID" 2>/dev/null
        READER_PID=""
    fi
    if [ -n "$LOGCAT_PID" ]; then
        kill "$LOGCAT_PID" 2>/dev/null
        LOGCAT_PID=""
    fi
    if [ -n "$EVENT_FIFO" ]; then
        rm -f "$EVENT_FIFO" 2>/dev/null
        EVENT_FIFO=""
    fi
    rm -f "$EVENT_COUNT_FILE" 2>/dev/null
    return 0
}

event_count_inc() {
    event_c=$(tr -cd '0-9' < "$EVENT_COUNT_FILE" 2>/dev/null)
    [ -z "$event_c" ] && event_c=0
    printf '%s' "$((event_c + 1))" > "$EVENT_COUNT_FILE" 2>/dev/null
    return 0
}

event_count_get() {
    tr -cd '0-9' < "$EVENT_COUNT_FILE" 2>/dev/null
    return 0
}

event_line_package() {
    printf '%s' "$1" | sed -n 's/.*[^A-Za-z0-9_.]\([A-Za-z0-9_][A-Za-z0-9_.]*\)\/.*/\1/p' | head -n 1
}

handle_foreground_event() {
    handle_pkg="$1"
    handle_source="$2"
    [ -n "$handle_pkg" ] || return 0
    case "$handle_pkg" in
        ''|*[!A-Za-z0-9._]*) return 0 ;;
    esac
    case "$handle_pkg" in
        *.*) ;;
        *) return 0 ;;
    esac
    
    # Skip transient packages
    if is_transient_package "$handle_pkg"; then
        return 0
    fi
    
    handle_last=""
    [ -f "$LAST_EVENT_PKG_FILE" ] && handle_last=$(cat "$LAST_EVENT_PKG_FILE" 2>/dev/null)
    [ "$handle_pkg" = "$handle_last" ] && return 0
    printf '%s' "$handle_pkg" > "$LAST_EVENT_PKG_FILE" 2>/dev/null
    printf '%s' "$handle_pkg" > "$HUD_FOREGROUND_FILE" 2>/dev/null
    handle_target=$(get_game_profile "$handle_pkg")
    if [ -z "$handle_target" ]; then
        handle_target=$(get_manual_profile)
    fi
    handle_current=""
    [ -f "$CURRENT_STATE_FILE" ] && handle_current=$(tr -d '[:space:]' < "$CURRENT_STATE_FILE" 2>/dev/null)
    
    # DAILY GAME PROMOTE: when manual profile is battery and a registered
    # game is detected, temporarily promote to balanced so the game runs
    # smoothly. After grace period (GB_GRACE), return to battery.
    local gb_active=0
    [ -f "$GB_ACTIVE_FILE" ] && gb_active=$(cat "$GB_ACTIVE_FILE" 2>/dev/null)

    local game_promote=0
    local _mapped_prof=""
    _mapped_prof=$(get_game_profile "$handle_pkg")
    if [ -n "$_mapped_prof" ] && [ "$_mapped_prof" != "performance" ] && [ "$handle_current" = "battery" ]; then
        game_promote=1
        handle_target="balanced"
        monitor_log "GAMEBOOST" "DAILY GAME PROMOTE: $handle_pkg detected in Daily mode, promoting to balanced"
    fi

    # Check if current package is a game with performance profile
    local is_game_perf=0
    if [ -n "$(get_game_profile "$handle_pkg")" ] && [ "$handle_target" = "performance" ]; then
        is_game_perf=1
    fi
    
    # GameBoost logic (rasa v20: extreme untuk game, performance = tangga mild panas)
    if [ "$is_game_perf" -eq 1 ]; then
        # Game with performance profile detected
        if [ ! -f "$GAME_T0_FILE" ]; then
            monitor_uptime
            printf '%s %s\n' "${MONITOR_UP:-0}" "$handle_pkg" > "$GAME_T0_FILE" 2>/dev/null
            rm -f "$GAME_SNAP_DONE_FILE" 2>/dev/null
        fi
        if [ "$gb_active" != "1" ]; then
            # Check DISABLE_GAMEBOOST gate
            if [ -f "${ALPHA_CONF_DIR:-/data/adb/alpha}/DISABLE_GAMEBOOST" ]; then
                monitor_log "GAMEBOOST" "DISABLED by DISABLE_GAMEBOOST file"
            else
                # Check battery status
                local battery_status
                battery_status=$(check_battery_status)
                # 15-30% tanpa charging: sebelumnya cabang ini HANYA log tanpa
                # gb_apply (log bilang "forcing" tapi tidak ada efek). Sekarang
                # eksplisit: default SKIP (jujur), atau boost level performance
                # bila flag GB_WARN_BOOST ada (A/B tanpa reflash). Level lewat
                # GB_BATT_LEVEL (global), BUKAN GB_FORCED_LEVEL, supaya cabang cooldown
                # termal (unforce -> gb_apply level default balanced) tidak
                # menganggapnya forced dan mematikan boost setelah 60 dtk.
                GB_BATT_LEVEL=""
                if [ "$battery_status" = "WARNING" ] && \
                    [ -f "${ALPHA_CONF_DIR:-/data/adb/alpha}/GB_WARN_BOOST" ]; then
                    GB_BATT_LEVEL="performance"
                    battery_status="OK"
                    monitor_log "GAMEBOOST" "BATTERY WARNING: <30% without charging, flag GB_WARN_BOOST -> boost level performance"
                fi
                if [ "$battery_status" = "LOW" ]; then
                    monitor_log "GAMEBOOST" "SKIPPED: battery <15% without charging"
                elif [ "$battery_status" = "WARNING" ]; then
                    monitor_log "GAMEBOOST" "SKIPPED: battery <30% without charging (touch GB_WARN_BOOST untuk boost level performance)"
                else
                    # Run safety check before apply
                    local current_temp
                    current_temp=$(gb_safety_check)
                    # Tangga termal sadar profil manual: profil performance
                    # digeser (warm 85 / high 90) supaya raw power
                    # bertahan; balanced/battery tetap 75/85. Batas kritis
                    # 95C (forced battery) TIDAK pernah bergeser.
                    local gb_warm_thr=75000 gb_high_thr=85000 gb_manual_prof
                    gb_manual_prof=$(get_manual_profile)
                    thermal_user_thr
                    gb_warm_thr=$TH_BASE_WARM
                    gb_high_thr=$((TH_BASE_WARM + 10000))
                    if [ "$gb_manual_prof" = "performance" ]; then
                        gb_warm_thr=$((TH_BASE_WARM + 10000))
                        gb_high_thr=$((TH_BASE_WARM + 15000))
                    fi
                    if [ "$TH_GUARD_OFF" = "1" ]; then
                        gb_warm_thr=200000
                        gb_high_thr=200000
                    fi
                    if [ "$current_temp" -ge 95000 ] 2>/dev/null; then
                        monitor_log "GAMEBOOST" "SKIPPED: temp ${current_temp}mC >= 95000, critical (manual=${gb_manual_prof})"
                    elif [ "$current_temp" -ge "$gb_high_thr" ] 2>/dev/null; then
                        monitor_log "GAMEBOOST" "TEMP WARNING: ${current_temp}mC >= ${gb_high_thr}, forcing balanced (manual=${gb_manual_prof})"
                        GB_FORCED_LEVEL="balanced"
                    elif [ "$current_temp" -ge "$gb_warm_thr" ] 2>/dev/null; then
                        monitor_log "GAMEBOOST" "TEMP WARNING: ${current_temp}mC >= ${gb_warm_thr}, forcing performance (manual=${gb_manual_prof})"
                        GB_FORCED_LEVEL="performance"
                    else
                        GB_FORCED_LEVEL=""
                    fi
                    
                    # Apply gameboost
                    if command -v gb_apply >/dev/null 2>&1; then
                        # Simpan orig_level, tulis level target, apply,
                        # kembalikan orig_level. Berlaku untuk forced
                        # DAN non-forced (extreme eksplisit supaya
                        # _gb_level tidak jatuh ke fail-safe balanced).
                        local orig_level
                        orig_level=$(cat "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null)
                        local _target_level="${GB_FORCED_LEVEL:-${GB_BATT_LEVEL:-extreme}}"
                        printf '%s\n' "$_target_level" > "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null
                        gb_apply
                        if [ -n "$orig_level" ]; then
                            printf '%s\n' "$orig_level" > "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null
                        else
                            rm -f "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null
                        fi
                        # Log level BENAR-BENAR diterapkan (baca boost_level
                        # sesudah gb_apply, sebelum orig restore di atas
                        # sudah mengembalikan GAMEBOOST_LEVEL ke user).
                        local _applied
                        _applied=$(cat "${ALPHA_CONF_DIR:-/data/adb/alpha}/boost_level" 2>/dev/null)
                        [ -z "$_applied" ] && _applied="$_target_level"
                        printf '%s\n' "1" > "$GB_ACTIVE_FILE" 2>/dev/null
                        monitor_log "GAMEBOOST" "APPLIED ${_applied} for $handle_pkg (temp=${current_temp}mC)"
                    else
                        monitor_log "GAMEBOOST" "WARN: gb_apply unavailable, boost skipped for $handle_pkg"
                    fi
                fi
            fi
        fi
        # Cancel any pending restore
        if [ -f "$GB_PENDING_FILE" ]; then
            monitor_log "GAMEBOOST" "CANCEL restore: game returned within grace period"
            rm -f "$GB_PENDING_FILE"
        fi
    else
        # Not a game with performance profile
        rm -f "$GAME_T0_FILE" "$GAME_SNAP_DONE_FILE" 2>/dev/null
        if [ "$gb_active" = "1" ]; then
            # Start grace period if not already started
            if [ ! -f "$GB_PENDING_FILE" ]; then
                printf '%s\n' "$(date +%s)" > "$GB_PENDING_FILE" 2>/dev/null
                monitor_log "GAMEBOOST" "GRACE started: ${GB_GRACE}s before restore"
            fi
        fi
        # DAILY GAME PROMOTE: start grace when game-promoted game exits
        if [ "$game_promote" -eq 0 ] && [ "$handle_current" = "balanced" ]; then
            local manual_prof
            manual_prof=$(get_manual_profile)
            if [ "$manual_prof" = "battery" ] && [ ! -f "$GB_PENDING_FILE" ]; then
                printf '%s\n' "$(date +%s)" > "$GB_PENDING_FILE" 2>/dev/null
                monitor_log "GAMEBOOST" "DAILY GRACE started: ${GB_GRACE}s before returning to Daily"
            fi
        fi
    fi
    
    if [ "$handle_target" = "$handle_current" ]; then
        # Still need to check grace period in main loop
        return 0
    fi
    
    if [ "$handle_source" = "event" ]; then
        monitor_log "APPLY-EVENT" "package=$handle_pkg target=$handle_target current=${handle_current:-none}"
    else
        monitor_log "APPLY-POLL" "package=$handle_pkg target=$handle_target current=${handle_current:-none}"
    fi
    if APPLY_MONITOR_PKG="$handle_pkg" sh "$MODDIR/apply_now.sh" "$handle_target" monitor >> "$LOG_FILE" 2>&1; then
        if get_game_profile "$handle_pkg" >/dev/null 2>&1; then
            notify_mode_change "$handle_pkg" "$handle_target"
        else
            notify_mode_change "" "$handle_target"
        fi
    else
        monitor_log "WARNING" "apply_now failed profile=$handle_target"
    fi
    return 0
}

event_stream_reader() {
    while IFS= read -r event_line; do
        IFS=','
        event_line_tag_matched=0
        for event_tag in $EVENT_TAG_PATTERN; do
            case "$event_line" in
                *$event_tag*) event_line_tag_matched=1; break ;;
            esac
        done
        unset IFS
        [ "$event_line_tag_matched" -eq 1 ] || continue
        # CATATAN PERF: dumpsys power per-event dibuang - itu extra subprocess
        # spawn di SETIAP pergantian foreground app, padahal supervisor loop
        # di run_event_supervised_loop sudah matiin stream ini dalam <=2s
        # begitu layar off (lihat stop_event_stream di sana). Trade-off: ada
        # celah sempit (<2s) pas transisi layar off dimana 1 event nyasar
        # masih bisa kepakai, tapi ini lebih ringan buat SoC lemah & sudah
        # self-correct di event berikutnya.
        event_pkg=$(event_line_package "$event_line")
        if [ -n "$event_pkg" ]; then
            event_count_inc
            handle_foreground_event "$event_pkg" "event"
        fi
    done < "$EVENT_FIFO"
    return 0
}

# DAILY anti-lag guard: check loadavg1 > 6.5 (8-core) 2x consecutively
# When triggered, temporarily apply balanced VM/IO to relieve pressure,
# then return to battery when load drops.
check_daily_loadavg_guard() {
    # monitor.sh hanya source gameboost.sh; tune_vm/tune_io ada di engine.sh dan
    # TIDAK dimuat di proses ini, jadi pemanggilan di bawah selalu "not found"
    # (disenyapkan 2>/dev/null) dan guard tidak mengubah apa pun. Jujur: log
    # sekali, lalu keluar. Perilaku kernel tidak berubah.
    if ! command -v tune_vm >/dev/null 2>&1 || ! command -v tune_io >/dev/null 2>&1; then
        if [ "${DAILY_LOADGUARD_NOOP_LOGGED:-0}" != "1" ]; then
            DAILY_LOADGUARD_NOOP_LOGGED=1
            monitor_log "DAILY-LOADGUARD" "NO-OP: tune_vm/tune_io tidak dimuat di proses monitor, guard tidak mengubah VM/IO"
        fi
        return 0
    fi
    local current_prof
    current_prof=""
    [ -f "$CURRENT_STATE_FILE" ] && current_prof=$(tr -d '[:space:]' < "$CURRENT_STATE_FILE" 2>/dev/null)
    [ "$current_prof" != "battery" ] && return 0

    local load1
    load1=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
    case "$load1" in ''|*[!0-9.]*) return 0 ;; esac

    # Compare as integer (truncate decimals): load1 > 6.5 means >= 6.5
    local load1_int
    load1_int=$(printf '%.0f' "$load1" 2>/dev/null)
    case "$load1_int" in ''|*[!0-9]*) return 0 ;; esac

    local balanced_applied=0
    [ -f "$DAILY_LOADBAL_FILE" ] && balanced_applied=$(cat "$DAILY_LOADBAL_FILE" 2>/dev/null)

    if [ "$load1_int" -ge 7 ] 2>/dev/null; then
        local high_count=0
        [ -f "$DAILY_LOADHIGH_FILE" ] && high_count=$(cat "$DAILY_LOADHIGH_FILE" 2>/dev/null)
        case "$high_count" in ''|*[!0-9]*) high_count=0 ;; esac
        high_count=$((high_count + 1))
        printf '%s\n' "$high_count" > "$DAILY_LOADHIGH_FILE" 2>/dev/null

        if [ "$high_count" -ge 2 ] 2>/dev/null && [ "$balanced_applied" != "1" ]; then
            monitor_log "MONITOR" "DAILY LOADGUARD: loadavg1=$load1 >= 6.5 twice, temporarily applying balanced VM/IO"
            # Save current battery VM/IO values, apply balanced temporarily
            local saved_vfs saved_dirty saved_dirty_bg saved_stat saved_swap saved_ra
            saved_vfs="$VM_VFS_CACHE_PRESSURE"
            saved_dirty="$VM_DIRTY_RATIO"
            saved_dirty_bg="$VM_DIRTY_BACKGROUND_RATIO"
            saved_stat="$VM_STAT_INTERVAL"
            saved_swap="$VM_SWAPPINESS"
            saved_ra="$IO_READ_AHEAD_KB"
            # Apply balanced VM/IO values
            VM_VFS_CACHE_PRESSURE="${BALANCED_VM_VFS_CACHE_PRESSURE:-100}"
            VM_DIRTY_RATIO="${BALANCED_VM_DIRTY_RATIO:-20}"
            VM_DIRTY_BACKGROUND_RATIO="${BALANCED_VM_DIRTY_BACKGROUND_RATIO:-10}"
            VM_STAT_INTERVAL="${BALANCED_VM_STAT_INTERVAL:-10}"
            VM_SWAPPINESS="${BALANCED_VM_SWAPPINESS:-60}"
            IO_READ_AHEAD_KB="${BALANCED_IO_READ_AHEAD_KB:-128}"
            tune_vm 2>/dev/null
            tune_io 2>/dev/null
            # Restore battery values in memory (applied when load drops)
            VM_VFS_CACHE_PRESSURE="$saved_vfs"
            VM_DIRTY_RATIO="$saved_dirty"
            VM_DIRTY_BACKGROUND_RATIO="$saved_dirty_bg"
            VM_STAT_INTERVAL="$saved_stat"
            VM_SWAPPINESS="$saved_swap"
            IO_READ_AHEAD_KB="$saved_ra"
            printf '%s\n' "1" > "$DAILY_LOADBAL_FILE" 2>/dev/null
        fi
    else
        # Load normal: if we were balanced, restore battery VM/IO
        if [ "$balanced_applied" = "1" ]; then
            monitor_log "MONITOR" "DAILY LOADGUARD: loadavg1=$load1 < 6.5, restoring Daily VM/IO"
            tune_vm 2>/dev/null
            tune_io 2>/dev/null
            rm -f "$DAILY_LOADBAL_FILE" 2>/dev/null
        fi
        rm -f "$DAILY_LOADHIGH_FILE" 2>/dev/null
    fi
    return 0
}

# Forced-level bookkeeping (safety step-down): simpan level user,
# tulis performance sementara, kembalikan saat cooldown/restore.
_gb_force_level() {
    [ -f "$STATE_DIR/.gb_level_orig" ] || {
        if [ -f "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" ]; then
            cat "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" \
                > "$STATE_DIR/.gb_level_orig" 2>/dev/null
        else
            printf '%s\n' "__ABSENT__" > "$STATE_DIR/.gb_level_orig" 2>/dev/null
        fi
    }
    printf '%s\n' "performance" > "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null
}

_gb_unforce_level() {
    GB_FORCED_LEVEL=""
    if [ -f "$STATE_DIR/.gb_level_orig" ]; then
        local _o
        _o=$(cat "$STATE_DIR/.gb_level_orig" 2>/dev/null)
        if [ "$_o" = "__ABSENT__" ]; then
            rm -f "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null
        elif [ -n "$_o" ]; then
            printf '%s\n' "$_o" > "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null
        fi
        rm -f "$STATE_DIR/.gb_level_orig" 2>/dev/null
    fi
}

# Baca 1 baris file TANPA fork. Hasil di MONITOR_RD.
monitor_rd() {
    MONITOR_RD=""
    IFS= read -r MONITOR_RD 2>/dev/null < "$1" || [ -n "$MONITOR_RD" ]
}

# Uptime detik (bulat) tanpa fork. Hasil di MONITOR_UP (kosong bila gagal).
monitor_uptime() {
    MONITOR_UP=""
    read -r MONITOR_UP _ 2>/dev/null < /proc/uptime
    MONITOR_UP=${MONITOR_UP%%.*}
    case "$MONITOR_UP" in ''|*[!0-9]*) MONITOR_UP="" ;; esac
}

# Override kadensi loop dari file MONITOR_LOOP_SECS (1-8). Kosong = default.
monitor_loop_override() {
    MONITOR_LOOP_OVR=""
    [ -f "$MONITOR_LOOP_FILE" ] || return 0
    monitor_rd "$MONITOR_LOOP_FILE" || return 0
    case "$MONITOR_RD" in ''|*[!0-9]*) return 0 ;; esac
    [ "$MONITOR_RD" -ge 1 ] 2>/dev/null && [ "$MONITOR_RD" -le 8 ] 2>/dev/null && MONITOR_LOOP_OVR="$MONITOR_RD"
    return 0
}

# GAME-SNAPSHOT: nilai efektif node + state tepat saat game sudah GAME_SNAP_AFTER_SECS
# detik di foreground. Tiap run benchmark jadi self-documenting (jalur A/B,
# flag aktif, baterai, suhu). Murni baca.
log_game_snapshot() {
    [ -f "$GAME_T0_FILE" ] || return 0
    local _t0="" _pkg="" _now _el _last=""
    read -r _t0 _pkg 2>/dev/null < "$GAME_T0_FILE"
    case "$_t0" in ''|*[!0-9]*) return 0 ;; esac
    monitor_uptime
    _now="$MONITOR_UP"
    [ -n "$_now" ] || return 0
    _el=$((_now - _t0))
    if [ "$_el" -lt 0 ] 2>/dev/null; then
        # t0 sisa boot sebelumnya (uptime direset): mulai ulang, jangan macet.
        printf '%s %s\n' "$_now" "$_pkg" > "$GAME_T0_FILE" 2>/dev/null
        rm -f "$GAME_SNAP_DONE_FILE" 2>/dev/null
        return 0
    fi
    if [ -f "$GAME_SNAP_DONE_FILE" ]; then
        [ "$GAME_SNAP_EVERY_SECS" -gt 0 ] 2>/dev/null || return 0
        monitor_rd "$GAME_SNAP_DONE_FILE" && _last="$MONITOR_RD"
        case "$_last" in
            ''|*[!0-9]*) printf '%s\n' "$_now" > "$GAME_SNAP_DONE_FILE" 2>/dev/null; return 0 ;;
        esac
        [ $((_now - _last)) -ge "$GAME_SNAP_EVERY_SECS" ] 2>/dev/null || return 0
    else
        [ "$_el" -ge "$GAME_SNAP_AFTER_SECS" ] 2>/dev/null || return 0
    fi
    printf '%s\n' "$_now" > "$GAME_SNAP_DONE_FILE" 2>/dev/null

    local _cdir="${ALPHA_CONF_DIR:-/data/adb/alpha}"
    local _state="?" _boost="none" _gbact="0" _cap="?" _bst="?" _flags="" _f _io="" _d _n _ra _sc _tfo="?" _tmax="?"
    monitor_rd "$CURRENT_STATE_FILE" && _state="$MONITOR_RD"
    monitor_rd "$_cdir/boost_level" && _boost="$MONITOR_RD"
    monitor_rd "$GB_ACTIVE_FILE" && _gbact="$MONITOR_RD"
    monitor_rd "${SYSFS_POWER_PREFIX:-/sys/class/power_supply}/battery/capacity" && _cap="$MONITOR_RD"
    monitor_rd "${SYSFS_POWER_PREFIX:-/sys/class/power_supply}/battery/status" && _bst="$MONITOR_RD"
    monitor_rd "${PROC_SYS_PREFIX:-/proc/sys}/net/ipv4/tcp_fastopen" && _tfo="$MONITOR_RD"
    for _f in DISABLE_GAMEBOOST GB_WARN_BOOST GB_PROFILE_OWNS_IO GB_COOLDOWN_EXTREME; do
        [ -f "$_cdir/$_f" ] && _flags="$_flags $_f"
    done
    monitor_loop_override
    [ -n "$MONITOR_LOOP_OVR" ] && _flags="$_flags MONITOR_LOOP_SECS=$MONITOR_LOOP_OVR"
    for _d in "${SYSFS_BLOCK_PREFIX:-/sys/block}"/sd* "${SYSFS_BLOCK_PREFIX:-/sys/block}"/mmcblk*; do
        [ -d "$_d/queue" ] || continue
        _n=${_d##*/}
        case "$_n" in *p[0-9]*|*[0-9]rpmb|*[0-9]boot*) continue ;; esac
        monitor_rd "$_d/queue/read_ahead_kb"; _ra="$MONITOR_RD"
        monitor_rd "$_d/queue/scheduler"; _sc="$MONITOR_RD"
        # scheduler aktif = yang dalam [kurung]
        case "$_sc" in *\[*\]*) _sc=${_sc#*\[}; _sc=${_sc%%\]*} ;; esac
        _io="$_io $_n:ra=$_ra sched=$_sc"
    done
    local _cpu="" _p _pn _c _mn _mx _fm="-"
    for _p in "${SYSFS_CPU_PREFIX:-/sys/devices/system/cpu}"/cpufreq/policy*; do
        [ -d "$_p" ] || continue
        _pn=${_p##*/}
        monitor_rd "$_p/scaling_cur_freq"; _c="$MONITOR_RD"
        monitor_rd "$_p/scaling_min_freq"; _mn="$MONITOR_RD"
        monitor_rd "$_p/scaling_max_freq"; _mx="$MONITOR_RD"
        _cpu="$_cpu $_pn:cur=$_c,min=$_mn,max=$_mx"
    done
    monitor_rd "${ALPHA_FASRS_MODE_NODE:-/dev/fas_rs/mode}" && _fm="$MONITOR_RD"
    command -v gb_safety_check >/dev/null 2>&1 && _tmax=$(gb_safety_check)
    monitor_log "GAME-SNAPSHOT" "pkg=${_pkg:-?} t=+${_el}s method=${MONITOR_METHOD} profile=${_state} gb_active=${_gbact} boost_level=${_boost} batt=${_cap}%(${_bst}) temp_max=${_tmax}mC tfo=${_tfo} fasrs_mode=${_fm} forced=${GB_FORCED_LEVEL:-none} batt_lv=${GB_BATT_LEVEL:-none} cpu:${_cpu} io:${_io} flags:${_flags:- none}"
    return 0
}

# Check GameBoost grace period and safety
check_gb_grace_period() {
    local now
    now=$(date +%s 2>/dev/null)
    
    # Check pending restore
    if [ -f "$GB_PENDING_FILE" ]; then
        local pending_time
        pending_time=$(cat "$GB_PENDING_FILE" 2>/dev/null)
        case "$pending_time" in ''|*[!0-9]*) rm -f "$GB_PENDING_FILE"; return 0 ;; esac
        
        local elapsed=$((now - pending_time))
        if [ "$elapsed" -ge "$GB_GRACE" ] 2>/dev/null; then
            # Grace period expired: restore original profile
            local manual_prof
            manual_prof=$(get_manual_profile)
            if [ "$manual_prof" = "battery" ]; then
                # DAILY restore: kembalikan boost dulu (bila aktif), lalu ke Daily
                if [ -f "$GB_ACTIVE_FILE" ] && [ "$(cat "$GB_ACTIVE_FILE" 2>/dev/null)" = "1" ] \
                    && command -v gb_restore >/dev/null 2>&1; then
                    gb_restore
                    printf '%s\n' "0" > "$GB_ACTIVE_FILE" 2>/dev/null
                elif [ -f "$GB_ACTIVE_FILE" ] && [ "$(cat "$GB_ACTIVE_FILE" 2>/dev/null)" = "1" ] \
                    && ! command -v gb_restore >/dev/null 2>&1; then
                    monitor_log "GAMEBOOST" "WARN: gb_restore unavailable, cannot restore Daily boost"
                fi
                _gb_unforce_level
                sh "$MODDIR/apply_now.sh" battery monitor >> "$LOG_FILE" 2>&1
                monitor_log "GAMEBOOST" "DAILY RESTORED after ${GB_GRACE}s grace, returning to Daily"
            elif command -v gb_restore >/dev/null 2>&1; then
                gb_restore
                printf '%s\n' "0" > "$GB_ACTIVE_FILE" 2>/dev/null
                _gb_unforce_level
                monitor_log "GAMEBOOST" "RESTORED after ${GB_GRACE}s grace"
            else
                monitor_log "GAMEBOOST" "WARN: gb_restore unavailable, cannot restore after grace"
            fi
            rm -f "$GB_PENDING_FILE"
        fi
    fi
    
    # Safety check every 15 seconds if gameboost is active
    local gb_active=0
    [ -f "$GB_ACTIVE_FILE" ] && gb_active=$(cat "$GB_ACTIVE_FILE" 2>/dev/null)
    
    if [ "$gb_active" = "1" ]; then
        local time_since_last=$((now - GB_SAFETY_LAST))
        if [ "$time_since_last" -ge "$GB_SAFETY_INTERVAL" ] 2>/dev/null; then
            GB_SAFETY_LAST=$now
            local current_temp
            current_temp=$(gb_safety_check)
            # Tangga termal sadar profil manual (sama seperti gate apply
            # game di atas): manual performance -> warm 85 / high 90,
            # sisanya 75/85. Kritis 95C (forced battery) tetap.
            local gb_warm_thr=75000 gb_high_thr=85000 gb_manual_prof
            gb_manual_prof=$(get_manual_profile)
            thermal_user_thr
            gb_warm_thr=$TH_BASE_WARM
            gb_high_thr=$((TH_BASE_WARM + 10000))
            if [ "$gb_manual_prof" = "performance" ]; then
                gb_warm_thr=$((TH_BASE_WARM + 10000))
                gb_high_thr=$((TH_BASE_WARM + 15000))
            fi
            if [ "$TH_GUARD_OFF" = "1" ]; then
                gb_warm_thr=200000
                gb_high_thr=200000
            fi

            # Konfirmasi 2 sampel sebelum step-down/kritis. Satu bacaan sensor
            # rusak yang melonjak (114C padahal SoC 52C) sebelumnya langsung
            # membunuh boost + mengunci profil battery sampai game ditutup.
            # Biaya salah-tolak panas asli: paling lama 1 tick (15 dtk), kernel
            # tetap punya proteksi termal sendiri. Biaya salah-bunuh: seluruh
            # sesi. Hanya jalan saat sampel pertama >= warm (jarang), jadi
            # suhu normal tidak menambah fork/sleep.
            # TIDAK ada opt-out lagi (v46): flag GB_THERMAL_NOCONFIRM sudah
            # dibuang karena cuma mengembalikan bug yang v45 perbaiki
            # (1 sampel = salah-bunuh boost di sensor bohong).
            if [ "$current_temp" -ge "$gb_warm_thr" ] 2>/dev/null; then
                local gb_confirm_temp gb_first_temp="$current_temp"
                sleep 2
                gb_confirm_temp=$(gb_safety_check)
                if [ "$gb_confirm_temp" -lt "$gb_warm_thr" ] 2>/dev/null; then
                    monitor_log "SENSOR-GLITCH" "sampel1=${gb_first_temp}mC tidak terkonfirmasi (sampel2=${gb_confirm_temp}mC < warm ${gb_warm_thr}), diabaikan"
                    current_temp="$gb_confirm_temp"
                else
                    # Keduanya >= warm: pakai yang lebih rendah (tahan satu spike).
                    [ "$gb_confirm_temp" -lt "$current_temp" ] 2>/dev/null && current_temp="$gb_confirm_temp"
                    monitor_log "THERMAL-CONFIRM" "sampel1=${gb_first_temp}mC sampel2=${gb_confirm_temp}mC terkonfirmasi, dipakai ${current_temp}mC"
                fi
            fi
            
            # Check thermal thresholds
            if [ "$current_temp" -ge 95000 ] 2>/dev/null; then
                # Critical: restore and apply battery
                if command -v gb_restore >/dev/null 2>&1; then
                    gb_restore
                else
                    monitor_log "GAMEBOOST" "WARN: gb_restore unavailable during critical temp restore"
                fi
                _gb_unforce_level
                sh "$MODDIR/apply_now.sh" battery monitor >> "$LOG_FILE" 2>&1
                printf '%s\n' "0" > "$GB_ACTIVE_FILE" 2>/dev/null
                rm -f "$GB_PENDING_FILE"
                monitor_log "GAMEBOOST" "CRITICAL TEMP: ${current_temp}mC >= 95000, forced battery (manual=${gb_manual_prof})"
            elif [ "$current_temp" -ge "$gb_high_thr" ] 2>/dev/null; then
                # High: restore and apply balanced
                if command -v gb_restore >/dev/null 2>&1; then
                    gb_restore
                else
                    monitor_log "GAMEBOOST" "WARN: gb_restore unavailable during high temp restore"
                fi
                _gb_unforce_level
                sh "$MODDIR/apply_now.sh" balanced monitor >> "$LOG_FILE" 2>&1
                printf '%s\n' "0" > "$GB_ACTIVE_FILE" 2>/dev/null
                rm -f "$GB_PENDING_FILE"
                monitor_log "GAMEBOOST" "HIGH TEMP: ${current_temp}mC >= ${gb_high_thr}, forced balanced (manual=${gb_manual_prof})"
            elif [ "$current_temp" -ge "$gb_warm_thr" ] 2>/dev/null; then
                # Warm: step down ke resep performance SEKARANG (bukan cuma var)
                if [ -z "$GB_FORCED_LEVEL" ]; then
                    GB_FORCED_LEVEL="performance"
                    _gb_force_level
                    if command -v gb_apply >/dev/null 2>&1; then
                        gb_apply
                    else
                        monitor_log "GAMEBOOST" "WARN: gb_apply unavailable during warm temp step-down"
                    fi
                    rm -f "$GB_COOLDOWN_COUNT_FILE" 2>/dev/null
                    monitor_log "GAMEBOOST" "WARM TEMP: ${current_temp}mC >= ${gb_warm_thr}, stepped down to performance (manual=${gb_manual_prof})"
                fi
            elif [ "$current_temp" -lt "${TH_REL:-70000}" ] 2>/dev/null; then
                # Cool down: check if we were forced
                if [ -n "$GB_FORCED_LEVEL" ]; then
                    # Check cooldown period (60 dtk = 60/15 = 4 tick)
                    local cooldown_count=0
                    local cooldown_need=4
                    [ -n "$GB_SAFETY_INTERVAL" ] && [ "$GB_SAFETY_INTERVAL" -gt 0 ] 2>/dev/null && \
                        cooldown_need=$(( (GB_COOLDOWN_SECS + GB_SAFETY_INTERVAL - 1) / GB_SAFETY_INTERVAL ))
                    [ "$cooldown_need" -lt 1 ] 2>/dev/null && cooldown_need=1
                    [ -f "$GB_COOLDOWN_COUNT_FILE" ] && cooldown_count=$(cat "$GB_COOLDOWN_COUNT_FILE" 2>/dev/null)
                    case "$cooldown_count" in ''|*[!0-9]*) cooldown_count=0 ;; esac

                    cooldown_count=$((cooldown_count + 1))
                    printf '%s\n' "$cooldown_count" > "$GB_COOLDOWN_COUNT_FILE" 2>/dev/null
                    if [ "$cooldown_count" -ge "$cooldown_need" ] 2>/dev/null; then
                        _gb_unforce_level
                        rm -f "$GB_COOLDOWN_COUNT_FILE"
                        local _cool_level=""
                        if command -v gb_apply >/dev/null 2>&1; then
                            if [ -f "${ALPHA_CONF_DIR:-/data/adb/alpha}/GB_COOLDOWN_EXTREME" ]; then
                                # Legacy: gb_apply tanpa level eksplisit -> _gb_level
                                # fail-safe "balanced" (GAMEBOOST_LEVEL dihapus saat
                                # boot) = restore-only, boost mati diam-diam. Flag ini:
                                # kembali ke level game seperti jalur buka-game
                                # (extreme, atau batas baterai bila GB_WARN_BOOST).
                                # Hanya tercapai setelah suhu <70C 60 dtk; thermal
                                # tetap menang (naik lagi -> tangga step-down jalan).
                                local _cd_orig _cd_target
                                _cd_orig=$(cat "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null)
                                _cd_target="${GB_BATT_LEVEL:-extreme}"
                                printf '%s\n' "$_cd_target" > "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null
                                gb_apply
                                if [ -n "$_cd_orig" ]; then
                                    printf '%s\n' "$_cd_orig" > "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null
                                else
                                    rm -f "${ALPHA_CONF_DIR:-/data/adb/alpha}/GAMEBOOST_LEVEL" 2>/dev/null
                                fi
                                monitor_log "GB-COOLDOWN" "re-apply level=${_cd_target} (flag GB_COOLDOWN_EXTREME)"
                            else
                                gb_apply
                            fi
                            _cool_level=$(cat "${ALPHA_CONF_DIR:-/data/adb/alpha}/boost_level" 2>/dev/null)
                        else
                            monitor_log "GAMEBOOST" "WARN: gb_apply unavailable during cooldown complete"
                        fi
                        [ -z "$_cool_level" ] && _cool_level="(unknown)"
                        monitor_log "GAMEBOOST" "COOLDOWN COMPLETE: temp<70C 60s, level=${_cool_level}"
                    fi
                fi
            fi
        fi
    fi
    
    return 0
}

start_event_stream() {
    stop_event_stream
    rm -f "$LAST_EVENT_PKG_FILE" 2>/dev/null
    EVENT_FIFO="$STATE_DIR/.foreground-events.$$.fifo"
    rm -f "$EVENT_FIFO" 2>/dev/null
    mkfifo "$EVENT_FIFO" 2>/dev/null || return 1
    event_stream_reader > /dev/null 2>&1 &
    READER_PID="$!"
    logcat -b events -v raw > "$EVENT_FIFO" 2>/dev/null &
    LOGCAT_PID="$!"
    sleep 1
    kill -0 "$READER_PID" 2>/dev/null || return 1
    kill -0 "$LOGCAT_PID" 2>/dev/null || { stop_event_stream; return 1; }
    EVENT_ON_SECS=0
    printf '%s' "0" > "$EVENT_COUNT_FILE" 2>/dev/null
    return 0
}

run_event_supervised_loop() {
    while [ "$STOP_MONITOR" -eq 0 ]; do
        monitor_screen_state=$(get_screen_state)
        if [ "$?" -ne 0 ]; then
            monitor_log "WARNING" "dumpsys power failed; pausing event stream"
            stop_event_stream
            sleep "$SCREEN_OFF_INTERVAL"
            continue
        fi
        if [ "$monitor_screen_state" != "ON" ]; then
            stop_event_stream
            sleep "$SCREEN_OFF_INTERVAL"
            continue
        fi
        stream_ok=1
        [ -n "$READER_PID" ] && kill -0 "$READER_PID" 2>/dev/null || stream_ok=0
        [ -n "$LOGCAT_PID" ] && kill -0 "$LOGCAT_PID" 2>/dev/null || stream_ok=0
        if [ "$stream_ok" -ne 1 ]; then
            if start_event_stream; then
                monitor_log "EVENT" "foreground event stream started"
            else
                monitor_log "WARNING" "event stream failed to start; retrying"
                sleep "$SCREEN_ON_INTERVAL"
                continue
            fi
        fi
        # Health window = detik layar-nyala sejak stream terakhir di-(re)start.
        # Reset window + count di start_event_stream mencegah vonis "deaf"
        # membandingkan detik basi dengan count fresh (false-positive live 446s).
        # Jika jendela lewat tapi NOL event ter-parse, fallback polling permanen
        # sisa sesi. Layar-mati tidak dihitung, jadi "sepi karena idle" tidak
        # disalahartikan sebagai "filter rusak".
        monitor_loop_override
        monitor_ev_secs="${MONITOR_LOOP_OVR:-$EVENT_LOOP_SECS_DEFAULT}"
        EVENT_ON_SECS=$((EVENT_ON_SECS + monitor_ev_secs))
        if [ "$EVENT_FALLBACK_DONE" -eq 0 ] && [ "$EVENT_ON_SECS" -ge "$EVENT_HEALTH_SECS" ] 2>/dev/null; then
            event_parsed=$(event_count_get)
            [ -z "$event_parsed" ] && event_parsed=0
            if [ "$event_parsed" -lt 1 ] 2>/dev/null; then
                EVENT_FALLBACK_DONE=1
                monitor_log "WARNING" "event stream deaf (${EVENT_ON_SECS}s on, 0 parsed); falling back to polling permanently"
                stop_event_stream
                MONITOR_METHOD="polling (event fallback)"
                run_polling_loop
                return 0
            elif [ "$EVENT_HEALTH_LOGGED" -eq 0 ]; then
                EVENT_HEALTH_LOGGED=1
                monitor_log "EVENT" "event stream healthy (${event_parsed} parsed in ${EVENT_ON_SECS}s)"
            fi
        fi
        # GameBoost: check grace period + thermal safety
        check_gb_grace_period
        log_game_snapshot
        # DAILY: anti-lag guard (loadavg)
        check_daily_loadavg_guard
        sleep "$monitor_ev_secs"
    done
    stop_event_stream
    return 0
}

run_polling_loop() {
    monitor_cycle=0
    while [ "$STOP_MONITOR" -eq 0 ]; do
        if [ "$MAX_CYCLES" -gt 0 ] 2>/dev/null && [ "$monitor_cycle" -ge "$MAX_CYCLES" ]; then
            break
        fi
        monitor_cycle=$((monitor_cycle + 1))

        monitor_use_cache=0
        if [ -n "$monitor_fg_cache_pkg" ]; then
            read -r monitor_now_up _ 2>/dev/null < /proc/uptime
            monitor_now_up=${monitor_now_up%%.*}
            case "$monitor_now_up" in ''|*[!0-9]*) monitor_now_up=0 ;; esac
            case "$monitor_fg_cache_ts" in ''|*[!0-9]*) monitor_fg_cache_ts=0 ;; esac
            if [ "$monitor_now_up" -gt 0 ] && [ "$monitor_fg_cache_ts" -gt 0 ] \
                && [ $((monitor_now_up - monitor_fg_cache_ts)) -lt "$FG_FULLCHK_SECS" ] \
                && [ -n "$(pidof "$monitor_fg_cache_pkg" 2>/dev/null)" ]; then
                monitor_use_cache=1
            fi
        fi

        if [ "$monitor_use_cache" -eq 1 ]; then
            monitor_foreground_package="$monitor_fg_cache_pkg"
        else
        monitor_screen_state=$(get_screen_state)
        if [ "$?" -ne 0 ]; then
            monitor_log "WARNING" "dumpsys power failed; skipping cycle=$monitor_cycle"
            sleep "$SCREEN_OFF_INTERVAL"
            continue
        fi

        if [ "$monitor_screen_state" != "ON" ]; then
            monitor_fg_cache_pkg=""
            sleep "$SCREEN_OFF_INTERVAL"
            continue
        fi

        monitor_foreground_package=$(get_foreground_package)
        if [ "$?" -ne 0 ] || [ -z "$monitor_foreground_package" ]; then
            monitor_log "WARNING" "foreground package unavailable; skipping cycle=$monitor_cycle"
            monitor_fg_cache_pkg=""
            sleep "$SCREEN_ON_INTERVAL"
            continue
        fi
        fi

        monitor_poll_interval="$SCREEN_ON_INTERVAL"
        if [ -n "$(get_game_profile "$monitor_foreground_package")" ]; then
            monitor_loop_override
            monitor_poll_interval="${MONITOR_LOOP_OVR:-$GAME_POLL_INTERVAL_SECS}"
            if [ "$monitor_use_cache" -eq 0 ]; then
                read -r monitor_fg_cache_ts _ 2>/dev/null < /proc/uptime
                monitor_fg_cache_ts=${monitor_fg_cache_ts%%.*}
                monitor_fg_cache_pkg="$monitor_foreground_package"
            fi
        else
            monitor_fg_cache_pkg=""
        fi

        handle_foreground_event "$monitor_foreground_package" "poll"

        # GameBoost: check grace period + thermal safety
        check_gb_grace_period
        log_game_snapshot
        # DAILY: anti-lag guard (loadavg)
        check_daily_loadavg_guard
        sleep "$monitor_poll_interval"
    done
    return 0
}

check_notify_available
event_precheck_ok=0
event_precheck_log=""
event_precheck_reason="logcat-events-unavailable"
if command -v logcat >/dev/null 2>&1 && command -v mkfifo >/dev/null 2>&1; then
    event_precheck_log=$(logcat -b events -v raw -d -t "$EVENT_PRECHECK_LINES" 2>/dev/null)
    event_precheck_regex=$(printf '%s' "$EVENT_TAG_PATTERN" | sed 's/,/|/g')
    if printf '%s\n' "$event_precheck_log" | grep -Eq "$event_precheck_regex"; then
        event_precheck_ok=1
    else
        event_precheck_reason="logcat-events-no-matching-tags"
    fi
fi
# Pre-check isi bisa false-negative kalau histori kosong setelah user lama
# tidak ganti app; diterima karena polling + interval game cepat menjadi jaring,
# dan health check tetap backstop bila pre-check lolos tetapi stream mati.
if [ "$event_precheck_ok" -eq 1 ]; then
    MONITOR_METHOD="event-driven"
    monitor_log "START" "monitor pid=$$ method=event-driven health=${EVENT_HEALTH_SECS}s interval_on=${SCREEN_ON_INTERVAL}s interval_off=${SCREEN_OFF_INTERVAL}s"
    run_event_supervised_loop
else
    MONITOR_METHOD="polling"
    monitor_log "START" "monitor pid=$$ method=polling reason=${event_precheck_reason} interval_on=${SCREEN_ON_INTERVAL}s interval_game=${GAME_POLL_INTERVAL_SECS}s interval_off=${SCREEN_OFF_INTERVAL}s"
    run_polling_loop
fi

monitor_log "STOP" "monitor stopped"
exit 0
