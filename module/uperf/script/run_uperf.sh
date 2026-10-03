#!/system/bin/sh
# Uperf safe-backend runner (bagian dari Alpha + Uperf Fusion)
# HANYA menjalankan binary `uperf` untuk thread/cgroup classification
# (foreground/background cpuset placement berdasarkan uperf.json).
# TIDAK ADA kode governor/scaling_min_freq/scaling_max_freq di sini -
# semua kontrol CPU freq/governor sepenuhnya milik Alpha (dan fas-rs jika ada).

BASEDIR="$(dirname $(readlink -f "$0"))"
. "$BASEDIR/pathinfo.sh"
. "$BASEDIR/libcommon.sh"
. "$BASEDIR/libcgroup.sh"
. "$BASEDIR/libuperf.sh"

if [ ! -f "$USER_PATH/uperf.json" ]; then
    log "[UPERF] uperf.json tidak ditemukan (chipset tidak didukung saat instalasi). Backend Uperf tidak dijalankan."
    exit 0
fi

if [ ! -x "$BIN_PATH/uperf" ]; then
    log "[UPERF] binary uperf tidak ditemukan/tidak executable. Backend Uperf tidak dijalankan."
    exit 0
fi

wait_until_login

# Batasan percobaan start (graceful degradation): kalau binary langsung exit
# (misal config chipset tidak kompatibel - terpantau error
# "powersave.trigger not specified" di Unisoc T606), JANGAN retry tanpa henti.
# Berhenti setelah 3x, log WARNING jelas sekali, dan nonaktifkan backend uperf
# untuk sesi ini. fas-rs & Alpha core tuning TIDAK terpengaruh (proses dan
# alur terpisah, service.sh tidak memakai set -e).
UPERF_MAX_START_ATTEMPTS=3
UPERF_START_RETRY_DELAY=3

# Cek apakah daemon uperf benar-benar hidup (lewat /proc saja, tanpa pidof/pgrep).
uperf_is_running() {
    for uperf_proc_dir in /proc/[0-9]*; do
        uperf_proc_pid="${uperf_proc_dir#/proc/}"
        case "$uperf_proc_pid" in
            *[!0-9]*) continue ;;
        esac
        [ "$uperf_proc_pid" = "$$" ] && continue
        if [ -f "$uperf_proc_dir/comm" ]; then
            read -r uperf_proc_comm < "$uperf_proc_dir/comm" 2>/dev/null
            [ "$uperf_proc_comm" = "uperf" ] && return 0
        fi
    done
    return 1
}

# Tulis ke initsvc.log (via log()) SEKALIGUS stdout (ditangkap redirect
# nohup service.sh / engine_manager.sh ke alpha.log).
uperf_warn() {
    log "[UPERF] $1"
    echo "[UPERF] $1"
}

UPERF_START_ATTEMPT=0
UPERF_STARTED=0
while [ "$UPERF_START_ATTEMPT" -lt "$UPERF_MAX_START_ATTEMPTS" ]; do
    UPERF_START_ATTEMPT=$((UPERF_START_ATTEMPT + 1))
    uperf_start
    if uperf_is_running; then
        UPERF_STARTED=1
        break
    fi
    uperf_warn "percobaan start ke-$UPERF_START_ATTEMPT gagal (proses uperf tidak hidup), coba lagi dalam $UPERF_START_RETRY_DELAY detik..."
    sleep "$UPERF_START_RETRY_DELAY"
done

if [ "$UPERF_STARTED" != "1" ]; then
    uperf_warn "uperf gagal start berulang, kemungkinan config chipset tidak kompatibel, backend uperf dinonaktifkan untuk sesi ini"
    exit 0
fi
log "[UPERF] backend uperf aktif (thread/cgroup classifier saja, governor & freq tidak disentuh)."
