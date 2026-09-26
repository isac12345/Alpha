#!/system/bin/sh
# Alpha v1 - Screen-aware foreground profile monitor

MODDIR="${0%/*}"
STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
PID_FILE="$STATE_DIR/monitor.pid"
MAP_FILE="$STATE_DIR/game_profile_map.conf"
ACTIVE_PROFILE_FILE="$STATE_DIR/active_profile"
CURRENT_STATE_FILE="$STATE_DIR/current_state"
LOG_FILE="${ALPHA_LOG_FILE:-$STATE_DIR/alpha.log}"
SCREEN_ON_INTERVAL="${ALPHA_SCREEN_ON_INTERVAL:-7}"
SCREEN_OFF_INTERVAL="${ALPHA_SCREEN_OFF_INTERVAL:-60}"
GAME_POLL_INTERVAL_SECS="${ALPHA_GAME_POLL_INTERVAL_SECS:-2}"
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
GB_COOLDOWN_SECS=60
GB_COOLDOWN_COUNT_FILE="$STATE_DIR/.gb_cooldown_count"
# Ambang "high" loop termal (dolar ke atas) dipakai juga adaptive floor.
# Nilai live di-refresh tiap safety tick; default = ambang non-performance.
GB_HIGH_THR=85000

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
        monitor_map_line=$(printf '%s' "$monitor_map_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
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
gb_safety_check() {
    local current_temp=0
    local max_temp=0
    local valid_count=0

    # Read thermal zones
    if [ -d "${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}" ]; then
        for zone in "${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"/thermal_zone*; do
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
            # Filter valid range: -50000..150000 milliC
            [ "$current_temp" -ge -50000 ] 2>/dev/null && \
                [ "$current_temp" -le 150000 ] 2>/dev/null || continue
            if [ "$current_temp" -gt "$max_temp" ] 2>/dev/null; then
                max_temp=$current_temp
            fi
            valid_count=$((valid_count + 1))
        done
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
        if [ "$gb_active" != "1" ]; then
            # Check DISABLE_GAMEBOOST gate
            if [ -f "${ALPHA_CONF_DIR:-/data/adb/alpha}/DISABLE_GAMEBOOST" ]; then
                monitor_log "GAMEBOOST" "DISABLED by DISABLE_GAMEBOOST file"
            else
                # Check battery status
                local battery_status
                battery_status=$(check_battery_status)
                if [ "$battery_status" = "LOW" ]; then
                    monitor_log "GAMEBOOST" "SKIPPED: battery <15% without charging"
                elif [ "$battery_status" = "WARNING" ]; then
                    # Battery <30% without charging: force performance-level boost
                    # (not battery) following HSIN safety policy
                    monitor_log "GAMEBOOST" "BATTERY WARNING: <30% without charging, forcing performance-level boost"
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
                    if [ "$gb_manual_prof" = "performance" ]; then
                        gb_warm_thr=85000
                        gb_high_thr=90000
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
                        local _target_level="${GB_FORCED_LEVEL:-extreme}"
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
            if [ "$gb_manual_prof" = "performance" ]; then
                gb_warm_thr=85000
                gb_high_thr=90000
            fi
            # Publikasikan ambang high yang terpakai gate di bawah supaya
            # consumer adaptive GPU floor (agf_tick) memakai angka yang
            # sama persis, bukan salinan yang bisa melenceng.
            GB_HIGH_THR="$gb_high_thr"
            
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
            elif [ "$current_temp" -lt 70000 ] 2>/dev/null; then
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
                            gb_apply
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

# ============================================================
# Adaptive GPU floor (prototipe tiered-delta)
# ============================================================
# Filosofi: floor GPU min_freq ngikut beban nyata, bukan angka
# mati dari profile. Beban tidak bisa dibaca dari node utilization
# instan (T615 tak punya), jadi dibaca dari DELTA trans_stat
# devfreq GPU: file kumulatif, kolom terakhir = total time (ms).
# busy% = 100 * (1 - delta_kolom_terendah / delta_total).
# Tier 3 saja: HIGH (busy >= AGF_HIGH_PCT), MID (>= AGF_MID_PCT),
# LOW sisanya. Naik tier LANGSUNG, turun tier baru berlaku setelah
# AGF_DROP_TICKS tick berturut-turut (hysteresis), suhu >= ambang
# high loop paksa LOW. Target tiap tier = persen dari plafon profil
# aktif (floor profil, dibaca LIVE dari profiles.sh) dengan snapping
# ke rung tabel terbesar <= target, jadi adaptive tak pernah menulis
# di atas ceiling profil. Semua angka device (rung, hw_max) diambil
# dari sysfs, tak ada yang dipatok di skrip.
# Hanya jalan saat GameBoost aktif; non-aktif = return 0 tanpa
# menyentuh apa pun (pemulihan tetap gb_restore).
AGF_STATE_FILE="$STATE_DIR/.agf_state"
AGF_HIGH_PCT="${ALPHA_AGF_HIGH_PCT:-70}"
AGF_MID_PCT="${ALPHA_AGF_MID_PCT:-30}"
AGF_MID_TIER_PCT="${ALPHA_AGF_MID_TIER_PCT:-60}"
AGF_DROP_TICKS="${ALPHA_AGF_DROP_TICKS:-3}"
AGF_GPU_NODE=""
AGF_PREV_TOTAL=0
AGF_PREV_LOW=0
AGF_LOWCOUNT=0
AGF_TIER=""
AGF_FLOOR_BALANCED=""
AGF_FLOOR_PERFORMANCE=""
AGF_LOGGED_NOSTAT=0
AGF_LOGGED_RO=0
AGF_LOGGED_FLOOR=0

# Ambang tier + hysteresis: nilai rusak/0 -> default, biar file
# state yang digarap user tak bisa membuat tier mati diam-diam.
agf_load_limits() {
    case "$AGF_HIGH_PCT" in ''|*[!0-9]*) AGF_HIGH_PCT=70 ;; esac
    case "$AGF_MID_PCT" in ''|*[!0-9]*) AGF_MID_PCT=30 ;; esac
    case "$AGF_MID_TIER_PCT" in ''|*[!0-9]*) AGF_MID_TIER_PCT=60 ;; esac
    case "$AGF_DROP_TICKS" in ''|*[!0-9]*) AGF_DROP_TICKS=3 ;; esac
    [ "$AGF_HIGH_PCT" -gt 100 ] 2>/dev/null && AGF_HIGH_PCT=100
    [ "$AGF_MID_PCT" -gt 100 ] 2>/dev/null && AGF_MID_PCT=100
    [ "$AGF_MID_TIER_PCT" -gt 100 ] 2>/dev/null && AGF_MID_TIER_PCT=100
    [ "$AGF_DROP_TICKS" -ge 1 ] 2>/dev/null || AGF_DROP_TICKS=3
    return 0
}

