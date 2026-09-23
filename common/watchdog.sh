#!/system/bin/sh
# Alpha v1 - monitor.sh watchdog (cron-like ringan)
# Loop tidur + cek pidfile tiap ALPHA_WATCHDOG_INTERVAL (default 180s).
# Kalau monitor.sh mati di luar skenario normal, start ulang otomatis
# persis seperti service.sh (bukan nunggu reboot). Satu-satunya proses
# tambahan: satu sleep loop (ppid 1), nyaris nol overhead.

WATCHDIR="${0%/*}"
STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
WD_PID_FILE="$STATE_DIR/watchdog.pid"
MON_PID_FILE="$STATE_DIR/monitor.pid"
WD_INTERVAL="${ALPHA_WATCHDOG_INTERVAL:-180}"
WD_LOG="${ALPHA_LOG_FILE:-$STATE_DIR/alpha.log}"
WD_STOP=0

wd_log() {
    wd_time=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    printf '%s\n' "[$wd_time] [WATCHDOG] [$1] $2" >> "$WD_LOG" 2>/dev/null
}

wd_cleanup() {
    if [ -f "$WD_PID_FILE" ] && [ "$(cat "$WD_PID_FILE" 2>/dev/null)" = "$$" ]; then
        rm -f "$WD_PID_FILE"
    fi
    WD_STOP=1
}

trap wd_cleanup TERM INT HUP
trap wd_cleanup EXIT

mkdir -p "$STATE_DIR" 2>/dev/null || exit 1

if [ -f "$WD_PID_FILE" ]; then
    wd_old=$(tr -d '[:space:]' < "$WD_PID_FILE" 2>/dev/null)
    if [ -n "$wd_old" ] && [ "$wd_old" != "$$" ] && [ -r "/proc/$wd_old/cmdline" ]; then
        wd_cmd=$(tr '\000' ' ' < "/proc/$wd_old/cmdline" 2>/dev/null)
        case "$wd_cmd" in
            *watchdog.sh*)
                wd_log "SKIPPED" "watchdog already running pid=$wd_old"
                exit 0
                ;;
        esac
    fi
    rm -f "$WD_PID_FILE"
fi

printf '%s\n' "$$" > "$WD_PID_FILE" || exit 1
wd_log "START" "watchdog pid=$$ interval=${WD_INTERVAL}s"

while [ "$WD_STOP" -eq 0 ]; do
    sleep "$WD_INTERVAL" 2>/dev/null || sleep 180
    [ "$WD_STOP" -eq 0 ] || break
    mon_ok=0
    if [ -f "$MON_PID_FILE" ]; then
        mon_pid=$(tr -d '[:space:]' < "$MON_PID_FILE" 2>/dev/null)
        if [ -n "$mon_pid" ] && [ -r "/proc/$mon_pid/cmdline" ]; then
            mon_cmd=$(tr '\000' ' ' < "/proc/$mon_pid/cmdline" 2>/dev/null)
            case "$mon_cmd" in
                *monitor.sh*) mon_ok=1 ;;
            esac
        fi
    fi
    if [ "$mon_ok" -ne 1 ]; then
        wd_log "RESTART" "monitor.sh mati/hilang, start ulang"
        rm -f "$MON_PID_FILE" 2>/dev/null
        ALPHA_STATE_DIR="$STATE_DIR"
        ALPHA_LOG_FILE="${ALPHA_LOG_FILE:-$STATE_DIR/alpha.log}"
        ALPHA_CONF_DIR="${ALPHA_CONF_DIR:-$STATE_DIR}"
        export ALPHA_STATE_DIR ALPHA_LOG_FILE ALPHA_CONF_DIR
        nohup sh "$WATCHDIR/monitor.sh" >> "$WD_LOG" 2>&1 &
        wd_new=$!
        printf '%s\n' "$wd_new" > "$MON_PID_FILE"
        # B27 OOM-GUARD: hasil restart ikut dilindungi (launcher-side,
        # berlaku untuk .sh maupun .bin karena operasi pada pid).
        if [ -n "$wd_new" ] && [ -w "/proc/$wd_new/oom_score_adj" ]; then
            if echo -1000 > "/proc/$wd_new/oom_score_adj" 2>/dev/null; then
                wd_log "OOM-GUARD" "monitor.sh pid=$wd_new adj=-1000"
            else
                wd_log "OOM-GUARD" "WARN: monitor.sh pid=$wd_new gagal"
            fi
        fi
        wd_log "RESTART" "monitor.sh started pid=$wd_new"
    fi
done

wd_log "STOP" "watchdog stopped"
exit 0
