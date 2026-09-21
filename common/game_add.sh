#!/system/bin/sh
# Alpha Fusion - Wrapper tambah game (fas-rs games.toml + uperf exclusion)
# CLI:
#   game_add.sh add <pkg> [fps_csv] [profile]
#   game_add.sh list
#
# add: tambah/ubah game ke REPO fasrs/games.toml, sentuh merge flag
#      untuk service.sh, sync uperf exclusion, tulis game_profile_map.conf.
#      Default fps="30,60", default profile="balanced".
# list: tampilkan gabungan games.toml + uperf regex + status asoulopt.
#
# CATATAN:
# - AsoulOpt binary hardcoded 270 paket. Script ini TIDAK menambah ke
#   asoulopt. List hanya melaporkan "asoulopt: hardcoded, cek manual via strings".
# - Merge flag = /sdcard/Android/fas-rs/.need_merge (dibaca service.sh).

MODDIR="$(dirname "$(readlink -f "$0")")"
REPO_DIR="$(dirname "$MODDIR")"
FASRS_TOML="$REPO_DIR/fasrs/games.toml"
WORK_DIR="${ALPHA_WORK_DIR:-/data/adb/alpha}"
LOG_FILE="$WORK_DIR/alpha.log"
MAP_FILE="$WORK_DIR/game_profile_map.conf"
FASRS_DIR="/sdcard/Android/fas-rs"
MERGE_FLAG="$FASRS_DIR/.need_merge"
UPERF_JSON="/sdcard/Android/yc/uperf/uperf.json"
SYNC_SCRIPT="$MODDIR/sync_uperf_exclusion.sh"

DEFAULT_FPS="30,60"
DEFAULT_PROFILE="balanced"

# ---------- helpers ----------

_log() {
    printf '[game_add] %s\n' "$1" >> "$LOG_FILE" 2>/dev/null
}

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

# Validasi fps CSV: "30,60" atau tunggal "60"
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

# "30,60,90" -> "[30, 60, 90]" ; "60" -> "60"
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

# ---------- add ----------

do_add() {
    _pkg="$1"
    _fps="${2:-$DEFAULT_FPS}"
    _profile="${3:-$DEFAULT_PROFILE}"

    # validasi
    if ! is_valid_package "$_pkg"; then
        echo "ERROR: invalid package name: $_pkg"
        _log "ERROR: invalid package name: $_pkg"
        return 1
    fi
    if ! is_valid_fps_csv "$_fps"; then
        echo "ERROR: invalid fps: $_fps (contoh: 30,60 atau 60)"
        _log "ERROR: invalid fps: $_fps"
        return 1
    fi
    if ! is_valid_profile "$_profile"; then
        echo "ERROR: invalid profile: $_profile (battery|balanced|performance)"
        _log "ERROR: invalid profile: $_profile"
        return 1
    fi
    [ -f "$FASRS_TOML" ] || { echo "ERROR: games.toml tidak ditemukan: $FASRS_TOML"; _log "ERROR: games.toml tidak ditemukan"; return 1; }

    mkdir -p "$WORK_DIR" 2>/dev/null

    # 1. Tulis ke REPO fasrs/games.toml (idempoten: update jika sudah ada)
    _toml_val=$(fps_csv_to_toml "$_fps")
    _new_line="\"$_pkg\" = $_toml_val"
    _tmp="$FASRS_TOML.tmp.$$"

    if grep -q "^\"${_pkg}\"[[:space:]]*=" "$FASRS_TOML" 2>/dev/null; then
        sed "s#^\"${_pkg}\"[[:space:]]*=.*#${_new_line}#" "$FASRS_TOML" > "$_tmp"
    else
        # sisipkan setelah baris [game_list] (sed a\ POSIX)
        sed "/^\[game_list\]/a\\
${_new_line}" "$FASRS_TOML" > "$_tmp"
    fi

    if [ ! -s "$_tmp" ]; then
        rm -f "$_tmp" 2>/dev/null
        echo "ERROR: gagal menulis games.toml"
        _log "ERROR: gagal menulis games.toml"
        return 1
    fi
    mv -f "$_tmp" "$FASRS_TOML"

    # 2. Sentuh merge flag agar service.sh merge ke /sdcard saat boot
    touch "$MERGE_FLAG" 2>/dev/null

    # 3. Sync uperf exclusion (games.toml -> uperf.json regex)
    if [ -x "$SYNC_SCRIPT" ]; then
        sh "$SYNC_SCRIPT" "$FASRS_TOML" "$UPERF_JSON" 2>/dev/null
    fi

    # 4. Tulis ke game_profile_map.conf
    if [ -n "$MAP_FILE" ]; then
        mkdir -p "$(dirname "$MAP_FILE")" 2>/dev/null
        touch "$MAP_FILE" 2>/dev/null
        _mtmp="$MAP_FILE.tmp.$$"
        grep -v "^${_pkg}:" "$MAP_FILE" 2>/dev/null > "$_mtmp"
        printf '%s:%s\n' "$_pkg" "$_profile" >> "$_mtmp"
        mv -f "$_mtmp" "$MAP_FILE" 2>/dev/null
    fi

    echo "OK: $_pkg -> fas-rs fps=$_fps profile=$_profile (merge flag set)"
    _log "add: $_pkg fps=$_fps profile=$_profile"
}

