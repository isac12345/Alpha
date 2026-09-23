#!/system/bin/sh
# shellcheck shell=dash
# Alpha Fusion - PROBE v2 (read-only): NET / Memory-ZRAM / Storage-IO
# Hanya membaca node: test -e/-r/-w + cat. Tidak ada tulisan ke node,
# tidak ada pengubahan izin file, tidak ada perintah sysctl penulis,
# tidak ada operasi swap. Pola PREFIX sama dengan common/gameboost.sh
# supaya bisa diuji di sandbox fake-fs:
#   PROC_SYS_PREFIX, SYSFS_BLOCK_PREFIX
#
# Node v2 yang BENAR-BENAR BARU (belum ada di gameboost.sh):
#   net/core/rmem_max, net/core/wmem_max, net/ipv4/tcp_low_latency,
#   zram0/comp_algorithm, vm/dirty_expire_centisecs,
#   pemilihan cc berprioritas (bbr, lalu cubic, lalu cc aktif).
# Sudah ditangani gameboost.sh (dicatat saja, jangan diduplikasi):
#   vm/swappiness, vm/dirty_ratio, vm/dirty_background_ratio,
#   queue/read_ahead_kb per device utama,
#   net/ipv4/tcp_congestion_control (gameboost hanya bbr-only;
#   probe melaporkan prioritas penuh).

PROC_SYS_PREFIX="${PROC_SYS_PREFIX:-/proc/sys}"
SYSFS_BLOCK_PREFIX="${SYSFS_BLOCK_PREFIX:-/sys/block}"

# Baca isi file bila readable. Selalu dijaga test -r dulu supaya
# tidak perlu mematikan pesan error eksternal.
_probe_cat() {
    [ -r "$1" ] || return 1
    cat "$1"
}

# comp_algorithm zram: "lzo lz4 [zstd]" menghasilkan aktif "zstd"
# (tanpa kurung-siku: token pertama, fallback kosong)
_probe_zram_active() {
    local _raw="$1" _act="" _t
    # shellcheck disable=SC2086 # pemisahan token memang diinginkan
    for _t in $_raw; do
        case "$_t" in
            \[*\])
                _act=$(printf '%s' "$_t" | tr -d '[]')
                break
                ;;
        esac
    done
    if [ -z "$_act" ]; then
        # shellcheck disable=SC2086
        for _t in $_raw; do
            _act="$_t"
            break
        done
    fi
    printf '%s' "$_act"
}

# comp_algorithm zram: semua token tanpa kurung-siku
_probe_zram_options() {
    local _raw="$1" _out="" _t
    # shellcheck disable=SC2086
    for _t in $_raw; do
        _t=$(printf '%s' "$_t" | tr -d '[]')
        [ -n "$_t" ] || continue
        [ -n "$_out" ] && _out="$_out "
        _out="$_out$_t"
    done
    printf '%s' "$_out"
}

# Pemilihan congestion-control berprioritas: bbr, lalu cubic,
# lalu cc yang sedang aktif, lalu token pertama yang tersedia.
_probe_cc_pick() {
    local _av="$1" _act="$2" _c
    # Preferensi dinamis dari daftar device: bbr3 > bbr2 > bbr > cubic > aktif
    for _c in bbr3 bbr2 bbr cubic; do
        case " $_av " in
            *" $_c "*)
                printf '%s\n' "$_c"
                return 0
                ;;
        esac
    done
    if [ -n "$_act" ] && [ "$_act" != "-" ]; then
        printf '%s\n' "$_act"
        return 0
    fi
    # shellcheck disable=SC2086 # ambil token pertama dari daftar
    set -- $_av
    if [ $# -gt 0 ] && [ -n "$1" ]; then
        printf '%s\n' "$1"
        return 0
    fi
    printf '%s\n' "-"
}

