#!/system/bin/sh
# Alpha v1 - Apply one profile immediately

MODDIR="${0%/*}"
STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
CURRENT_STATE_FILE="$STATE_DIR/current_state"
ACTIVE_PROFILE_FILE="$STATE_DIR/active_profile"
LOCK_DIR="$STATE_DIR/apply.lock"
LOCK_OWNER_FILE="$LOCK_DIR/owner.pid"
LOG_FILE="${ALPHA_LOG_FILE:-$STATE_DIR/alpha.log}"
LOCK_TIMEOUT=10

apply_log() {
    apply_log_status="$1"
    apply_log_message="$2"
    apply_log_time=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    printf '%s\n' "[$apply_log_time] [APPLY] [$apply_log_status] $apply_log_message" >> "$LOG_FILE" 2>/dev/null
}

release_lock() {
    if [ -f "$LOCK_OWNER_FILE" ]; then
        local lock_owner
        lock_owner=$(tr -d '[:space:]' < "$LOCK_OWNER_FILE" 2>/dev/null)
        if [ "$lock_owner" = "$$" ]; then
            rm -f "$LOCK_OWNER_FILE" 2>/dev/null
            rmdir "$LOCK_DIR" 2>/dev/null
            return 0
        fi
    fi
    return 1
}

apply_cleanup() {
    release_lock
}

trap apply_cleanup TERM INT HUP
trap apply_cleanup EXIT

is_stale_lock() {
    if [ ! -d "$LOCK_DIR" ]; then
        return 1
    fi
    if [ ! -f "$LOCK_OWNER_FILE" ]; then
        return 0
    fi
    local lock_owner
    lock_owner=$(tr -d '[:space:]' < "$LOCK_OWNER_FILE" 2>/dev/null)
    if [ -z "$lock_owner" ]; then
        return 0
    fi
    if kill -0 "$lock_owner" 2>/dev/null; then
        if [ -r "/proc/$lock_owner/cmdline" ]; then
            local lock_cmd
            lock_cmd=$(tr '\000' ' ' < "/proc/$lock_owner/cmdline" 2>/dev/null)
            case "$lock_cmd" in
                *apply_now*)
                    return 1
                    ;;
            esac
        fi
        return 0
    fi
    return 0
}

cleanup_stale_lock() {
    if is_stale_lock; then
        apply_log "WARNING" "removing stale lock (owner dead or not apply_now)"
        rm -f "$LOCK_OWNER_FILE" 2>/dev/null
        rmdir "$LOCK_DIR" 2>/dev/null
        return 0
    fi
    return 1
}

apply_profile="$1"
apply_source="${2:-manual}"
if [ -z "$apply_profile" ]; then
    apply_log "ERROR" "profile argument missing"
    exit 2
fi

case "$apply_profile" in
    battery|balanced|performance)
        ;;
    *)
        apply_log "WARNING" "unknown profile=$apply_profile; load_profile will fallback to balanced"
        ;;
esac

mkdir -p "$STATE_DIR" 2>/dev/null || {
    apply_log "ERROR" "cannot create state directory: $STATE_DIR"
    exit 1
}

# Catat pilihan manual (dari tombol APK) ke active_profile SEBELUM cek
# "already current" di bawah, supaya tetap tersimpan walau kebetulan sama
# dengan current_state (mis. fresh install, atau nge-tap ulang profile
# yang sama). Panggilan dari monitor.sh (source=monitor) sengaja TIDAK
# menyentuh file ini - itu cuma re-assert/auto-switch, bukan pilihan user.
# monitor.sh membaca active_profile ini sebagai fallback saat foreground
# app bukan game yang terdaftar, jadi auto-mode balik ke pilihan manual
# terakhir, bukan hardcoded ke satu profile tertentu.
if [ "$apply_source" = "manual" ]; then
    case "$apply_profile" in
        battery|balanced|performance)
            active_tmp="$ACTIVE_PROFILE_FILE.tmp.$$"
            if printf '%s\n' "$apply_profile" > "$active_tmp" && mv -f "$active_tmp" "$ACTIVE_PROFILE_FILE" 2>/dev/null; then
                apply_log "INFO" "active_profile=$apply_profile (manual)"
            else
                rm -f "$active_tmp" 2>/dev/null
                apply_log "WARNING" "failed to record active_profile=$apply_profile"
            fi
            ;;
    esac