# Log satu kali per proses per kondisi (jangan spam tiap tick).
agf_log_once() {
    case "$1" in
        nostat) [ "$AGF_LOGGED_NOSTAT" = "1" ] && return 0; AGF_LOGGED_NOSTAT=1 ;;
        ro) [ "$AGF_LOGGED_RO" = "1" ] && return 0; AGF_LOGGED_RO=1 ;;
        floor) [ "$AGF_LOGGED_FLOOR" = "1" ] && return 0; AGF_LOGGED_FLOOR=1 ;;
        *) return 0 ;;
    esac
    monitor_log "$2" "$3"
    return 0
}

# Node devfreq GPU yang punya trans_stat: scan generik *gpu*/*mali*
# (path device bisa platform/mali, misc/mali0, atau 23100000.gpu).
agf_find_gpu_node() {
    if [ -n "$AGF_GPU_NODE" ] && [ -r "$AGF_GPU_NODE/trans_stat" ]; then
        printf '%s\n' "$AGF_GPU_NODE"
        return 0
    fi
    AGF_GPU_NODE=""
    for agf_node_try in "${SYSFS_DEVFREQ_PREFIX:-/sys/class/devfreq}"/*gpu* "${SYSFS_DEVFREQ_PREFIX:-/sys/class/devfreq}"/*mali*; do
        [ -d "$agf_node_try" ] || continue
        [ -r "$agf_node_try/trans_stat" ] || continue
        [ -e "$agf_node_try/min_freq" ] || continue
        AGF_GPU_NODE="$agf_node_try"
        printf '%s\n' "$AGF_GPU_NODE"
        return 0
    done
    return 1
}

# Isi trans_stat -> "<kolom_terendah> <kolom_terakhir>". Kolom
# non-angka dibuang; butuh >= 2 kolom numerik.
agf_read_trans() {
    [ -r "$1" ] || return 1
    agf_line=$(tr -s '[:space:]' '\n' < "$1" 2>/dev/null | grep -E '^[0-9]+$' | tr '\n' ' ')
    agf_line=${agf_line% }
    case "$agf_line" in
        *' '*) ;;
        *) return 1 ;;
    esac
    agf_total=${agf_line##* }
    agf_head=${agf_line% * }
    agf_low=$(printf '%s\n' "$agf_head" | tr ' ' '\n' | sort -n | head -n 1)
    case "$agf_total" in ''|*[!0-9]*) return 1 ;; esac
    case "$agf_low" in ''|*[!0-9]*) return 1 ;; esac
    printf '%s %s\n' "$agf_low" "$agf_total"
    return 0
}

# Rung tabel terbesar <= target Hz (snap ke bawah, samaperti
# alpha_opp_cap_pick). Target tidak valid/0 -> return 1.
agf_opp_floor() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    agf_best=""
    for agf_f in $2; do
        case "$agf_f" in ''|*[!0-9]*) continue ;; esac
        [ "$agf_f" -le "$1" ] 2>/dev/null || continue
        if [ -z "$agf_best" ] || [ "$agf_f" -gt "$agf_best" ] 2>/dev/null; then
            agf_best="$agf_f"
        fi
    done
    [ -n "$agf_best" ] || return 1
    printf '%s\n' "$agf_best"
    return 0
}

# Plafon adaptive = floor profil aktif, dibaca live dari profiles.sh
# (sumber tunggal angka floor, bukan salinan). profiles.sh tak
# terbaca/nilai rusak -> return 1 supaya adaptive mati dengan jujur
# (tidak pernah jatuh ke angka hardcode).
agf_floor_pct() {
    case "$1" in
        performance) agf_pct_cached="$AGF_FLOOR_PERFORMANCE" ;;
        balanced) agf_pct_cached="$AGF_FLOOR_BALANCED" ;;
        *) return 1 ;;
    esac
    case "$agf_pct_cached" in
        ''|*[!0-9]*) ;;
        *) printf '%s\n' "$agf_pct_cached"; return 0 ;;
    esac
    [ -r "$MODDIR/profiles.sh" ] || return 1
    agf_prof_upper=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
    agf_pct=$(sed -n -E "s/^${agf_prof_upper}_GPU_FREQ_FLOOR_PERCENT=([0-9]+).*/\1/p" "$MODDIR/profiles.sh" 2>/dev/null | head -n 1)
    case "$agf_pct" in ''|*[!0-9]*) return 1 ;; esac
    case "$1" in
        performance) AGF_FLOOR_PERFORMANCE="$agf_pct" ;;
        balanced) AGF_FLOOR_BALANCED="$agf_pct" ;;
    esac
    printf '%s\n' "$agf_pct"
    return 0
}

