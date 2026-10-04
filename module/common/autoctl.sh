#!/system/bin/sh
# Alpha Fusion - autoctl: daemon ringan untuk fitur aplikasi.
#  1. Auto-profile: aturan baterai rendah / sedang charging (dari app.conf)
#  2. Statistik sesi game: durasi, suhu puncak, baterai -> sessions.log
# Satu loop sleep (default 10 dtk), tanpa fork berat saat tidak ada game.
# Game sendiri tetap diurus monitor.sh; di sini profil TIDAK diganti selama game aktif.

STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
COMMON="${0%/*}"
PID_FILE="$STATE_DIR/autoctl.pid"
CONF_FILE="$STATE_DIR/app.conf"
LOG_FILE="${ALPHA_LOG_FILE:-$STATE_DIR/alpha.log}"
SES_FILE="$STATE_DIR/sessions.log"
PREV_FILE="$STATE_DIR/.auto_prev"
MARK_FILE="$STATE_DIR/.auto_applied"
INTERVAL="${ALPHA_AUTOCTL_INTERVAL:-10}"
SYS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
SYS_POWER="${SYSFS_POWER_PREFIX:-/sys/class/power_supply}"
MAX_TICKS="${ALPHA_AUTOCTL_MAX_TICKS:-0}"
SES_MIN_SECS="${ALPHA_SES_MIN_SECS:-60}"
STOP=0

alog() {
    _t=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    printf '%s\n' "[$_t] [AUTOCTL] [$1] $2" >> "$LOG_FILE" 2>/dev/null
}

cleanup() {
    if [ -f "$PID_FILE" ] && [ "$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null)" = "$$" ]; then
        rm -f "$PID_FILE"
    fi
    STOP=1
}
trap cleanup TERM INT HUP
trap cleanup EXIT

mkdir -p "$STATE_DIR" 2>/dev/null || exit 1

# satu instance saja
if [ -f "$PID_FILE" ]; then
    _o=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null)
    if [ -n "$_o" ] && [ "$_o" != "$$" ] && [ -r "/proc/$_o/cmdline" ]; then
        case "$(tr '\000' ' ' < "/proc/$_o/cmdline" 2>/dev/null)" in
            *autoctl.sh*) exit 0 ;;
        esac
    fi
    rm -f "$PID_FILE"
fi
printf '%s\n' "$$" > "$PID_FILE" || exit 1
alog "START" "autoctl pid=$$ interval=${INTERVAL}s"

rdf() { [ -r "$1" ] && tr -d '\r\n' < "$1" 2>/dev/null; }

conf_get() {
    _v=""
    [ -f "$CONF_FILE" ] && _v=$(sed -n "s/^$1=//p" "$CONF_FILE" 2>/dev/null | tail -n 1)
    [ -n "$_v" ] && printf '%s' "$_v" || printf '%s' "$2"
}

valid_profile() { case "$1" in battery|balanced|performance) return 0 ;; *) return 1 ;; esac; }

# suhu baterai (mC), dipakai untuk puncak sesi. Fallback ke sensor terpanas bila node tidak ada.
batt_temp_mc() {
    _bt=$(rdf "$SYS_POWER/battery/temp")
    case "$_bt" in ''|*[!0-9]*) max_temp_mc; return ;; esac
    printf '%s' $((_bt * 100))
}

max_temp_mc() {
    _max=0
    for _z in "$SYS_THERMAL"/thermal_zone*; do
        [ -r "$_z/temp" ] || continue
        if command -v timeout >/dev/null 2>&1; then
            _v=$(timeout 1 cat "$_z/temp" 2>/dev/null | tr -d '[:space:]')
        else
            _v=$(tr -d '[:space:]' < "$_z/temp" 2>/dev/null)
        fi
        case "$_v" in ''|*[!0-9-]*) continue ;; esac
        [ "${_v#-}" -le 1000 ] 2>/dev/null && _v=$((_v * 1000))
        [ "$_v" -ge 0 ] 2>/dev/null || continue
        [ "$_v" -lt 125000 ] 2>/dev/null || continue
        [ "$_v" -gt "$_max" ] && _max=$_v
    done
    printf '%s' "$_max"
}

apply_profile() {
    sh "$COMMON/apply_now.sh" "$1" manual >> "$LOG_FILE" 2>&1
}

