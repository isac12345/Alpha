#!/system/bin/sh
# Alpha Fusion - screenrec: rekam layar lewat `screenrecord` bawaan Android (root, tanpa dialog izin).
#
#   screenrec.sh start     mulai merekam (sambung otomatis per 180 dtk, satu file per potongan)
#   screenrec.sh stop      berhenti dan tutup file dengan benar
#   screenrec.sh status    running=1|0, file=<potongan sekarang>, dir=<folder>
#   screenrec.sh list [N]  N file rekaman terbaru
#
# Hasil: /sdcard/Movies/Alpha/Alpha_<tanggal>_<jam>_p<n>.mp4 (tanpa audio; screenrecord tidak
# bisa merekam audio internal). Bitrate dari conf REC_BITRATE_MBPS (default 8, rentang 2-40).
# Ada jeda sekitar setengah detik antar potongan.

STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
CONF_FILE="$STATE_DIR/app.conf"
PID_FILE="$STATE_DIR/.rec_pid"
STOP_FILE="$STATE_DIR/.rec_stop"
CUR_FILE="$STATE_DIR/.rec_file"
OUT_DIR="${ALPHA_REC_DIR:-/sdcard/Movies/Alpha}"
SEG_SECS="${ALPHA_REC_SEG:-180}"
SELF="$(readlink -f "$0")"

rec_alive() {
    [ -f "$PID_FILE" ] || return 1
    _ra=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null)
    [ -n "$_ra" ] || return 1
    kill -0 "$_ra" 2>/dev/null || return 1
    [ -r "/proc/$_ra/cmdline" ] || return 1
    case "$(tr '\000' ' ' < "/proc/$_ra/cmdline" 2>/dev/null)" in *screenrec.sh*) return 0 ;; esac
    return 1
}

bitrate() {
    _b=""
    [ -f "$CONF_FILE" ] && _b=$(sed -n 's/^REC_BITRATE_MBPS=//p' "$CONF_FILE" 2>/dev/null | tail -n 1)
    case "$_b" in ''|*[!0-9]*) _b=8 ;; esac
    [ "$_b" -ge 2 ] 2>/dev/null && [ "$_b" -le 40 ] 2>/dev/null || _b=8
    printf '%s' $((_b * 1000000))
}

# Dijalankan di latar belakang oleh `start`.
rec_loop() {
    echo "$$" > "$PID_FILE"
    mkdir -p "$OUT_DIR" 2>/dev/null
    _n=1
    _br=$(bitrate)
    _fail=0
    while [ ! -f "$STOP_FILE" ]; do
        _f="$OUT_DIR/Alpha_$(date '+%Y%m%d_%H%M%S')_p$_n.mp4"
        printf '%s\n' "$_f" > "$CUR_FILE"
        _t0=$(cut -d. -f1 /proc/uptime 2>/dev/null)
        screenrecord --bit-rate "$_br" --time-limit "$SEG_SECS" "$_f" >/dev/null 2>&1
        _t1=$(cut -d. -f1 /proc/uptime 2>/dev/null)
        am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$_f" >/dev/null 2>&1
        # screenrecord langsung gagal (mis. layar terkunci / DRM / binary tidak ada): jangan putar tanpa henti
        if [ -n "$_t0" ] && [ -n "$_t1" ] && [ $((_t1 - _t0)) -lt 2 ]; then
            _fail=$((_fail + 1))
            [ "$_fail" -ge 3 ] && break
            sleep 1
        else
            _fail=0
        fi
        _n=$((_n + 1))
    done
    rm -f "$PID_FILE" "$STOP_FILE" "$CUR_FILE"
}

rec_start() {
    command -v screenrecord >/dev/null 2>&1 || { echo "ERROR: screenrecord tidak ada di perangkat ini"; return 1; }
    if rec_alive; then echo "OK: sudah merekam"; return 0; fi
    rm -f "$STOP_FILE" "$PID_FILE"
    nohup sh "$SELF" _loop >/dev/null 2>&1 &
    sleep 1
    if rec_alive; then echo "OK: merekam ke $OUT_DIR"; else echo "ERROR: gagal memulai rekaman"; return 1; fi
}

rec_sig() {
    for _p in $(pidof screenrecord 2>/dev/null); do kill "-$1" "$_p" 2>/dev/null; done
}

rec_wait_exit() {
    _i=0
    while rec_alive && [ "$_i" -lt "$1" ]; do sleep 0.5; _i=$((_i + 1)); done
}

rec_stop() {
    if ! rec_alive; then
        rm -f "$PID_FILE" "$STOP_FILE" "$CUR_FILE"
        echo "OK: tidak sedang merekam"
        return 0
    fi
    : > "$STOP_FILE"
    # screenrecord menutup mp4 dengan benar hanya lewat SIGINT/SIGHUP (bukan SIGTERM)
    rec_sig 2
    rec_wait_exit 6
    if rec_alive; then rec_sig 1; rec_wait_exit 6; fi
    if rec_alive; then kill "$(tr -d '[:space:]' < "$PID_FILE")" 2>/dev/null; fi
    rm -f "$PID_FILE" "$STOP_FILE" "$CUR_FILE"
    echo "OK: rekaman berhenti, folder $OUT_DIR"
}

rec_status() {
    if rec_alive; then echo "running=1"; else echo "running=0"; fi
    printf 'file=%s\n' "$(cat "$CUR_FILE" 2>/dev/null)"
    printf 'dir=%s\n' "$OUT_DIR"
}

rec_list() {
    _n="${1:-10}"
    case "$_n" in ''|*[!0-9]*) _n=10 ;; esac
    [ -d "$OUT_DIR" ] || return 0
    ls -t "$OUT_DIR" 2>/dev/null | head -n "$_n"
}

case "$1" in
    start) rec_start ;;
    stop) rec_stop ;;
    status) rec_status ;;
    list) rec_list "$2" ;;
    _loop) rec_loop ;;
    *) sed -n '2,12p' "$0" ;;
esac
