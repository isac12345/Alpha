#!/system/bin/sh
# Alpha Shield: pemblokir iklan/tracker berbasis hosts, systemless (bind mount, partisi tidak diubah).
# Tidak ada daftar domain yang ditanam: kamu yang memasukkan daftar (format hosts "0.0.0.0 domain"
# atau satu domain per baris), mis. dari L-Blocker / AdAway / Hagezi.
#
#   shield.sh status                     on, mounted, daftar aktif, jumlah domain
#   shield.sh lists                      daftar tersedia: nama, jumlah baris, aktif/tidak
#   shield.sh import <file|folder> [nama]  salin daftar ke Shield (folder: semua *.txt di dalamnya)
#   shield.sh enable <nama> | disable <nama>
#   shield.sh remove <nama>              hapus daftar yang sudah diimpor
#   shield.sh allow add|rm <domain> | allow list    pengecualian (domain ini TIDAK diblokir)
#   shield.sh on | off                   nyalakan (bangun + mount) / matikan (umount)
#   shield.sh apply                      bangun ulang + mount (setelah ubah daftar/pengecualian)
#   shield.sh boot                       dipanggil service.sh: apply bila SHIELD_ON=1
#
# Cara kerja: semua daftar aktif digabung -> dinormalisasi (huruf kecil, buang komentar/duplikat,
# hanya karakter domain valid) -> dikurangi pengecualian -> ditulis "0.0.0.0 domain" ke
# $STATE/shield/active_hosts -> `mount --bind` ke /system/etc/hosts. Lepas = `umount`, hosts asli utuh.
# Batas: hosts tidak menangkap app yang memakai DNS-over-HTTPS sendiri / Private DNS;
# matikan Private DNS bila iklan masih lolos. Jangan jalankan bersama modul hosts lain (L-Blocker, AdAway).

STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
SH_DIR="$STATE_DIR/shield"
LISTS="$SH_DIR/lists"
ENABLED="$SH_DIR/enabled.conf"
ALLOW="$SH_DIR/allow.txt"
ACTIVE="$SH_DIR/active_hosts"
MARK="$SH_DIR/.mounted"
CONF="$STATE_DIR/app.conf"
TARGET="${ALPHA_HOSTS_TARGET:-/system/etc/hosts}"
PROC_MOUNTS="${ALPHA_PROC_MOUNTS:-/proc/mounts}"
LOG="${ALPHA_LOG_FILE:-$STATE_DIR/alpha.log}"

mkdir -p "$LISTS" 2>/dev/null