# ---------- auto-profile ----------
auto_rules_tick() {
    # selama game aktif, monitor.sh yang memutuskan
    [ -f "$STATE_DIR/.game_t0" ] && return 0

    _cap=$(rdf "$SYS_POWER/battery/capacity")
    _st=$(rdf "$SYS_POWER/battery/status")
    case "$_cap" in ''|*[!0-9]*) _cap=100 ;; esac
    _charging=0
    case "$_st" in Charging|Full) _charging=1 ;; esac

    _want=""
    if [ "$(conf_get AUTO_BATT_ON 0)" = "1" ] && [ "$_charging" = "0" ]; then
        _pct=$(conf_get AUTO_BATT_PCT 20)
        case "$_pct" in ''|*[!0-9]*) _pct=20 ;; esac
        if [ "$_cap" -le "$_pct" ] 2>/dev/null; then
            _want=$(conf_get AUTO_BATT_PROFILE battery)
            reason="baterai ${_cap}% <= ${_pct}%"
        fi
    fi
    if [ -z "$_want" ] && [ "$(conf_get AUTO_CHG_ON 0)" = "1" ] && [ "$_charging" = "1" ]; then
        _want=$(conf_get AUTO_CHG_PROFILE balanced)
        reason="charging"
    fi
    [ -n "$_want" ] && ! valid_profile "$_want" && _want=""

    _mark=$(rdf "$MARK_FILE")
    if [ -n "$_want" ]; then
        # hanya saat transisi: tidak menimpa pilihan manual user selama kondisi bertahan
        if [ "$_mark" != "$_want" ]; then
            if [ ! -f "$PREV_FILE" ]; then
                _prev=$(rdf "$STATE_DIR/active_profile")
                valid_profile "$_prev" || _prev=$(rdf "$STATE_DIR/current_state")
                valid_profile "$_prev" && printf '%s\n' "$_prev" > "$PREV_FILE"
            fi
            apply_profile "$_want"
            printf '%s\n' "$_want" > "$MARK_FILE"
            alog "RULE" "profil -> $_want ($reason)"
        fi
    elif [ -n "$_mark" ]; then
        # kondisi selesai: kembalikan pilihan lama jika user tidak mengubahnya
        _prev=$(rdf "$PREV_FILE")
        _now=$(rdf "$STATE_DIR/active_profile")
        rm -f "$MARK_FILE" "$PREV_FILE" 2>/dev/null
        if valid_profile "$_prev" && [ "$_now" = "$_mark" ]; then
            apply_profile "$_prev"
            alog "RULE" "kondisi selesai, profil kembali ke $_prev"
        fi
    fi
}

# ---------- statistik sesi game ----------
SES_PKG=""; SES_T0=0; SES_PEAK=0; SES_B0=0; SES_EPOCH=0

ses_tick() {
    if [ -f "$STATE_DIR/.game_t0" ]; then
        read -r _t0 _pkg < "$STATE_DIR/.game_t0" 2>/dev/null
        if [ -z "$SES_PKG" ] || [ "$SES_PKG" != "$_pkg" ]; then
            [ -n "$SES_PKG" ] && ses_end
            SES_PKG="$_pkg"
            SES_T0=$(cut -d. -f1 /proc/uptime 2>/dev/null)
            SES_EPOCH=$(date +%s 2>/dev/null)
            SES_PEAK=0
            SES_B0=$(rdf "$SYS_POWER/battery/capacity")
            case "$SES_B0" in ''|*[!0-9]*) SES_B0=0 ;; esac
        fi
        _tm=$(batt_temp_mc)
        [ "$_tm" -gt "$SES_PEAK" ] 2>/dev/null && SES_PEAK=$_tm
    elif [ -n "$SES_PKG" ]; then
        ses_end
    fi
}

ses_end() {
    _up=$(cut -d. -f1 /proc/uptime 2>/dev/null)
    _dur=$((_up - SES_T0))
    _b1=$(rdf "$SYS_POWER/battery/capacity")
    case "$_b1" in ''|*[!0-9]*) _b1=$SES_B0 ;; esac
    _prof=$(rdf "$STATE_DIR/current_state")
    if [ "$_dur" -ge "$SES_MIN_SECS" ] 2>/dev/null; then
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$SES_EPOCH" "$SES_PKG" "$_dur" "$SES_PEAK" "$SES_B0" "$_b1" "${_prof:-?}" >> "$SES_FILE"
        if [ "$(wc -l < "$SES_FILE" 2>/dev/null)" -gt 60 ] 2>/dev/null; then
            tail -n 40 "$SES_FILE" > "$SES_FILE.tmp.$$" && mv -f "$SES_FILE.tmp.$$" "$SES_FILE"
        fi
        alog "SESSION" "pkg=$SES_PKG dur=${_dur}s peak=${SES_PEAK}mC batt=${SES_B0}->${_b1}"
    fi
    SES_PKG=""; SES_PEAK=0
}

ticks=0
while [ "$STOP" -eq 0 ]; do
    auto_rules_tick
    ses_tick
    ticks=$((ticks + 1))
    if [ "$MAX_TICKS" -gt 0 ] 2>/dev/null && [ "$ticks" -ge "$MAX_TICKS" ]; then break; fi
    sleep "$INTERVAL" 2>/dev/null || sleep 10
done
[ -n "$SES_PKG" ] && ses_end
alog "STOP" "autoctl stopped"
exit 0