# Tier + counter hysteresis. Turun = MISS (counter naik, tier
# ditahan); naik = langsung dipakai. Reset counter saat naik atau
# saat tier sama (momen "idle" terputus).
agf_apply_hysteresis() {
    AGF_WANT_TIER="$1"
    AGF_WANT_RANK=0
    AGF_CUR_RANK=0
    case "$AGF_WANT_TIER" in HIGH) AGF_WANT_RANK=3 ;; MID) AGF_WANT_RANK=2 ;; LOW) AGF_WANT_RANK=1 ;; esac
    case "$AGF_TIER" in HIGH) AGF_CUR_RANK=3 ;; MID) AGF_CUR_RANK=2 ;; LOW) AGF_CUR_RANK=1 ;; esac
    if [ "$AGF_WANT_RANK" -gt "$AGF_CUR_RANK" ]; then
        AGF_NEXT_TIER="$AGF_WANT_TIER"
        AGF_LOWCOUNT=0
        return 0
    fi
    if [ "$AGF_WANT_RANK" -eq "$AGF_CUR_RANK" ]; then
        AGF_NEXT_TIER="$AGF_WANT_TIER"
        AGF_LOWCOUNT=0
        return 0
    fi
    AGF_LOWCOUNT=$((AGF_LOWCOUNT + 1))
    AGF_NEXT_TIER="$AGF_TIER"
    [ "$AGF_LOWCOUNT" -ge "$AGF_DROP_TICKS" ] 2>/dev/null || return 0
    AGF_NEXT_TIER="$AGF_WANT_TIER"
    AGF_LOWCOUNT=0
    return 0
}