# ---------- list ----------

do_list() {
    # Bagian 1: games.toml [game_list]
    echo "=== games.toml (fas-rs engine) ==="
    if [ -f "$FASRS_TOML" ]; then
        _in_game_list=0
        while IFS= read -r _line || [ -n "$_line" ]; do
            case "$_line" in
                '[game_list]') _in_game_list=1; continue ;;
                '['*) if [ "$_in_game_list" = "1" ]; then break; fi ;;
            esac
            if [ "$_in_game_list" = "1" ]; then
                case "$_line" in
                    ''|'#'*) continue ;;
                esac
                printf '  %s\n' "$_line"
            fi
        done < "$FASRS_TOML"
    else
        echo "  (games.toml tidak ditemukan)"
    fi

    echo ""

    # Bagian 2: uperf regex (Alpha-FasrsManaged)
    echo "=== uperf.json (Alpha-FasrsManaged regex) ==="
    if [ -f "$UPERF_JSON" ]; then
        _regex=$(sed -n '/"name": "Alpha-FasrsManaged"/,/}/p' "$UPERF_JSON" 2>/dev/null \
            | sed -n 's/.*"regex": *"\([^"]*\)".*/\1/p')
        if [ -n "$_regex" ]; then
            case "$_regex" in
                ALPHA_NO_GAMES_YET_PLACEHOLDER)
                    echo "  (kosong - tidak ada game di managed list)"
                    ;;
                *)
                    # tampilkan per-paket, dipisah pipe
                    printf '%s\n' "$_regex" | tr '|' '\n' | while IFS= read -r _p; do
                        printf '  %s\n' "$_p"
                    done
                    ;;
            esac
        else
            echo "  (regex tidak ditemukan)"
        fi
    else
        echo "  (uperf.json tidak ditemukan)"
    fi

    echo ""

    # Bagian 3: asoulopt status
    echo "=== asoulopt ==="
    echo "  asoulopt: hardcoded, cek manual via strings"
    echo "  (binary mencakup ~270 paket; TIDAK bisa ditambah dari sini)"

    echo ""

    # Bagian 4: game_profile_map.conf
    echo "=== game_profile_map.conf ==="
    if [ -f "$MAP_FILE" ]; then
        while IFS= read -r _line || [ -n "$_line" ]; do
            _line=$(printf '%s' "$_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            case "$_line" in ''|'#'*) continue ;; esac
            printf '  %s\n' "$_line"
        done < "$MAP_FILE"
    else
        echo "  (belum ada mapping)"
    fi
}

# ---------- remove (kompatibel APK removeGameFlow: "sh game_add.sh remove <pkg>") ----------

do_remove() {
    _pkg="$1"
    if ! is_valid_package "$_pkg"; then
        echo "ERROR: invalid package name: $_pkg"
        return 1
    fi
    # 1. Hapus dari REPO games.toml (no-op bila tidak ada)
    if [ -f "$FASRS_TOML" ]; then
        _tmp="$FASRS_TOML.tmp.$$"
        grep -v "^\"${_pkg}\"[[:space:]]*=" "$FASRS_TOML" > "$_tmp" 2>/dev/null \
            && mv -f "$_tmp" "$FASRS_TOML"
        touch "$MERGE_FLAG" 2>/dev/null
    fi
    # 2. Hapus dari profile map (kembali ke manual)
    if [ -f "$MAP_FILE" ]; then
        _mtmp="$MAP_FILE.tmp.$$"
        grep -v "^${_pkg}:" "$MAP_FILE" 2>/dev/null > "$_mtmp" \
            && mv -f "$_mtmp" "$MAP_FILE" 2>/dev/null
    fi
    # 3. Sync uperf exclusion
    if [ -x "$SYNC_SCRIPT" ]; then
        sh "$SYNC_SCRIPT" "$FASRS_TOML" "$UPERF_JSON" 2>/dev/null
    fi
    echo "OK: $_pkg dihapus (kembali ke uperf/manual)"
    _log "remove: $_pkg"
}

# ---------- main ----------

case "$1" in
    add)
        # Kompatibel dua urutan: APK lama kirim "add <pkg> <profile> [fps]",
        # CLI baru "add <pkg> [fps] [profile]". Deteksi via $3.
        case "$3" in
            battery|balanced|performance)
                do_add "$2" "${4:-30,60}" "$3"
                ;;
            *)
                do_add "$2" "$3" "$4"
                ;;
        esac
        ;;
    remove)
        do_remove "$2"
        ;;
    list)
        do_list
        ;;
    *)
        echo "Usage: game_add.sh [add <pkg> [fps_csv] [profile] | remove <pkg> | list]"
        echo ""
        echo "  add <pkg> [fps_csv] [profile]"
        echo "    Tambah game ke fas-rs games.toml + uperf exclusion + profile map."
        echo "    Default fps=30,60  Default profile=balanced"
        echo "    Contoh: game_add.sh add com.example.game"
        echo "            game_add.sh add com.example.game 60"
        echo "            game_add.sh add com.example.game 30,60,90 performance"
        echo ""
        echo "  list"
        echo "    Tampilkan gabungan: games.toml + uperf regex + asoulopt + profile map."
        echo ""
        echo "  CATATAN: AsoulOpt binary hardcoded, tidak bisa ditambah dari sini."
        exit 1
        ;;
esac
