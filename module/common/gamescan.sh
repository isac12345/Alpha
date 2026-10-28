#!/system/bin/sh
# Alpha Fusion - gamescan: temukan game terpasang yang belum terdaftar, lalu daftarkan sekaligus.
# LIBRARY (di-source alphactl.sh). Tidak ada daftar game yang ditanam di kode:
#   - common/gamelist.seed   daftar paket game umum (data, bisa diganti/ditambah)
#   - $STATE/gamelist.user   paket tambahan dari pengguna (satu per baris)
# Game "terdaftar" = ada di game_profile_map.conf (sumber yang sama dengan Games di app).
#
#   gs_candidates              paket seed yang terpasang tapi belum terdaftar, satu per baris
#   gs_add_all [profil] [fps]  daftarkan semua kandidat, fas-rs di-merge SEKALI di akhir
#   gs_user_add <pkg>          tambah paket ke daftar pengguna

GS_STATE="${ALPHA_STATE_DIR:-/data/adb/alpha}"
GS_MAP="$GS_STATE/game_profile_map.conf"
GS_USER="$GS_STATE/gamelist.user"

_gs_clean() { tr -d '\r' | sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -E '^[A-Za-z0-9._]+$' | sort -u; }

gs_installed() {
    { pm list packages 2>/dev/null || cmd package list packages 2>/dev/null; } | sed -n 's/^package://p' | tr -d '\r' | sort -u
}

gs_known() {
    { [ -f "${COMMON:-.}/gamelist.seed" ] && cat "${COMMON:-.}/gamelist.seed"; [ -f "$GS_USER" ] && cat "$GS_USER"; } | _gs_clean
}

gs_registered() {
    [ -f "$GS_MAP" ] && cut -d: -f1 "$GS_MAP" | tr -d '\r' | sort -u
}

gs_candidates() {
    _gs_t="$GS_STATE/.gs.$$"
    mkdir -p "$GS_STATE" 2>/dev/null
    gs_installed > "$_gs_t.inst"
    gs_known > "$_gs_t.known"
    gs_registered > "$_gs_t.reg" 2>/dev/null
    [ -s "$_gs_t.inst" ] && [ -s "$_gs_t.known" ] || { rm -f "$_gs_t".*; return 0; }
    grep -Fx -f "$_gs_t.known" "$_gs_t.inst" > "$_gs_t.hit" 2>/dev/null
    if [ -s "$_gs_t.reg" ]; then
        grep -Fvx -f "$_gs_t.reg" "$_gs_t.hit" 2>/dev/null
    else
        cat "$_gs_t.hit"
    fi
    rm -f "$_gs_t".*
    return 0
}

gs_user_add() {
    case "$1" in ''|*[!A-Za-z0-9._]*) echo "ERROR: package tidak valid"; return 1 ;; esac
    touch "$GS_USER" 2>/dev/null
    grep -qx "$1" "$GS_USER" 2>/dev/null || printf '%s\n' "$1" >> "$GS_USER"
    echo "OK: $1 masuk daftar pengguna"
}

gs_add_all() {
    _gs_prof="${1:-balanced}"
    _gs_fps="${2:-30,60}"
    case "$_gs_prof" in battery|balanced|performance) ;; *) echo "ERROR: profil = battery|balanced|performance"; return 1 ;; esac
    _gs_n=0
    _gs_list=$(gs_candidates)
    [ -n "$_gs_list" ] || { echo "OK: 0 game baru"; return 0; }
    for _gs_p in $_gs_list; do
        GA_SKIP_MERGE=1 sh "${COMMON:-.}/game_add.sh" add "$_gs_p" "$_gs_fps" "$_gs_prof" >/dev/null 2>&1 \
            && _gs_n=$((_gs_n + 1))
    done
    # satu kali merge + restart fas-rs untuk semuanya
    [ "$_gs_n" -gt 0 ] && sh "${COMMON:-.}/game_add.sh" merge >/dev/null 2>&1
    echo "OK: $_gs_n game ditambahkan (profil $_gs_prof, fps $_gs_fps)"
}
