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
MAX_CYCLES="${ALPHA_MONITOR_MAX_CYCLES:-0}"
# Health-check event stream: kalau layar sudah nyala selama
# EVENT_HEALTH_SECS tapi NOL event ter-parse jadi package, filter event
# dianggap tidak cocok dengan ROM ini -> turun ke polling permanen
# untuk sisa proses (satu keputusan per boot, hemat resource).
EVENT_HEALTH_SECS="${ALPHA_EVENT_HEALTH_SECS:-45}"
EVENT_COUNT_FILE="$STATE_DIR/.foreground-events.$$.count"
EVENT_ON_SECS=0
EVENT_FALLBACK_DONE=0
EVENT_HEALTH_LOGGED=0
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

monitor_log() {
    monitor_log_status="$1"
    monitor_log_message="$2"
    monitor_log_time=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    printf '%s\n' "[$monitor_log_time] [MONITOR] [$monitor_log_status] $monitor_log_message" >> "$LOG_FILE" 2>/dev/null
}

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
    [ "$handle_target" = "$handle_current" ] && return 0
    if [ "$handle_source" = "event" ]; then
        monitor_log "APPLY-EVENT" "package=$handle_pkg target=$handle_target current=${handle_current:-none}"
    else
        monitor_log "APPLY-POLL" "package=$handle_pkg target=$handle_target current=${handle_current:-none}"
    fi
    if sh "$MODDIR/apply_now.sh" "$handle_target" monitor >> "$LOG_FILE" 2>&1; then
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
        case "$event_line" in
            *wm_set_resumed_activity*|*wm_set_top_resumed_activity*|*wm_top_resumed*|*wm_resume_activity*|*wm_on_resume_called*|*wm_on_top_resumed_called*|*am_focused_activity*|*am_on_resume_called*|*minimalResumeActivityLocked*|*Focus\ entering*) ;;
            *) continue ;;
        esac
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
        # Health-check REAL (bukan sekadar "process started"): akumulasi
        # detik layar-nyala. Kalau jendela health sudah lewat tapi NOL
        # event ter-parse, filter tidak cocok dengan ROM ini -> polling
        # permanen sisa sesi (satu keputusan per boot, hemat resource).
        # Layar-mati tidak dihitung, jadi "sepi karena idle" tidak
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

        handle_foreground_event "$monitor_foreground_package" "poll"

        sleep "$SCREEN_ON_INTERVAL"
    done
    return 0
}

check_notify_available
if command -v logcat >/dev/null 2>&1 && command -v mkfifo >/dev/null 2>&1 && logcat -b events -v raw -d -t 3 >/dev/null 2>&1; then
    MONITOR_METHOD="event-driven"
    monitor_log "START" "monitor pid=$$ method=event-driven health=${EVENT_HEALTH_SECS}s interval_on=${SCREEN_ON_INTERVAL}s interval_off=${SCREEN_OFF_INTERVAL}s"
    run_event_supervised_loop
else
    MONITOR_METHOD="polling"
    monitor_log "START" "monitor pid=$$ method=polling reason=logcat-events-unavailable interval_on=${SCREEN_ON_INTERVAL}s interval_off=${SCREEN_OFF_INTERVAL}s"
    run_polling_loop
fi

monitor_log "STOP" "monitor stopped"
exit 0
