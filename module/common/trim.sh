#!/system/bin/sh
# Alpha Fusion - trim: `fstrim` semua partisi yang ter-mount (data, cache, metadata, system, vendor, ...).
# TRIM memberi tahu flash blok mana yang tidak dipakai, supaya penulisan berikutnya tidak melambat.
# Ide dari utilitas FSTrim milik AZenith; ditulis ulang. Manual saja (tidak terjadwal).
#
#   trim.sh [force]    force = abaikan penjagaan (game aktif / baterai rendah)
# Penjagaan: tidak jalan saat game aktif, dan tidak saat baterai < 15% bila tidak dipaksa.
# Keluaran: satu baris per partisi dari fstrim, lalu "OK: N partisi di-trim".

STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
PROC_MOUNTS="${ALPHA_PROC_MOUNTS:-/proc/mounts}"
BATT="${ALPHA_BATT_CAP:-/sys/class/power_supply/battery/capacity}"
LOG="${ALPHA_LOG_FILE:-$STATE_DIR/alpha.log}"
FSTRIM="${ALPHA_FSTRIM:-fstrim}"

_log() { printf '[%s] [TRIM] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$1" "$2" >> "$LOG" 2>/dev/null; }

if [ "$1" != force ]; then
    if [ -f "$STATE_DIR/.gh_active" ]; then echo "ERROR: game sedang aktif, coba setelah selesai (atau: trim force)"; exit 1; fi
    read -r _cap < "$BATT" 2>/dev/null
    case "$_cap" in ''|*[!0-9]*) ;; *)
        if [ "$_cap" -lt 15 ]; then echo "ERROR: baterai ${_cap}% terlalu rendah (atau: trim force)"; exit 1; fi ;;
    esac
fi

if ! command -v "$FSTRIM" >/dev/null 2>&1; then
    # cadangan: pemeliharaan idle bawaan Android (menjalankan fstrim juga)
    if command -v sm >/dev/null 2>&1 && sm idle-maint run >/dev/null 2>&1; then
        echo "OK: fstrim tidak ada, memakai sm idle-maint run"; _log APPLIED "sm idle-maint run"; exit 0
    fi
    echo "ERROR: fstrim tidak tersedia di perangkat ini"; exit 1
fi

_n=0
for _mp in /data /cache /metadata /system /vendor /product /system_ext /odm; do
    grep -q " $_mp " "$PROC_MOUNTS" 2>/dev/null || continue
    _out=$("$FSTRIM" -v "$_mp" 2>&1)
    if [ $? -eq 0 ]; then
        printf '%s\n' "${_out:-$_mp: ok}"; _n=$((_n + 1))
    else
        printf '%s: dilewati (%s)\n' "$_mp" "$(printf '%s' "$_out" | head -n 1)"
    fi
done
echo "OK: $_n partisi di-trim"
_log APPLIED "fstrim $_n partisi"
