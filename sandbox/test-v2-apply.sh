#!/system/bin/sh
# shellcheck shell=dash
# Alpha Fusion - SANDBOX v2 apply/restore (fake-fs, tanpa sentuh device).
# Menguji perluasan gameboost.sh: cc berprioritas, rmem/wmem 2x cap 8MB,
# tcp_low_latency, dirty_expire_centisecs, zram comp_algorithm.
# Skenario: (a) normal apply extreme + restore persis, (b) zram read-only
# SKIP + exit 0, (c) cc tak-writable apply tetap lanjut, (d) idempoten 2x,
# (e) balanced = restore-only. Pola PREFIX sama seperti gameboost.sh.

GB_SH="${GB_SH:-$(dirname "$0")/../common/gameboost.sh}"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
assert_eq() {
    # assert_eq label wanted got
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want=$2 got=$3)"; fi
}

# Bangun fake-fs lengkap di $1 (root tmp). Semua file writable awal.
mk_fakefs() {
    local _r="$1" _d
    mkdir -p "$_r/proc/sys/net/ipv4" "$_r/proc/sys/net/core" "$_r/proc/sys/vm" \
             "$_r/sys/block/sda/queue" "$_r/sys/block/mmcblk0/queue" \
             "$_r/sys/block/mmcblk0p1/queue" "$_r/sys/block/zram0" \
             "$_r/empty" "$_r/conf"
    printf 'cubic' > "$_r/proc/sys/net/ipv4/tcp_congestion_control"
    printf 'reno cubic bbr' > "$_r/proc/sys/net/ipv4/tcp_available_congestion_control"
    printf '1' > "$_r/proc/sys/net/ipv4/tcp_fastopen"
    printf '0' > "$_r/proc/sys/net/ipv4/tcp_ecn"
    printf '0' > "$_r/proc/sys/net/ipv4/tcp_low_latency"
    printf '1000' > "$_r/proc/sys/net/core/netdev_max_backlog"
    printf '4194304' > "$_r/proc/sys/net/core/rmem_max"
    printf '212992' > "$_r/proc/sys/net/core/wmem_max"
    printf '60' > "$_r/proc/sys/vm/swappiness"
    printf '100' > "$_r/proc/sys/vm/vfs_cache_pressure"
    printf '20' > "$_r/proc/sys/vm/dirty_ratio"
    printf '10' > "$_r/proc/sys/vm/dirty_background_ratio"
    printf '0' > "$_r/proc/sys/vm/page-cluster"
    printf '3000' > "$_r/proc/sys/vm/dirty_expire_centisecs"
    printf 'lzo lz4 [zstd]' > "$_r/sys/block/zram0/comp_algorithm"
    for _d in sda mmcblk0; do
        printf 'none' > "$_r/sys/block/$_d/queue/scheduler"
        printf '128' > "$_r/sys/block/$_d/queue/read_ahead_kb"
    done
    printf '128' > "$_r/sys/block/mmcblk0p1/queue/read_ahead_kb"
}

# Siapkan env isolasi untuk $1 (root tmp), lalu source gameboost.sh.
gb_env() {
    # shellcheck disable=SC2034
    local _r="$1"
    export PROC_SYS_PREFIX="$_r/proc/sys" SYSFS_BLOCK_PREFIX="$_r/sys/block"
    export SYSFS_CPU_PREFIX="$_r/empty" SYSFS_DEVFREQ_PREFIX="$_r/empty"
    export GPU_SYSFS_PREFIX="$_r/empty" SYSFS_MODULE_PREFIX="$_r/empty"
    export DEV_CPUSET_PREFIX="$_r/empty" DEV_CPUCTL_PREFIX="$_r/empty"
    export DEV_STUNE_PREFIX="$_r/empty" SYSFS_DEBUG_PREFIX="$_r/empty"
    export ALPHA_CONF_DIR="$_r/conf" ALPHA_LOG_FILE="$_r/alpha.log"
    export CPU_POLICIES="" MODDIR="$_r/empty"
    # shellcheck disable=SC1090 # path dari env/arg saat uji
    . "$GB_SH"
}

rd() { cat "$1" 2>/dev/null | tr -d '[:space:]'; }

# Algoritma zram AKTIF dari isi node ("[lz4]" -> lz4; tanpa kurung -> utuh).
# Restore menulis snapshot aktif ("zstd") sehingga teks mentah beda dari
# "lzo lz4 [zstd]" tapi arti kernel sama — bandingkan yang aktif.
zram_active() {
    local _a
    _a=$(tr ' ' '\n' < "$1" 2>/dev/null | grep -E '^\[.*\]$' | tr -d '[]' | head -1)
    [ -z "$_a" ] && _a=$(tr -d '[:space:]' < "$1" 2>/dev/null)
    printf '%s' "$_a"
}

