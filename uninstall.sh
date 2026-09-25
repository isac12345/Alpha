#!/system/bin/sh
# Alpha + Uperf Fusion - Uninstall Cleanup

# --- Alpha cleanup ---
WORK_DIR="${ALPHA_WORK_DIR:-/data/adb/alpha}"

# modul31: hentikan daemon Alpha (monitor + watchdog + pgr-log) via
# kecocokan cmdline, JANGAN bunuh PID buta (pid bisa dipakai ulang).
_alpha_kill_pat() {
    _pat="$1"
    for _pidf in "$WORK_DIR/monitor.pid" "$WORK_DIR/watchdog.pid"; do
        [ -f "$_pidf" ] || continue
        _p=$(tr -d '[:space:]' < "$_pidf" 2>/dev/null)
        [ -n "$_p" ] || continue
        if kill -0 "$_p" 2>/dev/null && [ -r "/proc/$_p/cmdline" ]; then
            _cmd=$(tr '\000' ' ' < "/proc/$_p/cmdline" 2>/dev/null)
            case "$_cmd" in
                *"${_pat}"*)
                    kill "$_p" 2>/dev/null
                    echo "[UNINSTALL] ${_pat} killed pid=$_p"
                    ;;
            esac
        fi
    done
    unset _pat _pidf _p _cmd
}
_alpha_kill_pat "monitor.sh"
_alpha_kill_pat "watchdog.sh"
_alpha_kill_pat "pgr-log"
rm -f "$WORK_DIR/monitor.pid" "$WORK_DIR/watchdog.pid" 2>/dev/null
echo "[UNINSTALL] pid files removed"

# modul31: kembalikan nilai native (best-effort, tanpa gagal).
# Setelah uninstall + reboot kernel kembali default sendiri; ini hanya
# melepas kunci boost SEKARANG supaya tidak nyangkut sampai reboot.
if [ -f "${0%/*}/common/detect.sh" ]; then
    ALPHA_CONF_DIR="$WORK_DIR"
    export ALPHA_CONF_DIR
    . "${0%/*}/common/detect.sh" 2>/dev/null
fi
if [ -f "${0%/*}/common/gameboost.sh" ]; then
    ALPHA_CONF_DIR="$WORK_DIR" ALPHA_LOG_FILE="/dev/null"
    export ALPHA_CONF_DIR ALPHA_LOG_FILE
    . "${0%/*}/common/gameboost.sh" 2>/dev/null
    if command -v gb_restore >/dev/null 2>&1; then
        gb_restore >/dev/null 2>&1
        echo "[UNINSTALL] native values restored (best-effort)"
    fi
    unset ALPHA_CONF_DIR ALPHA_LOG_FILE
fi

# modul31: bersih total state Alpha. DIPERTAHANKAN hanya daftar game user
# (game_profile_map.conf = mahal dibangun ulang); sisanya transient,
# snapshot, log, cache, penanda -> hapus supaya install berikutnya fresh.
rm -f "$WORK_DIR/boost_level" "$WORK_DIR/GAMEBOOST_LEVEL" \
    "$WORK_DIR/.gb_active" "$WORK_DIR/.gb_cooldown_count" \
    "$WORK_DIR/.gb_level_orig" "$WORK_DIR/.gb_pending" \
    "$WORK_DIR/apply.lock" "$WORK_DIR/.profile_transitions.log" \
    "$WORK_DIR/.daily_loadbalanced" "$WORK_DIR/.daily_loadhigh_count" \
    "$WORK_DIR/.foreground-events" "$WORK_DIR/.foreground_last_pkg" \
    "$WORK_DIR/.hud_foreground_pkg" "$WORK_DIR/native_boost.conf" \
    "$WORK_DIR/detected.conf" "$WORK_DIR/alpha.log" \
    "$WORK_DIR/.boot_fail_count" "$WORK_DIR/active_profile" \
    "$WORK_DIR/current_state" 2>/dev/null
rm -f "$WORK_DIR"/.monitor-dumpsys.* 2>/dev/null
echo "[UNINSTALL] Alpha state cleaned (game list preserved)"

# --- Uperf backend cleanup (kept minimal & non-blocking) ---
# M6: hanya hapus config uperf/fas-rs/AsoulOpt bila penanda Alpha ada.
# JANGAN pernah hapus config modul lain.
UPERF_USER_PATH="/sdcard/Android/yc/uperf"
ALPHA_MARKER="/data/adb/alpha/.alpha_installed"

# Pastikan penanda Alpha ada (ditulis oleh customize.sh saat install)
ALPHA_OWNED=0
if [ -f "$ALPHA_MARKER" ]; then
    ALPHA_OWNED=1
fi

uperf_on_remove() {
    # modul31: tunggu bounded (maks ~60 dtk tiap tahap) supaya job latar
    # tidak menggantung selamanya bila /sdcard tak ter-mount.
    _n=0
    while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$_n" -lt 60 ]; do
        sleep 1
        _n=$((_n + 1))
    done
    local test_file="/sdcard/Android/.PERMISSION_TEST"
    true > "$test_file" 2>/dev/null
    _n=0
    while [ ! -f "$test_file" ] && [ "$_n" -lt 60 ]; do
        true > "$test_file" 2>/dev/null
        sleep 1
        _n=$((_n + 1))
    done
    rm -f "$test_file"
    unset _n

    # M6: hapus config hanya jika Alpha adalah pemilik
    if [ "$ALPHA_OWNED" = "1" ]; then
        killall uperf 2>/dev/null
        # simpan perapp config user, hapus sisanya
        if [ -d "$UPERF_USER_PATH" ]; then
            cp -af "$UPERF_USER_PATH/perapp_powermode.txt" /sdcard/ 2>/dev/null
            rm -rf "$UPERF_USER_PATH"
            mkdir -p "$UPERF_USER_PATH"
            mv -f /sdcard/perapp_powermode.txt "$UPERF_USER_PATH/" 2>/dev/null
        fi
        # hapus marker supaya tidak double-cleanup di boot berikutnya
        rm -f "$ALPHA_MARKER" 2>/dev/null
    else
        echo "[UNINSTALL] uperf config dilewati (bukan pemilik Alpha)"
    fi
}
# jangan blokir proses uninstall/boot
(uperf_on_remove &)

# --- fas-rs cleanup (mengikuti uninstall.sh asli fas-rs) ---
FASRS_DIR="/sdcard/Android/fas-rs"
fasrs_on_remove() {
    # modul31: tunggu bounded (maks ~60 dtk) supaya tak menggantung.
    _n=0
    until [ -d "$FASRS_DIR" ] && [ -d /data ]; do
        [ "$_n" -ge 60 ] && return 0
        sleep 1
        _n=$((_n + 1))
    done
    unset _n
    # M6: hapus config fas-rs HANYA bila penanda Alpha ada
    if [ "$ALPHA_OWNED" = "1" ]; then
        killall fas-rs 2>/dev/null
        rm -rf "$FASRS_DIR"
        rm -f /data/powercfg.json
        rm -f /data/powercfg.sh
    fi
}
(fasrs_on_remove &)

echo "[UNINSTALL] Alpha + Uperf + fas-rs Fusion cleanup complete"
