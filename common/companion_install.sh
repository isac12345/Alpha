#!/system/bin/sh
# Alpha + Uperf + fas-rs Fusion - Companion APK auto-install helper
ALPHA_COMPANION_PKG="com.alphabubble"
ALPHA_COMPANION_VER=20

alpha_companion_installed_code() {
    dumpsys package "$ALPHA_COMPANION_PKG" 2>/dev/null | grep -m1 'versionCode=' | tr -cd '0-9'
}

alpha_companion_flag_code() {
    _code=$(tr -cd '0-9' < "$1" 2>/dev/null)
    case "$_code" in
        ''|*[!0-9]*) printf '0' ;;
        *) printf '%s' "$_code" ;;
    esac
}

alpha_companion_install_once() {
    _apk="$1"
    _flag="$2"
    [ -f "$_apk" ] || return 0
    if [ -f "$_flag" ] && [ "$(alpha_companion_flag_code "$_flag")" -ge "$ALPHA_COMPANION_VER" ] 2>/dev/null; then
        _have="$(alpha_companion_installed_code)"
        case "$_have" in
            ''|*[!0-9]*) _have=0 ;;
        esac
        if [ "$_have" -ge "$ALPHA_COMPANION_VER" ] 2>/dev/null; then
            return 0
        fi
    fi
    if ! command -v pm >/dev/null 2>&1; then
        return 1
    fi
    _have="$(alpha_companion_installed_code)"
    case "$_have" in
        ''|*[!0-9]*) _have=0 ;;
    esac
    if [ "$_have" -ge "$ALPHA_COMPANION_VER" ] 2>/dev/null; then
        printf '%s\n' "$ALPHA_COMPANION_VER" > "$_flag" 2>/dev/null
        return 0
    fi
    if pm install -r "$_apk" 2>/dev/null | grep -qi 'success'; then
        printf '%s\n' "$ALPHA_COMPANION_VER" > "$_flag" 2>/dev/null
        return 0
    fi
    if [ "$(alpha_companion_installed_code)" -ge "$ALPHA_COMPANION_VER" ] 2>/dev/null; then
        printf '%s\n' "$ALPHA_COMPANION_VER" > "$_flag" 2>/dev/null
        return 0
    fi
    return 1
}