fi

if [ -f "$CURRENT_STATE_FILE" ]; then
    current_state=$(tr -d '[:space:]' < "$CURRENT_STATE_FILE" 2>/dev/null)
    if [ "$apply_profile" = "$current_state" ]; then
        apply_log "SKIPPED" "profile=$apply_profile already current"
        exit 0
    fi
fi

lock_acquired=0
lock_try=0
while [ "$lock_try" -lt "$LOCK_TIMEOUT" ]; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        lock_acquired=1
        break
    fi
    cleanup_stale_lock
    sleep 1
    lock_try=$((lock_try + 1))
done

if [ "$lock_acquired" != "1" ]; then
    apply_log "WARNING" "apply lock busy after ${LOCK_TIMEOUT}s; profile=$apply_profile skipped"
    exit 1
fi

printf '%s\n' "$$" > "$LOCK_OWNER_FILE" 2>/dev/null || {
    apply_log "ERROR" "failed to write lock owner pid"
    release_lock
    exit 1
}

if [ ! -f "$MODDIR/profiles.sh" ]; then
    apply_log "ERROR" "profiles.sh missing: $MODDIR/profiles.sh"
    release_lock
    exit 1
fi
if [ ! -f "$MODDIR/detect.sh" ]; then
    apply_log "ERROR" "detect.sh missing: $MODDIR/detect.sh"
    release_lock
    exit 1
fi
if [ ! -f "$MODDIR/engine.sh" ]; then
    apply_log "ERROR" "engine.sh missing: $MODDIR/engine.sh"
    release_lock
    exit 1
fi

. "$MODDIR/detect.sh" 2>/dev/null
if [ "$?" -ne 0 ]; then
    apply_log "ERROR" "failed to source detect.sh"
    release_lock
    exit 1
fi

. "$MODDIR/profiles.sh" 2>/dev/null
if [ "$?" -ne 0 ]; then
    apply_log "ERROR" "failed to source profiles.sh"
    release_lock
    exit 1
fi

. "$MODDIR/engine.sh" 2>/dev/null
if [ "$?" -ne 0 ]; then
    apply_log "ERROR" "failed to source engine.sh"
    release_lock
    exit 1
fi

load_profile "$apply_profile"
if [ "$?" -ne 0 ]; then
    apply_log "ERROR" "load_profile failed for profile=$apply_profile"
    release_lock
    exit 1
fi

# CATATAN MERGE: tune_governor, tune_cpu_freq, tune_boost_silencer SENGAJA
# TIDAK dipanggil di sini (sama seperti service.sh) - domain governor/freq
# dan perfmgr/mtk_fpsgo diserahkan penuh ke fas-rs supaya tidak rebutan
# kontrol setiap kali monitor.sh memicu apply_now.sh saat ganti profil.
tune_devfreq
tune_io
tune_vm
tune_thermal
tune_network
tune_gpu

state_tmp="$CURRENT_STATE_FILE.tmp.$$"
if printf '%s\n' "$ACTIVE_PROFILE" > "$state_tmp" && mv -f "$state_tmp" "$CURRENT_STATE_FILE" 2>/dev/null; then
    apply_log "APPLIED" "current_state=$ACTIVE_PROFILE"
else
    rm -f "$state_tmp" 2>/dev/null
    apply_log "ERROR" "failed to atomically write current_state"
    release_lock
    exit 1
fi

apply_log "SUMMARY" "profile=$ACTIVE_PROFILE applied=$APPLIED_COUNT skipped=$SKIPPED_COUNT failed=$FAILED_COUNT"
release_lock
exit 0
