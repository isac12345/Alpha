#!/system/bin/sh
# Alpha + Uperf + fas-rs Fusion
# Kelola [game_list] di fasrs/games.toml dari APK - ini SATU-SATUNYA titik
# pilih engine per-game: package yang di-add di sini otomatis dipegang fas-rs
# dan otomatis di-exclude dari classifier cpuset uperf (lihat
# common/sync_uperf_exclusion.sh). Package yang di-remove otomatis balik
# ditangani uperf seperti biasa. Setiap add/remove langsung men-sync uperf.json
# dan me-restart fas-rs + uperf supaya efeknya instan tanpa reboot.

MODDIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
FASRS_TOML="$MODDIR/fasrs/games.toml"
UPERF_JSON="/sdcard/Android/yc/uperf/uperf.json"
SYNC_SCRIPT="$MODDIR/common/sync_uperf_exclusion.sh"

is_valid_package() {
    case "$1" in
        ''|*[!A-Za-z0-9._]*) return 1 ;;
    esac
    case "$1" in
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}

# Validasi daftar fps dipisah koma, contoh: "30,60,90"
is_valid_fps_csv() {
    case "$1" in
        '') return 1 ;;
    esac
    _old_ifs=$IFS
    IFS=','
    for _v in $1; do
        case "$_v" in
            ''|*[!0-9]*) IFS=$_old_ifs; return 1 ;;
        esac
        if [ "$_v" -lt 1 ] || [ "$_v" -gt 1000 ]; then
            IFS=$_old_ifs
            return 1
        fi
    done
    IFS=$_old_ifs
    return 0
}

# Ubah "30,60,90" jadi nilai TOML: angka tunggal polos, atau [30, 60, 90]
fps_csv_to_toml() {
    _count=$(printf '%s' "$1" | tr -cd ',' | wc -c)
    if [ "$_count" -eq 0 ]; then
        printf '%s' "$1"
        return 0
    fi
    _out=""
    _old_ifs=$IFS
    IFS=','
    for _v in $1; do
        if [ -z "$_out" ]; then
            _out="$_v"
        else
            _out="$_out, $_v"
        fi
    done
    IFS=$_old_ifs
    printf '[%s]' "$_out"
}

apply_and_restart() {
    [ -x "$SYNC_SCRIPT" ] && sh "$SYNC_SCRIPT" "$FASRS_TOML" "$UPERF_JSON" 2>/dev/null

    # Restart fas-rs supaya games.toml yang baru langsung terbaca
    if [ -x "$MODDIR/fasrs/fas-rs" ]; then
        killall fas-rs 2>/dev/null
        FASRS_DIR="/sdcard/Android/fas-rs"
        RUST_BACKTRACE=1 nohup "$MODDIR/fasrs/fas-rs" run "$FASRS_TOML" >> "$FASRS_DIR/fas_log.txt" 2>&1 &
        _em_fasrs_pid=$!
        # B27 OOM-GUARD: hasil restart ikut dilindungi.
        if [ -n "$_em_fasrs_pid" ] && [ -w "/proc/$_em_fasrs_pid/oom_score_adj" ]; then
            echo -1000 > "/proc/$_em_fasrs_pid/oom_score_adj" 2>/dev/null
        fi
    fi

    # Restart backend uperf supaya exclusion rule yang baru langsung terbaca
    if [ -f "$MODDIR/uperf/script/run_uperf.sh" ]; then
        killall uperf 2>/dev/null
        WORK_DIR="${ALPHA_WORK_DIR:-/data/adb/alpha}"
        nohup sh "$MODDIR/uperf/script/run_uperf.sh" >> "$WORK_DIR/alpha.log" 2>&1 &
    fi
}

list_games() {
    [ -f "$FASRS_TOML" ] || { printf '[]\n'; return 0; }
    _first=1
    printf '['
    sed -n '/^\[game_list\]/,/^\[/p' "$FASRS_TOML" | while IFS= read -r _line; do
        case "$_line" in
            '"'*)
                _pkg=$(printf '%s' "$_line" | sed -n 's/^"\([^"]*\)".*/\1/p')
                _val=$(printf '%s' "$_line" | sed -n 's/^"[^"]*"[[:space:]]*=[[:space:]]*\(.*\)$/\1/p')
                [ -z "$_pkg" ] && continue
                [ "$_first" = "1" ] || printf ','
                _first=0
                printf '{"package":"%s","fps":"%s"}' "$_pkg" "$(printf '%s' "$_val" | sed 's/"/\\"/g')"
                ;;
        esac
    done
    printf ']\n'
}

add_game() {
    _pkg="$1"
    _fps="$2"
    if ! is_valid_package "$_pkg"; then
        echo "ERROR: invalid package name"
        return 1
    fi
    if ! is_valid_fps_csv "$_fps"; then
        echo "ERROR: invalid fps list (contoh: 30,60,90)"
        return 1
    fi
    [ -f "$FASRS_TOML" ] || { echo "ERROR: games.toml tidak ditemukan"; return 1; }

    _toml_val=$(fps_csv_to_toml "$_fps")
    _new_line="\"$_pkg\" = $_toml_val"
    _tmp="$FASRS_TOML.tmp.$$"

    if grep -q "^\"${_pkg}\"[[:space:]]*=" "$FASRS_TOML" 2>/dev/null; then
        sed "s#^\"${_pkg}\"[[:space:]]*=.*#${_new_line}#" "$FASRS_TOML" > "$_tmp"
    else
        # Sisipkan baris baru tepat setelah header [game_list] (sed 'a\',
        # bentuk klasik POSIX supaya kompatibel dengan busybox minimal)
        sed "/^\[game_list\]/a\\
${_new_line}" "$FASRS_TOML" > "$_tmp"
    fi

    if [ -s "$_tmp" ]; then
        mv -f "$_tmp" "$FASRS_TOML"
        apply_and_restart
        echo "OK: $_pkg -> fas-rs ($_toml_val)"
    else
        rm -f "$_tmp" 2>/dev/null
        echo "ERROR: gagal menulis games.toml"
        return 1
    fi
}

remove_game() {
    _pkg="$1"
    if ! is_valid_package "$_pkg"; then
        echo "ERROR: invalid package name"
        return 1
    fi
    [ -f "$FASRS_TOML" ] || { echo "OK: nothing to remove"; return 0; }
    _tmp="$FASRS_TOML.tmp.$$"
    grep -v "^\"${_pkg}\"[[:space:]]*=" "$FASRS_TOML" > "$_tmp" 2>/dev/null
    mv -f "$_tmp" "$FASRS_TOML" 2>/dev/null
    apply_and_restart
    echo "OK: removed $_pkg (kembali ke uperf)"
}

case "$1" in
    list) list_games ;;
    add) add_game "$2" "$3" ;;
    remove) remove_game "$2" ;;
    *) echo "Usage: engine_manager.sh [list|add <pkg> <fps_csv>|remove <pkg>]" ;;
esac