# ---------- skenario (a): normal ----------
printf '%s\n' "--- skenario (a): normal, backup-apply extreme-restore ---"
A=$(mktemp -d) || exit 1
mk_fakefs "$A"
gb_env "$A"
printf 'extreme' > "$A/conf/GAMEBOOST_LEVEL"
SNAP_CC=$(rd "$A/proc/sys/net/ipv4/tcp_congestion_control")
SNAP_RMEM=$(rd "$A/proc/sys/net/core/rmem_max")
SNAP_WMEM=$(rd "$A/proc/sys/net/core/wmem_max")
SNAP_LL=$(rd "$A/proc/sys/net/ipv4/tcp_low_latency")
SNAP_EXP=$(rd "$A/proc/sys/vm/dirty_expire_centisecs")
SNAP_ZRAM_ACT="zstd"
gb_apply >/dev/null 2>&1
RC=$?
assert_eq "a: gb_apply exit 0" "0" "$RC"
assert_eq "a: cc cubic->bbr (prioritas)" "bbr" "$(rd "$A/proc/sys/net/ipv4/tcp_congestion_control")"
assert_eq "a: rmem 2x cap 8MB" "8388608" "$(rd "$A/proc/sys/net/core/rmem_max")"
assert_eq "a: wmem 2x" "425984" "$(rd "$A/proc/sys/net/core/wmem_max")"
assert_eq "a: low_latency=1" "1" "$(rd "$A/proc/sys/net/ipv4/tcp_low_latency")"
assert_eq "a: expire=setengah" "1500" "$(rd "$A/proc/sys/vm/dirty_expire_centisecs")"
assert_eq "a: zram zstd->lz4" "lz4" "$(rd "$A/sys/block/zram0/comp_algorithm" | tr -d '[]')"
# backup tanpa duplikat
DUP=$(sort "$A/conf/native_boost.conf" | cut -d= -f1 | uniq -d | tr '\n' ' ')
assert_eq "a: backup key unik" "" "$DUP"
# kunci baru hadir
for _k in net_core_rmem_max net_core_wmem_max tcp_low_latency vm/dirty_expire_centisecs zram_comp_algorithm; do
    if grep -q "^${_k}=" "$A/conf/native_boost.conf" 2>/dev/null; then ok "a: backup ada $_k"; else bad "a: backup ada $_k"; fi
done
gb_restore >/dev/null 2>&1
assert_eq "a: restore cc" "$SNAP_CC" "$(rd "$A/proc/sys/net/ipv4/tcp_congestion_control")"
assert_eq "a: restore rmem" "$SNAP_RMEM" "$(rd "$A/proc/sys/net/core/rmem_max")"
assert_eq "a: restore wmem" "$SNAP_WMEM" "$(rd "$A/proc/sys/net/core/wmem_max")"
assert_eq "a: restore low_latency" "$SNAP_LL" "$(rd "$A/proc/sys/net/ipv4/tcp_low_latency")"
assert_eq "a: restore expire" "$SNAP_EXP" "$(rd "$A/proc/sys/vm/dirty_expire_centisecs")"
assert_eq "a: restore zram (aktif)" "$SNAP_ZRAM_ACT" "$(zram_active "$A/sys/block/zram0/comp_algorithm")"

# ---------- skenario (b): zram read-only ----------
printf '%s\n' "--- skenario (b): zram comp_algorithm read-only ---"
B=$(mktemp -d) || exit 1
mk_fakefs "$B"
chmod 444 "$B/sys/block/zram0/comp_algorithm"
gb_env "$B"
printf 'extreme' > "$B/conf/GAMEBOOST_LEVEL"
gb_apply >/dev/null 2>&1
assert_eq "b: gb_apply exit 0 (zram SKIP bukan gagal)" "0" "$?"
assert_eq "b: zram tak berubah" "lzo lz4 [zstd]" "$(cat "$B/sys/block/zram0/comp_algorithm")"
assert_eq "b: cc tetap applied" "bbr" "$(rd "$B/proc/sys/net/ipv4/tcp_congestion_control")"
assert_eq "b: expire tetap applied" "1500" "$(rd "$B/proc/sys/vm/dirty_expire_centisecs")"
if grep -q "ZRAM.*runtime-locked\|ZRAM.*not writable" "$B/alpha.log" 2>/dev/null; then ok "b: log SKIP zram jelas"; else bad "b: log SKIP zram jelas"; fi

