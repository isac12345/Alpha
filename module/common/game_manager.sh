#!/system/bin/sh
# Alpha v1 - Kelola daftar game & pemetaan profile per-game
# File yang diubah adalah $STATE_DIR/game_profile_map.conf, format
# "package:profile" satu baris per app - persis format yang sudah
# dibaca oleh monitor.sh (get_game_profile). Script ini cuma
# menyediakan sisi tulis (add/remove/list) buat dipanggil dari APK.

STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
MAP_FILE="$STATE_DIR/game_profile_map.conf"

mkdir -p "$STATE_DIR" 2>/dev/null

is_valid_package() {
    case "$1" in
        ''|*[!A-Za-z0-9._]*) return 1 ;;
    esac
    case "$1" in
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}

is_valid_profile() {
    case "$1" in
        battery|balanced|performance) return 0 ;;
        *) return 1 ;;
    esac
}

list_games() {
    [ -f "$MAP_FILE" ] || { printf '[]\n'; return 0; }
    _first=1
    printf '['
    while IFS= read -r _line || [ -n "$_line" ]; do
        _line=$(printf '%s' "$_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        case "$_line" in ''|'#'*) continue ;; esac
        _pkg=${_line%%:*}
        _prof=${_line#*:}
        is_valid_package "$_pkg" || continue
        is_valid_profile "$_prof" || continue
        [ "$_first" = "1" ] || printf ','
        _first=0
        printf '{"package":"%s","profile":"%s"}' "$_pkg" "$_prof"
    done < "$MAP_FILE"
    printf ']\n'
}

list_installed() {
    command -v pm >/dev/null 2>&1 || { printf '[]\n'; return 0; }
    _out='['
    _first=1
    _pkgs=$(pm list packages -3 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort -u)
    _old_ifs=$IFS
    IFS='
'
    for _pkg in $_pkgs; do
        [ -z "$_pkg" ] && continue
        case "$_pkg" in
            *[!A-Za-z0-9._]*) continue ;;
        esac
        [ "$_first" = 1 ] || _out="$_out,"
        _out="$_out\"$_pkg\""
        _first=0
    done
    IFS=$_old_ifs
    printf '%s]\n' "$_out"
}

add_game() {
    _pkg="$1"
    _prof="$2"
    if ! is_valid_package "$_pkg"; then
        echo "ERROR: invalid package name"
        return 1
    fi
    if ! is_valid_profile "$_prof"; then
        echo "ERROR: invalid profile (battery|balanced|performance)"
        return 1
    fi
    touch "$MAP_FILE" 2>/dev/null
    _tmp="$MAP_FILE.tmp.$$"
    grep -v "^${_pkg}:" "$MAP_FILE" 2>/dev/null > "$_tmp"
    printf '%s:%s\n' "$_pkg" "$_prof" >> "$_tmp"
    mv -f "$_tmp" "$MAP_FILE" 2>/dev/null
    echo "OK: $_pkg -> $_prof"
}

remove_game() {
    _pkg="$1"
    if ! is_valid_package "$_pkg"; then
        echo "ERROR: invalid package name"
        return 1
    fi
    [ -f "$MAP_FILE" ] || { echo "OK: nothing to remove"; return 0; }
    _tmp="$MAP_FILE.tmp.$$"
    grep -v "^${_pkg}:" "$MAP_FILE" > "$_tmp" 2>/dev/null
    mv -f "$_tmp" "$MAP_FILE" 2>/dev/null
    echo "OK: removed $_pkg"
}

case "$1" in
    list) list_games ;;
    add) add_game "$2" "$3" ;;
    remove) remove_game "$2" ;;
    list_installed) list_installed ;;
    *) echo "Usage: game_manager.sh [list|add <package> <profile>|remove <package>|list_installed]" ;;
esac
