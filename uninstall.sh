#!/system/bin/sh
# Alpha + Uperf Fusion - Uninstall Cleanup

# --- Alpha cleanup ---
WORK_DIR="${ALPHA_WORK_DIR:-/data/adb/alpha}"
PID_FILE="$WORK_DIR/monitor.pid"

if [ -f "$PID_FILE" ]; then
    monitor_pid=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null)
    if [ -n "$monitor_pid" ] && kill -0 "$monitor_pid" 2>/dev/null; then
        if [ -r "/proc/$monitor_pid/cmdline" ]; then
            monitor_cmd=$(tr '\000' ' ' < "/proc/$monitor_pid/cmdline" 2>/dev/null)
            case "$monitor_cmd" in
                *monitor.sh*)
                    kill "$monitor_pid" 2>/dev/null
                    echo "[UNINSTALL] monitor.sh killed pid=$monitor_pid"
                    ;;
            esac
        fi
    fi
    rm -f "$PID_FILE" 2>/dev/null
    echo "[UNINSTALL] monitor.pid removed"
fi

# --- Uperf backend cleanup (kept minimal & non-blocking) ---
UPERF_USER_PATH="/sdcard/Android/yc/uperf"

uperf_on_remove() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 1
    done
    local test_file="/sdcard/Android/.PERMISSION_TEST"
    true > "$test_file" 2>/dev/null
    while [ ! -f "$test_file" ]; do
        true > "$test_file" 2>/dev/null
        sleep 1
    done
    rm -f "$test_file"

    killall uperf 2>/dev/null
    # simpan perapp config user, hapus sisanya
    if [ -d "$UPERF_USER_PATH" ]; then
        cp -af "$UPERF_USER_PATH/perapp_powermode.txt" /sdcard/ 2>/dev/null
        rm -rf "$UPERF_USER_PATH"
        mkdir -p "$UPERF_USER_PATH"
        mv -f /sdcard/perapp_powermode.txt "$UPERF_USER_PATH/" 2>/dev/null
    fi
}
# jangan blokir proses uninstall/boot
(uperf_on_remove &)

# --- fas-rs cleanup (mengikuti uninstall.sh asli fas-rs) ---
FASRS_DIR="/sdcard/Android/fas-rs"
fasrs_on_remove() {
    until [ -d "$FASRS_DIR" ] && [ -d /data ]; do
        sleep 1
    done
    killall fas-rs 2>/dev/null
    rm -rf "$FASRS_DIR"
    rm -f /data/powercfg.json
    rm -f /data/powercfg.sh
}
(fasrs_on_remove &)

echo "[UNINSTALL] Alpha + Uperf + fas-rs Fusion cleanup complete"