# ---------- skenario (c): cc tak-writable (SELinux) ----------
# chmod 444 TIDAK mempan di sandbox: _gb_write memang chmod-ulang file
# milik sendiri (benar di HP; di SELinux chmod-nya yang ditolak kernel).
# Simulasi penolakan kernel = symlink ke direktori: -e/-w true (tanpa
# chmod), printf gagal -> FAILED per-node, apply tetap lanjut.
printf '%s\n' "--- skenario (c): tcp_congestion_control tidak writable ---"
C=$(mktemp -d) || exit 1
mk_fakefs "$C"
mkdir -p "$C/nowrite"
rm -f "$C/proc/sys/net/ipv4/tcp_congestion_control"
ln -s "$C/nowrite" "$C/proc/sys/net/ipv4/tcp_congestion_control"
gb_env "$C"
printf 'extreme' > "$C/conf/GAMEBOOST_LEVEL"
gb_apply >/dev/null 2>&1
assert_eq "c: gb_apply exit 0 (lanjut walau cc gagal)" "0" "$?"
if grep -q "FAILED.*tcp_congestion_control" "$C/alpha.log" 2>/dev/null; then ok "c: log FAILED cc jelas"; else bad "c: log FAILED cc jelas"; fi
assert_eq "c: rmem tetap applied" "8388608" "$(rd "$C/proc/sys/net/core/rmem_max")"
assert_eq "c: wmem tetap applied" "425984" "$(rd "$C/proc/sys/net/core/wmem_max")"
gb_restore >/dev/null 2>&1
assert_eq "c: restore rmem persis" "4194304" "$(rd "$C/proc/sys/net/core/rmem_max")"

# ---------- skenario (d): idempoten ----------
printf '%s\n' "--- skenario (d): apply extreme 2x idempoten ---"
gb_env "$A"
printf 'extreme' > "$A/conf/GAMEBOOST_LEVEL"
gb_apply >/dev/null 2>&1
V1_CC=$(rd "$A/proc/sys/net/ipv4/tcp_congestion_control")
V1_RMEM=$(rd "$A/proc/sys/net/core/rmem_max")
V1_EXP=$(rd "$A/proc/sys/vm/dirty_expire_centisecs")
gb_apply >/dev/null 2>&1
assert_eq "d: cc sama" "$V1_CC" "$(rd "$A/proc/sys/net/ipv4/tcp_congestion_control")"
assert_eq "d: rmem sama (tak dobel-2x)" "$V1_RMEM" "$(rd "$A/proc/sys/net/core/rmem_max")"
assert_eq "d: expire sama" "$V1_EXP" "$(rd "$A/proc/sys/vm/dirty_expire_centisecs")"
gb_restore >/dev/null 2>&1
assert_eq "d: restore rmem snapshot (bukan 2x)" "4194304" "$(rd "$A/proc/sys/net/core/rmem_max")"

# ---------- skenario (e): balanced = restore-only ----------
printf '%s\n' "--- skenario (e): balanced restore-only ---"
E=$(mktemp -d) || exit 1
mk_fakefs "$E"
gb_env "$E"
printf 'extreme' > "$E/conf/GAMEBOOST_LEVEL"
gb_apply >/dev/null 2>&1
printf 'balanced' > "$E/conf/GAMEBOOST_LEVEL"
gb_apply >/dev/null 2>&1
assert_eq "e: cc kembali cubic" "cubic" "$(rd "$E/proc/sys/net/ipv4/tcp_congestion_control")"
assert_eq "e: rmem kembali" "4194304" "$(rd "$E/proc/sys/net/core/rmem_max")"
assert_eq "e: expire kembali" "3000" "$(rd "$E/proc/sys/vm/dirty_expire_centisecs")"
assert_eq "e: zram kembali (aktif)" "zstd" "$(zram_active "$E/sys/block/zram0/comp_algorithm")"

# ---------- skenario (f): MTK-like — hormati bbr3 + lz4kd ----------
printf '%s\n' "--- skenario (f): MTK-like, cc bbr3 + zram lz4kd dihormati ---"
F=$(mktemp -d) || exit 1
mk_fakefs "$F"
printf 'reno bbr bbr3 bic cubic westwood htcp' > "$F/proc/sys/net/ipv4/tcp_available_congestion_control"
printf 'bbr3' > "$F/proc/sys/net/ipv4/tcp_congestion_control"
printf 'lzo lzo-rle lz4 lz4hc lz4k [lz4kd] deflate zstd' > "$F/sys/block/zram0/comp_algorithm"
gb_env "$F"
printf 'extreme' > "$F/conf/GAMEBOOST_LEVEL"
gb_apply >/dev/null 2>&1
assert_eq "f: cc tetap bbr3 (bukan diturunkan ke bbr)" "bbr3" "$(rd "$F/proc/sys/net/ipv4/tcp_congestion_control")"
assert_eq "f: zram tetap lz4kd (lz4-family dihormati)" "lz4kd" "$(zram_active "$F/sys/block/zram0/comp_algorithm")"
assert_eq "f: node lain tetap applied (expire)" "1500" "$(rd "$F/proc/sys/vm/dirty_expire_centisecs")"
if grep -q "already lz4-family" "$F/alpha.log" 2>/dev/null; then ok "f: log skip lz4-family"; else bad "f: log skip lz4-family"; fi
if grep -q "cc already bbr3" "$F/alpha.log" 2>/dev/null; then ok "f: log cc already bbr3"; else bad "f: log cc already bbr3"; fi
rm -rf "$A" "$B" "$C" "$E" "$F"
printf '== hasil total: %s PASS, %s FAIL ==\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
