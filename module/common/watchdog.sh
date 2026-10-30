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

BUBBLE_WANT="$STATE_DIR/.bubble_want"
BUBBLE_PKG="com.alphabubble"
BUBBLE_TICK="${ALPHA_BUBBLE_TICK:-45}"
wd_n=0
wd_per=$((WD_INTERVAL / BUBBLE_TICK)); [ "$wd_per" -ge 1 ] || wd_per=1

# Floating/HUD harus hidup lagi tanpa membuka app: kalau app menandai ingin aktif (.bubble_want)
# tetapi service-nya mati (dibunuh pembersih ROM), start ulang lewat root (lolos batas background).
bubble_revive() {
    [ -f "$BUBBLE_WANT" ] || return 0
    command -v am >/dev/null 2>&1 || return 0
    _up=0
    if [ -n "$(pidof "$BUBBLE_PKG" 2>/dev/null)" ]; then
        dumpsys activity services "$BUBBLE_PKG/.BubbleService" 2>/dev/null | grep -q 'ServiceRecord' && _up=1
    fi
    [ "$_up" -eq 1 ] && return 0
    am start-foreground-service -n "$BUBBLE_PKG/.BubbleService" >/dev/null 2>&1 \
        || am startservice -n "$BUBBLE_PKG/.BubbleService" >/dev/null 2>&1
    wd_log REVIVE "floating mati, service dihidupkan ulang"
}

while [ "$WD_STOP" -eq 0 ]; do
    sleep "$BUBBLE_TICK" 2>/dev/null || sleep 45
    [ "$WD_STOP" -eq 0 ] || break
    bubble_revive
    wd_n=$((wd_n + 1))
    [ "$wd_n" -ge "$wd_per" ] || continue
    wd_n=0
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
        wd_log "RESTART" "monitor.sh started pid=$wd_new"
    fi
done

wd_log "STOP" "watchdog stopped"
exit 0
