#!/system/bin/sh
# sandbox/test-v2-nodes.sh — fake-fs uji read-only common/probe_v2.sh
# Skenario:
#   (a) normal: semua node ada + writable
#   (b) zram0/comp_algorithm read-only saat runtime
#   (c) tcp_congestion_control tidak writable (proxy SELinux: mode baca)
#   (d) node absen (tcp_low_latency dihapus)
# Assert per skenario:
#   - checksum fake-fs (path+mode+isi) identik sebelum/sesudah probe
#   - (b)/(c)/(d) terdeteksi SKIP dengan alasan benar
# Catatan (c): peniru penolakan SELinux memakai mode baca saja karena
# tes ini jalan tanpa root; arti hasil sama: writable=N.
# Tidak menyentuh /proc atau /sys asli; hanya $TMPDIR.
set -u
umask 022

TESTDIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
ROOT=$(dirname "$TESTDIR")
PROBE="$ROOT/common/probe_v2.sh"

PASS_N=0
FAIL_N=0

pass() {
    PASS_N=$((PASS_N + 1))
    printf 'PASS %s\n' "$1"
}

fail() {
    FAIL_N=$((FAIL_N + 1))
    printf 'FAIL %s\n' "$1"
}

# assert_has <label> <substring-literal> <haystack>
assert_has() {
    case "$3" in
        *"$2"*) pass "$1" ;;
        *)      fail "$1 — tidak ada: $2" ;;
    esac
}

assert_lacks() {
    case "$3" in
        *"$2"*) fail "$1 — seharusnya tidak ada: $2" ;;
        *)     pass "$1" ;;
    esac
}

# Digest fake-fs: daftar path (urut) + mode + cksum isi per file.
fs_digest() {
    find "$1" | LC_ALL=C sort | while IFS= read -r p; do
        if [ -d "$p" ]; then
            printf 'd %s\n' "$p"
        else
            printf '%s | %s\n' "$(ls -ld "$p")" "$(cksum "$p")"
        fi
    done
}

# Isi fake-fs lengkap untuk semua node target probe v2.
build_fs() {
    F=$(mktemp -d "${TMPDIR:-/tmp}/probev2.XXXXXX") || exit 1
    P="$F/proc/sys"
    B="$F/sys/block"
    mkdir -p "$P/net/ipv4" "$P/net/core" "$P/vm" \
        "$B/zram0" "$B/sda/queue" "$B/mmcblk0/queue" "$B/mmcblk0p1/queue"
    printf '%s' 'cubic'                 > "$P/net/ipv4/tcp_congestion_control"
    printf '%s' 'reno cubic bbr'        > "$P/net/ipv4/tcp_available_congestion_control"
    printf '%s' '1'                     > "$P/net/ipv4/tcp_low_latency"
    printf '%s' '4194304'               > "$P/net/core/rmem_max"
    printf '%s' '4194304'               > "$P/net/core/wmem_max"
    printf '%s' '60'                    > "$P/vm/swappiness"
    printf '%s' '20'                    > "$P/vm/dirty_ratio"
    printf '%s' '10'                    > "$P/vm/dirty_background_ratio"
    printf '%s' '3000'                  > "$P/vm/dirty_expire_centisecs"
    printf '%s' 'lzo lzo-rle lz4 [zstd]' > "$B/zram0/comp_algorithm"
    printf '%s' '128'                   > "$B/sda/queue/read_ahead_kb"
    printf '%s' '128'                   > "$B/mmcblk0/queue/read_ahead_kb"
    printf '%s' '128'                   > "$B/mmcblk0p1/queue/read_ahead_kb"
}

# Source probe_v2.sh dengan PREFIX mengarah ke fake-fs (subshell,
# stdout ditangkap pemanggil). Tidak ada fallback ke /proc atau /sys.
run_probe() {
    (
        export PROC_SYS_PREFIX="$P"
        export SYSFS_BLOCK_PREFIX="$B"
        # shellcheck disable=SC1090 # path probe dibangun saat runtime
        . "$PROBE"
    )
}

# Kembalikan 0 bila probe tidak mengubah fake-fs sama sekali.
assert_fs_unchanged() {
    _label="$1"
    _before="$2"
    _after=$(fs_digest "$F")
    if [ "$_before" = "$_after" ]; then
        pass "$_label: fake-fs tidak berubah oleh probe"
    else
        fail "$_label: fake-fs BERUBAH oleh probe"
        printf '%s\n' "$_after"
    fi
}