agf_state_load() {
    AGF_PREV_TOTAL=0
    AGF_PREV_LOW=0
    AGF_LOWCOUNT=0
    AGF_TIER=""
    [ -f "$AGF_STATE_FILE" ] || return 1
    read -r AGF_PREV_TOTAL AGF_PREV_LOW AGF_LOWCOUNT AGF_TIER < "$AGF_STATE_FILE" 2>/dev/null || return 1
    case "$AGF_PREV_TOTAL" in ''|*[!0-9]*) return 1 ;; esac
    case "$AGF_PREV_LOW" in ''|*[!0-9]*) return 1 ;; esac
    case "$AGF_LOWCOUNT" in ''|*[!0-9]*) return 1 ;; esac
    case "$AGF_TIER" in ''|HIGH|MID|LOW) ;; *) return 1 ;; esac
    return 0
}

agf_state_save() {
    printf '%s %s %s %s\n' "$AGF_PREV_TOTAL" "$AGF_PREV_LOW" "$AGF_LOWCOUNT" "$AGF_TIER" \
        > "$AGF_STATE_FILE" 2>/dev/null
    return 0
}

# Tick adaptive GPU floor. Dipanggil loop utama; boost non-aktif
# langsung return 0 tanpa baca/tulis apa pun.
agf_tick() {
    [ -f "$GB_ACTIVE_FILE" ] || return 0
    [ "$(tr -d '[:space:]' < "$GB_ACTIVE_FILE" 2>/dev/null)" = "1" ] || return 0
    agf_load_limits

    # Profil aktif = plafon tier. current_state (hasil apply)
    # menang, active_profile (pilihan manual user) cadangan.
    agf_prof=""
    if [ -f "$CURRENT_STATE_FILE" ]; then
        agf_prof=$(tr -d '[:space:]' < "$CURRENT_STATE_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    fi
    case "$agf_prof" in
        performance|balanced|battery) ;;
        *)
            agf_prof=$(get_manual_profile)
            ;;
    esac
    # Daily/battery = adaptive OFF (profilnya tak mengunci floor).
    [ "$agf_prof" = "battery" ] && return 0
    agf_floor_pct_v=$(agf_floor_pct "$agf_prof") || {
        agf_log_once floor SKIPPED "GPU_AGF: floor profil $agf_prof tak terbaca dari profiles.sh, adaptive mati"
        return 0
    }
    [ "$agf_floor_pct_v" -gt 0 ] 2>/dev/null || return 0

    agf_node=$(agf_find_gpu_node) || {
        agf_log_once nostat SKIPPED "GPU_AGF: node devfreq GPU *gpu*/*mali* dengan trans_stat tak ada, adaptive mati"
        return 0
    }
    if [ ! -w "$agf_node/min_freq" ]; then
        agf_log_once ro SKIPPED "GPU_AGF: min_freq ${agf_node##*/} tak writable, adaptive mati"
        return 0
    fi
    agf_table=$(tr ' ' '\n' < "$agf_node/available_frequencies" 2>/dev/null | grep -E '^[0-9]+$' | sort -n)
    # Tabel = daftar rung (satu per baris); cukup dua rung valid agar
    # ada rangkit untuk disnap (satu rung = tabel tak berguna).
    agf_hw_max=$(printf '%s\n' "$agf_table" | tail -n 1)
    agf_low_rung=$(printf '%s\n' "$agf_table" | head -n 1)
    case "$agf_hw_max" in ''|*[!0-9]*) agf_hw_max="" ;; esac
    case "$agf_low_rung" in ''|*[!0-9]*) agf_low_rung="" ;; esac
    if [ -z "$agf_hw_max" ] || [ "$agf_low_rung" = "$agf_hw_max" ]; then
        agf_log_once ro SKIPPED "GPU_AGF: available_frequencies ${agf_node##*/} tak terbaca, adaptive mati"
        return 0
    fi

    agf_state_load
    agf_now=$(agf_read_trans "$agf_node/trans_stat") || {
        monitor_log "SKIPPED" "GPU_AGF: trans_stat ${agf_node##*/} tak terbaca, tick dilewati"
        return 0
    }
    agf_low_now=${agf_now%% *}
    agf_total_now=${agf_now##* }
    agf_delta_total=$((agf_total_now - AGF_PREV_TOTAL))
    agf_delta_low=$((agf_low_now - AGF_PREV_LOW))
    AGF_PREV_TOTAL="$agf_total_now"
    AGF_PREV_LOW="$agf_low_now"
    if [ "$agf_delta_total" -le 0 ] 2>/dev/null; then
        agf_state_save
        return 0
    fi
    agf_busy=$(( 100 * (agf_delta_total - agf_delta_low) / agf_delta_total ))

    # Tier dari beban.
    if [ "$agf_busy" -ge "$AGF_HIGH_PCT" ] 2>/dev/null; then
        agf_want=HIGH
    elif [ "$agf_busy" -ge "$AGF_MID_PCT" ] 2>/dev/null; then
        agf_want=MID
    else
        agf_want=LOW
    fi
    # Thermal override: >= ambang high loop -> paksa LOW seketika
    # (melewati hysteresis; menurunkan floor selalu arah aman).
    agf_temp=$(gb_safety_check)
    if [ "$agf_temp" -ge "$GB_HIGH_THR" ] 2>/dev/null; then
        # Log cukup sekali per episode panas (tiap tick = 2s).
        [ "$AGF_TIER" = "LOW" ] || \
            monitor_log "GAMEBOOST" "GPU_AGF: temp ${agf_temp}mC >= ${GB_HIGH_THR}mC, tier dipaksa LOW"
        AGF_NEXT_TIER=LOW
        AGF_LOWCOUNT=0
    else
        agf_apply_hysteresis "$agf_want"
    fi
    # Kunci tier hasil ke state (penanda tier aktif buat tick berikutnya
    # menakar naik/turun). Tanpa ini tier selalu kosong dan hysteresis
    # tak pernah melayani drop.
    AGF_TIER="$AGF_NEXT_TIER"

    # Target tier = persen dari plafon profil aktif.
    case "$AGF_NEXT_TIER" in
        HIGH) agf_tier_pct=100 ;;
        MID) agf_tier_pct="$AGF_MID_TIER_PCT" ;;
        *) agf_tier_pct=0 ;;
    esac
    agf_ceiling=$(agf_opp_floor "$(( (agf_hw_max / 100) * agf_floor_pct_v ))" "$agf_table")
    if [ -n "$agf_ceiling" ] && [ "$agf_tier_pct" -gt 0 ] 2>/dev/null; then
        agf_target=$(agf_opp_floor "$(( (agf_ceiling / 100) * agf_tier_pct ))" "$agf_table")
    else
        # LOW: lepas floor ke rung terbawah (bukan skip) supaya kunci
        # tier atas beneran hilang.
        agf_target=$(printf '%s\n' "$agf_table" | head -n 1)
    fi
    # Plafon keras: tak boleh di atas max_freq yang lagi berlaku
    # (profile bisa sedang mengunci ceiling lebih rendah).
    if [ -r "$agf_node/max_freq" ]; then
        agf_max_live=$(tr -d '[:space:]' < "$agf_node/max_freq" 2>/dev/null)
        case "$agf_max_live" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$agf_max_live" -gt 0 ] 2>/dev/null && [ "$agf_max_live" -lt "$agf_hw_max" ] 2>/dev/null; then
                    agf_max_live=$(agf_opp_floor "$agf_max_live" "$agf_table")
                    if [ -n "$agf_max_live" ] && [ "$agf_max_live" -lt "$agf_target" ] 2>/dev/null; then
                        agf_target="$agf_max_live"
                    fi
                fi
                ;;
        esac
    fi
    case "$agf_target" in ''|*[!0-9]*) return 0 ;; esac
    [ -f "$GB_ACTIVE_FILE" ] || return 0
    [ "$(tr -d '[:space:]' < "$GB_ACTIVE_FILE" 2>/dev/null)" = "1" ] || return 0
    agf_state_save
    agf_cur_min=$(tr -d '[:space:]' < "$agf_node/min_freq" 2>/dev/null)
    if [ "$agf_cur_min" = "$agf_target" ]; then
        return 0
    fi
    if command -v _gb_write >/dev/null 2>&1; then
        _gb_write "$agf_node/min_freq" "$agf_target" "GPU_AGF"
    else
        printf '%s' "$agf_target" > "$agf_node/min_freq" 2>/dev/null
        agf_rb=$(tr -d '[:space:]' < "$agf_node/min_freq" 2>/dev/null)
        if [ "$agf_rb" = "$agf_target" ]; then
            monitor_log "APPLIED" "GPU_AGF: min_freq ${agf_node##*/}=$agf_target (tier=$AGF_NEXT_TIER busy=${agf_busy}% ceil=$agf_ceiling)"
        else
            monitor_log "SKIPPED" "GPU_AGF: min_freq ${agf_node##*/} tak menerima $agf_target (readback=${agf_rb:-kosong})"
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
        EVENT_ON_SECS=$((EVENT_ON_SECS + 2))
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
        # Adaptive GPU floor: tier dari delta beban, self-guard boost aktif
        agf_tick
        # DAILY: anti-lag guard (loadavg)
        check_daily_loadavg_guard
        sleep 2
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

        monitor_screen_state=$(get_screen_state)
        if [ "$?" -ne 0 ]; then
            monitor_log "WARNING" "dumpsys power failed; skipping cycle=$monitor_cycle"
            sleep "$SCREEN_OFF_INTERVAL"
            continue
        fi

        if [ "$monitor_screen_state" != "ON" ]; then
            sleep "$SCREEN_OFF_INTERVAL"
            continue
        fi

        monitor_foreground_package=$(get_foreground_package)
        if [ "$?" -ne 0 ] || [ -z "$monitor_foreground_package" ]; then
            monitor_log "WARNING" "foreground package unavailable; skipping cycle=$monitor_cycle"
            sleep "$SCREEN_ON_INTERVAL"
            continue
        fi

        monitor_poll_interval="$SCREEN_ON_INTERVAL"
        if [ -n "$(get_game_profile "$monitor_foreground_package")" ]; then
            monitor_poll_interval="$GAME_POLL_INTERVAL_SECS"
        fi

        handle_foreground_event "$monitor_foreground_package" "poll"

        # GameBoost: check grace period + thermal safety
        check_gb_grace_period
        # Adaptive GPU floor: tier dari delta beban, self-guard boost aktif
        agf_tick
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