_log() { printf '[%s] [SHIELD] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$1" "$2" >> "$LOG" 2>/dev/null; }

_conf_get() {
    _v=""
    [ -f "$CONF" ] && _v=$(sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -n 1)
    [ -n "$_v" ] && printf '%s' "$_v" || printf '%s' "$2"
}

_conf_set() {
    touch "$CONF" 2>/dev/null
    grep -v "^$1=" "$CONF" > "$CONF.tmp.$$" 2>/dev/null
    printf '%s=%s\n' "$1" "$2" >> "$CONF.tmp.$$"
    mv -f "$CONF.tmp.$$" "$CONF"
}

_valid_name() { case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac; return 0; }
_is_mounted() { grep -q " $TARGET " "$PROC_MOUNTS" 2>/dev/null; }
_count() { [ -f "$1" ] || { echo 0; return 0; }; grep -c '^0\.0\.0\.0 ' "$1" 2>/dev/null; return 0; }

_enabled_names() { [ -f "$ENABLED" ] && grep -v '^[[:space:]]*$' "$ENABLED"; return 0; }

# stdout: domain unik, huruf kecil, hanya karakter domain valid, tanpa localhost dan pengecualian
_build_domains() {
    for _n in $(_enabled_names); do
        [ -f "$LISTS/$_n.txt" ] && cat "$LISTS/$_n.txt"
    done | tr -d '\r' \
        | sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
              -e 's/^[0-9a-fA-F:.]*[[:space:]][[:space:]]*//' \
        | tr 'A-Z' 'a-z' \
        | grep -E '^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$' \
        | grep -vx -e localhost -e 'localhost.localdomain' -e local -e broadcasthost \
        | sort -u > "$SH_DIR/.domains"
    if [ -s "$ALLOW" ]; then
        tr -d '\r' < "$ALLOW" | tr 'A-Z' 'a-z' | grep -v '^[[:space:]]*$' > "$SH_DIR/.allow.norm"
        grep -Fvx -f "$SH_DIR/.allow.norm" "$SH_DIR/.domains" > "$SH_DIR/.domains2"
        mv -f "$SH_DIR/.domains2" "$SH_DIR/.domains"
        rm -f "$SH_DIR/.allow.norm"
    fi
}

_build() {
    _build_domains
    { printf '127.0.0.1 localhost\n::1 localhost\n\n'; sed 's/^/0.0.0.0 /' "$SH_DIR/.domains"; } > "$ACTIVE.tmp.$$"
    mv -f "$ACTIVE.tmp.$$" "$ACTIVE"
    rm -f "$SH_DIR/.domains"
    chmod 0644 "$ACTIVE" 2>/dev/null
    chown 0:0 "$ACTIVE" 2>/dev/null
    chcon u:object_r:system_file:s0 "$ACTIVE" 2>/dev/null
}

_unmount_ours() {
    if [ -f "$MARK" ] && _is_mounted; then umount "$TARGET" 2>/dev/null; fi
    rm -f "$MARK"
}

_mount() {
    if [ ! -f "$MARK" ] && _is_mounted; then
        echo "ERROR: $TARGET sudah di-mount modul lain (L-Blocker/AdAway?). Matikan itu dulu."
        _log WARN "hosts sudah di-mount pihak lain, Shield tidak menimpa"
        return 1
    fi
    _unmount_ours
    if ! mount --bind "$ACTIVE" "$TARGET" 2>/dev/null; then
        echo "ERROR: mount --bind gagal"
        _log WARN "mount --bind gagal"
        return 1
    fi
    : > "$MARK"
    # flush cache DNS supaya aturan baru langsung berlaku (perintah tidak ada di semua ROM)
    ndc resolver flushdefaultif >/dev/null 2>&1
    return 0
}

do_apply() {
    if [ -z "$(_enabled_names)" ]; then
        echo "ERROR: belum ada daftar aktif. Impor lalu enable dulu (shield.sh import ...; shield.sh enable <nama>)"
        return 1
    fi
    _build
    _mount || return 1
    echo "OK: Shield aktif, $(_count "$ACTIVE") domain diblokir"
    _log APPLIED "hosts aktif: $(_count "$ACTIVE") domain"
}

do_off() {
    _conf_set SHIELD_ON 0
    _unmount_ours
    ndc resolver flushdefaultif >/dev/null 2>&1
    echo "OK: Shield dimatikan"
    _log RESTORED "hosts dilepas"
}

do_import() {
    _src="$1"
    [ -e "$_src" ] || { echo "ERROR: $_src tidak ada"; return 1; }
    if [ -d "$_src" ]; then
        _n=0
        for _f in "$_src"/*.txt; do
            [ -f "$_f" ] || continue
            _nm=$(basename "$_f" .txt)
            _valid_name "$_nm" || continue
            cp -f "$_f" "$LISTS/$_nm.txt" && _n=$((_n + 1))
        done
        echo "OK: $_n daftar diimpor"
        return 0
    fi
    _nm="${2:-$(basename "$_src" .txt)}"
    _valid_name "$_nm" || { echo "ERROR: nama daftar tidak valid (huruf, angka, . _ -)"; return 1; }
    cp -f "$_src" "$LISTS/$_nm.txt" || { echo "ERROR: gagal menyalin"; return 1; }
    echo "OK: daftar $_nm diimpor ($(wc -l < "$LISTS/$_nm.txt" | tr -d '[:space:]') baris)"
}

do_enable() {
    _valid_name "$1" && [ -f "$LISTS/$1.txt" ] || { echo "ERROR: daftar $1 tidak ada"; return 1; }
    touch "$ENABLED"
    grep -qx "$1" "$ENABLED" || printf '%s\n' "$1" >> "$ENABLED"
    echo "OK: $1 aktif (jalankan apply)"
}

do_disable() {
    [ -f "$ENABLED" ] || return 0
    grep -vx "$1" "$ENABLED" > "$ENABLED.tmp.$$"
    mv -f "$ENABLED.tmp.$$" "$ENABLED"
    echo "OK: $1 nonaktif (jalankan apply)"
}

do_remove() {
    _valid_name "$1" || { echo "ERROR: nama tidak valid"; return 1; }
    do_disable "$1" >/dev/null
    rm -f "$LISTS/$1.txt"
    echo "OK: daftar $1 dihapus"
}

do_lists() {
    for _f in "$LISTS"/*.txt; do
        [ -f "$_f" ] || continue
        _nm=$(basename "$_f" .txt)
        _on=0; grep -qx "$_nm" "$ENABLED" 2>/dev/null && _on=1
        printf '%s %s %s\n' "$_nm" "$(wc -l < "$_f" | tr -d '[:space:]')" "$_on"
    done
    return 0
}

do_allow() {
    case "$1" in
        add)
            case "$2" in ''|*[!A-Za-z0-9._-]*) echo "ERROR: domain tidak valid"; return 1 ;; esac
            touch "$ALLOW"; grep -qx "$2" "$ALLOW" || printf '%s\n' "$2" >> "$ALLOW"
            echo "OK: $2 dikecualikan (jalankan apply)" ;;
        rm)
            [ -f "$ALLOW" ] && { grep -vx "$2" "$ALLOW" > "$ALLOW.tmp.$$"; mv -f "$ALLOW.tmp.$$" "$ALLOW"; }
            echo "OK: pengecualian $2 dihapus (jalankan apply)" ;;
        list) [ -f "$ALLOW" ] && cat "$ALLOW"; return 0 ;;
        *) echo "Usage: allow add|rm <domain> | allow list"; return 1 ;;
    esac
}

do_status() {
    printf 'on=%s\n' "$(_conf_get SHIELD_ON 0)"
    printf 'mounted=%s\n' "$([ -f "$MARK" ] && _is_mounted && echo 1 || echo 0)"
    printf 'enabled=%s\n' "$(_enabled_names | tr '\n' ',' | sed 's/,$//')"
    printf 'domains=%s\n' "$(_count "$ACTIVE")"
    printf 'lists=%s\n' "$(do_lists | wc -l | tr -d '[:space:]')"
}

case "$1" in
    status) do_status ;;
    lists) do_lists ;;
    import) do_import "$2" "$3" ;;
    enable) do_enable "$2" ;;
    disable) do_disable "$2" ;;
    remove) do_remove "$2" ;;
    allow) do_allow "$2" "$3" ;;
    on) _conf_set SHIELD_ON 1; do_apply ;;
    off) do_off ;;
    apply) do_apply ;;
    boot)
        rm -f "$MARK"   # sisa dari boot sebelumnya: mount sudah hilang
        [ "$(_conf_get SHIELD_ON 0)" = "1" ] && do_apply >/dev/null 2>&1
        exit 0 ;;
    *) sed -n '2,22p' "$0" ;;
esac