scenario_a() {
    printf '\n--- skenario (a): normal, semua node ada + writable ---\n'
    build_fs
    _before=$(fs_digest "$F")
    out=$(run_probe)
    assert_fs_unchanged "a" "$_before"
    assert_lacks "a: tidak ada SKIP" '[SKIP' "$out"

    for n in \
        net/ipv4/tcp_congestion_control \
        net/ipv4/tcp_available_congestion_control \
        net/core/rmem_max \
        net/core/wmem_max \
        net/ipv4/tcp_low_latency \
        vm/swappiness \
        zram0/comp_algorithm \
        vm/dirty_ratio \
        vm/dirty_background_ratio \
        vm/dirty_expire_centisecs \
        sda/queue/read_ahead_kb \
        mmcblk0/queue/read_ahead_kb; do
        assert_has "a: OK node=$n" "[OK] node=$n " "$out"
    done

    assert_has "a: parse zram (aktif + opsi)" \
        "[OK] node=zram0/comp_algorithm exists=Y readable=Y writable=Y value=zstd options=lzo lzo-rle lz4 zstd" \
        "$out"
    assert_has "a: opsi cc dari available" \
        "[OK] node=net/ipv4/tcp_congestion_control exists=Y readable=Y writable=Y value=cubic options=reno cubic bbr" \
        "$out"
    assert_has "a: header ringkasan" "node|default|opsi|writable" "$out"
    assert_has "a: baris ringkasan zram" \
        "zram0/comp_algorithm|zstd|lzo lzo-rle lz4 zstd|Y" "$out"
    assert_has "a: baris ringkasan rmem_max" \
        "net/core/rmem_max|4194304|-|Y" "$out"
    assert_has "a: cc_pick berprioritas bbr" "cc_pick=bbr" "$out"
    assert_lacks "a: partisi mmcblk0p1 terfilter" "mmcblk0p1" "$out"

    printf '%s\n' "--- output probe skenario (a) ---"
    printf '%s\n' "$out"
    rm -rf "$F"
}

scenario_b() {
    printf '\n--- skenario (b): zram comp_algorithm read-only ---\n'
    build_fs
    chmod 444 "$B/zram0/comp_algorithm"
    _before=$(fs_digest "$F")
    out=$(run_probe)
    assert_fs_unchanged "b" "$_before"
    assert_has "b: SKIP not-writable + tetap terbaca" \
        "[SKIP:not-writable] node=zram0/comp_algorithm exists=Y readable=Y writable=N value=zstd options=lzo lzo-rle lz4 zstd" \
        "$out"
    assert_has "b: node lain tetap OK" \
        "[OK] node=net/core/rmem_max exists=Y readable=Y writable=Y" \
        "$out"
    rm -rf "$F"
}

scenario_c() {
    printf '\n--- skenario (c): tcp_congestion_control tidak writable ---\n'
    build_fs
    chmod 444 "$P/net/ipv4/tcp_congestion_control"
    _before=$(fs_digest "$F")
    out=$(run_probe)
    assert_fs_unchanged "c" "$_before"
    assert_has "c: SKIP not-writable + tetap terbaca" \
        "[SKIP:not-writable] node=net/ipv4/tcp_congestion_control exists=Y readable=Y writable=N value=cubic options=reno cubic bbr" \
        "$out"
    assert_has "c: cc_pick tetap bbr (dari available)" "cc_pick=bbr" "$out"
    rm -rf "$F"
}

scenario_d() {
    printf '\n--- skenario (d): node absen ---\n'
    build_fs
    rm -f "$P/net/ipv4/tcp_low_latency"
    _before=$(fs_digest "$F")
    out=$(run_probe)
    assert_fs_unchanged "d" "$_before"
    assert_has "d: SKIP absent" \
        "[SKIP:absent] node=net/ipv4/tcp_low_latency exists=N readable=N writable=N value=- options=-" \
        "$out"
    assert_has "d: baris ringkasan absen" \
        "net/ipv4/tcp_low_latency|-|-|N" "$out"
    rm -rf "$F"
}

[ -r "$PROBE" ] || { printf 'FAIL probe tidak terbaca: %s\n' "$PROBE"; exit 1; }

scenario_a
scenario_b
scenario_c
scenario_d

printf '\n== hasil: %s PASS, %s FAIL ==\n' "$PASS_N" "$FAIL_N"
[ "$FAIL_N" -eq 0 ]