# probe_node nama-relatif path-lengkap mode-opsi
#   mode-opsi: cc   = opsi dari tcp_available_congestion_control
#              avail = opsi isi node itu sendiri
#              zram  = nilai aktif [..], opsi semua algoritma
#              none  = tanpa daftar opsi
# Cetak satu baris detail + akumulasi baris ringkasan (PROBE_ROWS).
probe_node() {
    local _name="$1" _path="$2" _omode="$3"
    local _ex=N _rd=N _wr=N _val="-" _opts="-" _status="OK" _an

    if [ -e "$_path" ]; then
        _ex=Y
        [ -r "$_path" ] && _rd=Y
        [ -w "$_path" ] && _wr=Y
        if [ "$_rd" != Y ]; then
            _status="SKIP:not-readable"
        elif [ "$_wr" != Y ]; then
            _status="SKIP:not-writable"
        fi
    else
        _status="SKIP:absent"
    fi

    if [ "$_rd" = Y ]; then
        _val=$(_probe_cat "$_path")
        [ -n "$_val" ] || _val="-"
    fi

    case "$_omode" in
        avail)
            _opts="$_val"
            ;;
        zram)
            if [ "$_rd" = Y ]; then
                _opts=$(_probe_zram_options "$_val")
                _val=$(_probe_zram_active "$_val")
                [ -n "$_val" ] || _val="-"
                [ -n "$_opts" ] || _opts="-"
            fi
            ;;
        cc)
            _an="$PROC_SYS_PREFIX/net/ipv4/tcp_available_congestion_control"
            if [ -r "$_an" ]; then
                _opts=$(_probe_cat "$_an")
                [ -n "$_opts" ] || _opts="-"
            fi
            ;;
    esac

    printf '%s node=%s exists=%s readable=%s writable=%s value=%s options=%s\n' \
        "[$_status]" "$_name" "$_ex" "$_rd" "$_wr" "$_val" "$_opts"
    PROBE_ROWS="${PROBE_ROWS}${_name}|${_val}|${_opts}|${_wr}
"
}

probe_v2_main() {
    PROBE_ROWS=""
    local _dev _name _avail="-" _active="-" _pick="-" _an _ccn

    printf '%s\n' "=== PROBE v2 read-only: NET / Memory-ZRAM / Storage-IO ==="
    printf '%s\n' "PROC_SYS_PREFIX=$PROC_SYS_PREFIX"
    printf '%s\n' "SYSFS_BLOCK_PREFIX=$SYSFS_BLOCK_PREFIX"

    printf '%s\n' "== NET =="
    probe_node "net/ipv4/tcp_congestion_control" \
        "$PROC_SYS_PREFIX/net/ipv4/tcp_congestion_control" cc
    probe_node "net/ipv4/tcp_available_congestion_control" \
        "$PROC_SYS_PREFIX/net/ipv4/tcp_available_congestion_control" avail
    probe_node "net/core/rmem_max" \
        "$PROC_SYS_PREFIX/net/core/rmem_max" none
    probe_node "net/core/wmem_max" \
        "$PROC_SYS_PREFIX/net/core/wmem_max" none
    probe_node "net/ipv4/tcp_low_latency" \
        "$PROC_SYS_PREFIX/net/ipv4/tcp_low_latency" none

    printf '%s\n' "== MEM =="
    probe_node "vm/swappiness" "$PROC_SYS_PREFIX/vm/swappiness" none
    probe_node "zram0/comp_algorithm" \
        "$SYSFS_BLOCK_PREFIX/zram0/comp_algorithm" zram
    probe_node "vm/dirty_ratio" "$PROC_SYS_PREFIX/vm/dirty_ratio" none
    probe_node "vm/dirty_background_ratio" \
        "$PROC_SYS_PREFIX/vm/dirty_background_ratio" none

    printf '%s\n' "== IO =="
    probe_node "vm/dirty_expire_centisecs" \
        "$PROC_SYS_PREFIX/vm/dirty_expire_centisecs" none
    # read_ahead_kb per device utama (pola _gb_apply_io + detect.sh);
    # partisi gaya mmc dibuang dengan filter yang sama seperti gameboost.
    for _dev in "$SYSFS_BLOCK_PREFIX"/sd* "$SYSFS_BLOCK_PREFIX"/mmcblk* \
                "$SYSFS_BLOCK_PREFIX"/nvme* "$SYSFS_BLOCK_PREFIX"/ufs*; do
        [ -d "$_dev/queue" ] || continue
        _name=${_dev##*/}
        case "$_name" in
            *p[0-9]*|*[0-9]rpmb|*[0-9]boot*) continue ;;
        esac
        probe_node "$_name/queue/read_ahead_kb" \
            "$_dev/queue/read_ahead_kb" none
    done

    printf '%s\n' "== ringkasan =="
    printf '%s\n' "node|default|opsi|writable"
    printf '%s' "$PROBE_ROWS"

    _an="$PROC_SYS_PREFIX/net/ipv4/tcp_available_congestion_control"
    _ccn="$PROC_SYS_PREFIX/net/ipv4/tcp_congestion_control"
    [ -r "$_an" ] && _avail=$(_probe_cat "$_an")
    [ -r "$_ccn" ] && _active=$(_probe_cat "$_ccn")
    [ -n "$_avail" ] || _avail="-"
    [ -n "$_active" ] || _active="-"
    _pick=$(_probe_cc_pick "$_avail" "$_active")
    printf '%s\n' "== rekomendasi cc (prioritas: bbr, cubic, aktif) =="
    printf 'cc_available=%s\n' "$_avail"
    printf 'cc_active=%s\n' "$_active"
    printf 'cc_pick=%s\n' "$_pick"
}

probe_v2_main
