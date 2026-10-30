#!/system/bin/sh
# Alpha Fusion - Overdrive: mode di atas Performa, mesin sendiri (tanpa Uperf / fas-rs).
#
#   overdrive.sh start [pkg]    mulai Overdrive untuk game (pkg kosong = game terdaftar yang sedang aktif)
#   overdrive.sh stop [alasan]  keluar, kembalikan semua nilai asli
#   overdrive.sh status         baris key=value (ovd, ovd_pkg, ovd_level, ovd_last)
#   overdrive.sh recover        pulihkan sisa state (boot / monitor restart): lanjutkan proses, kembalikan nilai
#   overdrive.sh _loop <pkg>    penjaga (dipanggil start, jangan dijalankan manual)
#
# Yang dilakukan saat aktif:
#   1. uperf + fas-rs dibekukan (SIGSTOP). Proses tetap hidup, tidak ada restart; CONT saat keluar.
#   2. Batas BAWAH frekuensi CPU (tiap policy) dan GPU (devfreq) dinaikkan, batas atas dibuka penuh.
#      Governor tidak disentuh. Semua nilai asli disimpan di .ovd_prev dan dikembalikan saat keluar.
#   3. Penjaga tiap 3 detik: suhu (turun ke level aman dulu, keluar bila lewat batas), baterai < 15%,
#      layar mati, game ditutup / ditinggalkan, proses yang dibekukan tetap beku.
#
# Aman-gagal: kalau penjaga mati, gh_tick (monitor) mendeteksi dan memanggil stop; saat boot recover jalan.
# CATATAN: /system/bin/sh di ROM ini 32-bit. Tidak ada aritmetika pada angka besar (frekuensi dibandingkan
#   sebagai string, urutan dari `sort -n`).

STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
OVD_ACTIVE="$STATE_DIR/.ovd_active"
OVD_PREV="$STATE_DIR/.ovd_prev"
OVD_PID="$STATE_DIR/.ovd_pid"
OVD_STOPPED="$STATE_DIR/.ovd_stopped"
OVD_LAST="$STATE_DIR/.ovd_last"
OVD_FG="$STATE_DIR/.hud_foreground_pkg"
CONF="$STATE_DIR/app.conf"
LOG_FILE="${ALPHA_LOG_FILE:-$STATE_DIR/alpha.log}"
CPUFREQ="${ALPHA_SYS_CPUFREQ:-/sys/devices/system/cpu/cpufreq}"
DEVFREQ="${ALPHA_SYS_DEVFREQ:-/sys/class/devfreq}"
THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
POWER="${SYSFS_POWER_PREFIX:-/sys/class/power_supply}"

OVD_TICK="${ALPHA_OVD_TICK:-3}"
OVD_CPU_FULL=100     # persen posisi dalam daftar frekuensi (0 = terendah, 100 = tertinggi); bisa diubah: OVD_CPU_PCT / OVD_GPU_PCT di app.conf
OVD_GPU_FULL=100     # catatan: fas-rs mode performa di game sudah mengunci CPU di maksimum, jadi Overdrive tidak boleh lebih rendah dari itu
OVD_CPU_MID=70
OVD_GPU_MID=65
OVD_CPU_SAFE=40
OVD_GPU_SAFE=40
OVD_BATT_MIN=15      # keluar bila baterai di bawah ini dan tidak di-charge
FG_GRACE_TICKS=7     # ~21 dtk app di depan bukan game ini

ovd_log() {
    printf '[%s] [OVERDRIVE] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$1" "$2" >> "$LOG_FILE" 2>/dev/null
}

num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

conf_int() {
    _ci=""
    [ -f "$CONF" ] && _ci=$(sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -n 1 | tr -d '[:space:]')
    num "$_ci" && printf '%s' "$_ci" || printf '%s' "$2"
}

# lantai Overdrive bisa disetel di app.conf (0-100); nilai di luar rentang diabaikan
_pc=$(conf_int OVD_CPU_PCT "$OVD_CPU_FULL"); [ "$_pc" -le 100 ] 2>/dev/null && OVD_CPU_FULL=$_pc
_pg=$(conf_int OVD_GPU_PCT "$OVD_GPU_FULL"); [ "$_pg" -le 100 ] 2>/dev/null && OVD_GPU_FULL=$_pg
# 0 = tanpa step-down (selalu full, mode gacor); 1 = step-down bertingkat
OVD_STEPDOWN=$(conf_int OVD_STEPDOWN 0)

rd() { _rd_v=""; [ -r "$1" ] || return 1; read -r _rd_v < "$1" 2>/dev/null; printf '%s' "$_rd_v"; }
wr() { printf '%s' "$2" > "$1" 2>/dev/null; }

# ---------------------------------------------------------------- suhu / baterai
batt_temp_dc() { rd "$POWER/battery/temp"; }          # 0,1 C
batt_cap() { rd "$POWER/battery/capacity"; }
batt_status() { rd "$POWER/battery/status"; }

soc_temp_c() {                                         # zona terpanas, derajat C bulat
    _sm=0
    for _z in "$THERMAL"/thermal_zone*; do
        [ -r "$_z/temp" ] || continue
        _zt=""; read -r _zt < "$_z/temp" 2>/dev/null
        case "$_zt" in ''|*[!0-9]*) continue ;; esac
        [ "$_zt" -ge 1000 ] 2>/dev/null && [ "$_zt" -lt 150000 ] 2>/dev/null || continue
        [ "$_zt" -gt "$_sm" ] && _sm=$_zt
    done
    printf '%s' $((_sm / 1000))
}

# Batas default sengaja DI ATAS suhu Performa (baterai Performa bisa 60+ C): Overdrive harus lebih
# panas dulu baru turun. Margin = jarak ke batas terdekat; turun bertahap: >6 penuh, <=6 sedang,
# <=2 aman, <=0 keluar. Naik kembali butuh +2 C (histeresis) supaya tidak bolak-balik.
# temp_state: 0 = boleh lanjut (margin di $_mg), 2 = keluar
temp_state() {
    _soc_max=$(conf_int OVD_SOC_MAX_C 105)
    _bat_max=$(conf_int OVD_BATT_MAX_C 70)
    _soc=$(soc_temp_c); num "$_soc" || _soc=0
    _bt=$(batt_temp_dc); num "$_bt" || _bt=0
    _bc=$((_bt / 10))
    # nilai ngawur (sensor error > 110 C) diabaikan
    [ "$_soc" -gt 110 ] && _soc=0
    [ "$_bc" -gt 110 ] && _bc=0
    _m1=$((_soc_max - _soc)); _m2=$((_bat_max - _bc))
    _mg=$_m1; [ "$_m2" -lt "$_mg" ] && _mg=$_m2
    [ "$_mg" -le 0 ] && return 2
    return 0
}

# level target dari margin dan level sekarang (histeresis)
level_for() {
    [ "$OVD_STEPDOWN" = 1 ] || { echo full; return; }
    _cur="$1"; _h=0
    [ "$_cur" != full ] && _h=2
    if [ "$_mg" -le 2 ]; then echo safe; return; fi
    if [ "$_cur" = safe ] && [ "$_mg" -le 4 ]; then echo safe; return; fi
    if [ "$_mg" -le 6 ]; then echo mid; return; fi
    if [ "$_cur" != full ] && [ "$_mg" -le $((6 + _h)) ]; then echo mid; return; fi
    echo full
}

lv_cpu() { case "$1" in full) echo "$OVD_CPU_FULL" ;; mid) echo "$OVD_CPU_MID" ;; *) echo "$OVD_CPU_SAFE" ;; esac; }
lv_gpu() { case "$1" in full) echo "$OVD_GPU_FULL" ;; mid) echo "$OVD_GPU_MID" ;; *) echo "$OVD_GPU_SAFE" ;; esac; }

screen_off() {
    command -v dumpsys >/dev/null 2>&1 || return 1
    _w=$(dumpsys power 2>/dev/null | grep -m1 -o 'mWakefulness=[A-Za-z]*')
    case "$_w" in 'mWakefulness=Asleep'|'mWakefulness=Dozing') return 0 ;; esac
    return 1
}

# ---------------------------------------------------------------- frekuensi
# pick "<daftar>" <persen> -> frekuensi pada posisi persen dalam urutan naik
pick_freq() {
    _pct="$2"
    _pl=$(printf '%s\n' $1 | sort -n 2>/dev/null | tr '\n' ' ')
    set -- $_pl
    _n=$#
    [ "$_n" -ge 1 ] || return 1
    _i=$(( ((_n - 1) * _pct) / 100 ))
    _k=0
    for _f in "$@"; do
        [ "$_k" -eq "$_i" ] && { printf '%s' "$_f"; return 0; }
        _k=$((_k + 1))
    done
    return 1
}

top_freq() { printf '%s\n' $1 | sort -n 2>/dev/null | tail -n 1; }

gpu_dir() {
    for _d in "$DEVFREQ"/*gpu*; do
        [ -f "$_d/min_freq" ] && [ -f "$_d/max_freq" ] && { printf '%s' "$_d"; return 0; }
    done
    return 1
}

# Simpan nilai asli sekali (kalau .ovd_prev sudah ada, jangan timpa: itu nilai asli sebelum crash).
save_prev() {
    [ -f "$OVD_PREV" ] && return 0
    : > "$OVD_PREV.tmp" 2>/dev/null || return 1
    for _p in "$CPUFREQ"/policy*; do
        [ -f "$_p/scaling_min_freq" ] || continue
        printf 'cpu|%s|%s|%s\n' "$_p" "$(rd "$_p/scaling_min_freq")" "$(rd "$_p/scaling_max_freq")" >> "$OVD_PREV.tmp"
    done
    _g=$(gpu_dir) && printf 'gpu|%s|%s|%s\n' "$_g" "$(rd "$_g/min_freq")" "$(rd "$_g/max_freq")" >> "$OVD_PREV.tmp"
    mv -f "$OVD_PREV.tmp" "$OVD_PREV"
}

# apply_floors <persen_cpu> <persen_gpu>; hanya menulis bila nilai berbeda. Return 1 kalau tidak ada yang bisa ditulis.
apply_floors() {
    _any=1
    for _p in "$CPUFREQ"/policy*; do
        [ -f "$_p/scaling_min_freq" ] || continue
        _av=$(rd "$_p/scaling_available_frequencies")
        [ -n "$_av" ] || continue
        _fl=$(pick_freq "$_av" "$1") || continue
        _mx=$(top_freq "$_av")
        [ "$(rd "$_p/scaling_max_freq")" = "$_mx" ] || wr "$_p/scaling_max_freq" "$_mx"
        [ "$(rd "$_p/scaling_min_freq")" = "$_fl" ] || wr "$_p/scaling_min_freq" "$_fl"
        _any=0
    done
    if _g=$(gpu_dir); then
        _av=$(rd "$_g/available_frequencies")
        if [ -n "$_av" ]; then
            _fl=$(pick_freq "$_av" "$2"); _mx=$(top_freq "$_av")
            if [ -n "$_fl" ] && [ -n "$_mx" ]; then
                [ "$(rd "$_g/max_freq")" = "$_mx" ] || wr "$_g/max_freq" "$_mx"
                [ "$(rd "$_g/min_freq")" = "$_fl" ] || wr "$_g/min_freq" "$_fl"
                _any=0
            fi
        fi
    fi
    return $_any
}

restore_prev() {
    [ -f "$OVD_PREV" ] || return 0
    while IFS='|' read -r _t _d _mn _mx; do
        [ -n "$_d" ] || continue
        case "$_t" in
            cpu) [ -d "$_d" ] || continue
                 num "$_mn" && wr "$_d/scaling_min_freq" "$_mn"     # turunkan min dulu, baru max
                 num "$_mx" && wr "$_d/scaling_max_freq" "$_mx" ;;
            gpu) [ -d "$_d" ] || continue
                 num "$_mn" && wr "$_d/min_freq" "$_mn"
                 num "$_mx" && wr "$_d/max_freq" "$_mx" ;;
        esac
    done < "$OVD_PREV"
    rm -f "$OVD_PREV"
}

# ---------------------------------------------------------------- bekukan / lanjutkan
freeze_engines() {
    _fz=""
    for _nm in uperf fas-rs; do
        for _pid in $(pidof "$_nm" 2>/dev/null); do
            kill -STOP "$_pid" 2>/dev/null && _fz="$_fz $_pid"
        done
    done
    printf '%s\n' "$_fz" > "$OVD_STOPPED" 2>/dev/null
}

# Proses yang lahir ulang (pid baru) ikut dibekukan; pid yang sudah beku dilewati.
keep_frozen() {
    _fz=$(cat "$OVD_STOPPED" 2>/dev/null)
    for _nm in uperf fas-rs; do
        for _pid in $(pidof "$_nm" 2>/dev/null); do
            case " $_fz " in *" $_pid "*) continue ;; esac
            kill -STOP "$_pid" 2>/dev/null && _fz="$_fz $_pid"
        done
    done
    printf '%s\n' "$_fz" > "$OVD_STOPPED" 2>/dev/null
}

thaw_engines() {
    for _pid in $(cat "$OVD_STOPPED" 2>/dev/null) $(pidof uperf fas-rs 2>/dev/null); do
        kill -CONT "$_pid" 2>/dev/null
    done
    rm -f "$OVD_STOPPED"
}

# ---------------------------------------------------------------- start / stop
ovd_alive() {
    [ -f "$OVD_PID" ] || return 1
    _op=$(rd "$OVD_PID")
    num "$_op" || return 1
    kill -0 "$_op" 2>/dev/null || return 1
    # pid bisa didaur ulang / zombie: pastikan memang penjaga Overdrive (zombie punya cmdline kosong)
    _oc=$(tr '\0' ' ' < "/proc/$_op/cmdline" 2>/dev/null)
    case "$_oc" in *_loop*) return 0 ;; esac
    return 1
}

do_stop() {
    _why="${1:-manual}"
    _was=0
    [ -f "$OVD_ACTIVE" ] || [ -f "$OVD_PREV" ] || [ -f "$OVD_STOPPED" ] && _was=1
    # ACTIVE dihapus lebih dulu: trap penjaga yang ikut terpicu lalu tidak mengerjakan apa-apa lagi
    rm -f "$OVD_ACTIVE"
    # penjaga dihentikan (kecuali yang memanggil adalah penjaga itu sendiri)
    if [ -f "$OVD_PID" ]; then
        _op=$(rd "$OVD_PID")
        [ "$_op" != "$$" ] && num "$_op" && kill "$_op" 2>/dev/null
    fi
    thaw_engines
    restore_prev
    rm -f "$OVD_ACTIVE" "$OVD_PID"
    if [ "$_was" = 1 ]; then
        printf '%s\n' "$_why" > "$OVD_LAST" 2>/dev/null
        ovd_log RESTORED "Overdrive selesai ($_why), nilai asli kembali, uperf/fas-rs dilanjutkan"
    fi
}

do_start() {
    _pkg="$1"
    if ovd_alive && [ -f "$OVD_ACTIVE" ]; then echo "OK: Overdrive sudah aktif"; return 0; fi
    # sisa state lama (crash): pulihkan dulu supaya nilai asli yang tersimpan benar
    [ -f "$OVD_PREV" ] || [ -f "$OVD_STOPPED" ] && do_stop recover
    if [ -z "$_pkg" ]; then
        _pkg=$(rd "$STATE_DIR/.gh_active")     # hanya game terdaftar yang sedang aktif
    fi
    case "$_pkg" in ''|*[!A-Za-z0-9._]*) echo "ERROR: buka game terdaftar dulu (Overdrive hanya untuk game)"; return 1 ;; esac
    [ -n "$(pidof "$_pkg" 2>/dev/null)" ] || { echo "ERROR: $_pkg belum jalan, buka gamenya dulu"; return 1; }
    _cap=$(batt_cap); _st=$(batt_status)
    if num "$_cap" && [ "$_cap" -lt "$OVD_BATT_MIN" ] && [ "$_st" != "Charging" ]; then
        echo "ERROR: baterai ${_cap}% terlalu rendah untuk Overdrive"; return 1
    fi
    temp_state; _ts=$?
    [ "$_ts" -ge 2 ] && { echo "ERROR: suhu terlalu tinggi untuk Overdrive"; return 1; }
    save_prev || { echo "ERROR: gagal menyimpan nilai asli"; return 1; }
    if ! apply_floors "$OVD_CPU_FULL" "$OVD_GPU_FULL"; then
        restore_prev; echo "ERROR: node frekuensi tidak bisa ditulis"; return 1
    fi
    freeze_engines
    printf '%s\nfull\n' "$_pkg" > "$OVD_ACTIVE"
    rm -f "$OVD_LAST" "$OVD_PID"
    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$0" _loop "$_pkg" </dev/null >/dev/null 2>&1 &
    else
        nohup sh "$0" _loop "$_pkg" </dev/null >/dev/null 2>&1 &
    fi
    # penjaga menulis pid-nya sendiri (setsid bisa mem-fork, jadi $! tidak bisa dipercaya)
    _w=0
    while [ ! -f "$OVD_PID" ] && [ "$_w" -lt 20 ]; do sleep 0.1; _w=$((_w + 1)); done
    if [ ! -f "$OVD_PID" ]; then
        do_stop "penjaga gagal start"
        echo "ERROR: penjaga Overdrive gagal start"; return 1
    fi
    ovd_log APPLIED "Overdrive aktif untuk $_pkg (uperf/fas-rs dibekukan, lantai CPU ${OVD_CPU_FULL}% GPU ${OVD_GPU_FULL}%)"
    echo "OK: Overdrive aktif ($_pkg)"
}

# ---------------------------------------------------------------- penjaga
do_loop() {
    _pkg="$1"
    echo "$$" > "$OVD_PID"
    # Hanya penjaga yang masih MEMILIKI .ovd_pid yang boleh membersihkan; penjaga lama yang baru
    # tersadar (sinyal diterima belakangan) tidak boleh mematikan Overdrive yang baru dimulai.
    trap '_me=$(rd "$OVD_PID"); if [ "$_me" = "$$" ] && [ -f "$OVD_ACTIVE" ]; then do_stop "penjaga berhenti"; fi; exit 0' TERM INT HUP
    _lv=full; _n=0; _away=0; _dead=0; _hot=0
    while :; do
        sleep "$OVD_TICK" & wait $!       # wait: sinyal TERM langsung ditangani, tidak menunggu sleep selesai
        _me=$(rd "$OVD_PID")
        [ "$_me" = "$$" ] || exit 0       # sudah digantikan penjaga lain
        [ -f "$OVD_ACTIVE" ] || exit 0
        _n=$((_n + 1))

        # game masih hidup? (2x berturut-turut supaya kedip tidak memutus)
        if [ -z "$(pidof "$_pkg" 2>/dev/null)" ]; then
            _dead=$((_dead + 1))
            [ "$_dead" -ge 2 ] && { do_stop "game ditutup"; exit 0; }
        else
            _dead=0
        fi

        # app di depan bukan game ini terlalu lama
        _fg=$(rd "$OVD_FG")
        if [ -n "$_fg" ] && [ "$_fg" != "$_pkg" ]; then
            _away=$((_away + 1))
            [ "$_away" -ge "$FG_GRACE_TICKS" ] && { do_stop "game ditinggalkan"; exit 0; }
        else
            _away=0
        fi

        # baterai
        _cap=$(batt_cap); _st=$(batt_status)
        if num "$_cap" && [ "$_cap" -lt "$OVD_BATT_MIN" ] && [ "$_st" != "Charging" ]; then
            do_stop "baterai ${_cap}%"; exit 0
        fi

        # suhu: level aman dulu, keluar bila lewat batas
        temp_state; _ts=$?
        if [ "$_ts" -ge 2 ]; then
            _hot=$((_hot + 1))
            [ "$_hot" -ge 2 ] && { do_stop "suhu tinggi"; exit 0; }
        else
            _hot=0
        fi
        _nl=$(level_for "$_lv")
        if [ "$_nl" != "$_lv" ]; then
            _old=$_lv; _lv=$_nl
            apply_floors "$(lv_cpu "$_lv")" "$(lv_gpu "$_lv")"
            printf '%s\n%s\n' "$_pkg" "$_lv" > "$OVD_ACTIVE"
            ovd_log WARN "suhu: Overdrive $_old -> $_lv (margin ${_mg} C)"
        else
            # skrip lain (apply profil) bisa menimpa lantai; tulis ulang bila berbeda
            apply_floors "$(lv_cpu "$_lv")" "$(lv_gpu "$_lv")"
        fi

        # tiap ~9 dtk: proses yang lahir ulang tetap dibekukan; tiap ~15 dtk: cek layar
        [ $((_n % 3)) -eq 0 ] && keep_frozen
        if [ $((_n % 5)) -eq 0 ] && screen_off; then do_stop "layar mati"; exit 0; fi
    done
}

do_status() {
    if [ -f "$OVD_ACTIVE" ] && ovd_alive; then
        _p=$(sed -n '1p' "$OVD_ACTIVE" 2>/dev/null); _l=$(sed -n '2p' "$OVD_ACTIVE" 2>/dev/null)
        printf 'ovd=1\novd_pkg=%s\novd_level=%s\n' "$_p" "$_l"
    else
        printf 'ovd=0\novd_pkg=\novd_level=\n'
    fi
    printf 'ovd_last=%s\n' "$(sed -n '1p' "$OVD_LAST" 2>/dev/null)"
}

do_recover() {
    if [ -f "$OVD_ACTIVE" ] && ovd_alive; then return 0; fi
    if [ -f "$OVD_ACTIVE" ] || [ -f "$OVD_PREV" ] || [ -f "$OVD_STOPPED" ]; then
        do_stop "pemulihan"
    fi
    return 0
}

case "$1" in
    start) do_start "$2" ;;
    stop) do_stop "${2:-manual}"; echo "OK: Overdrive berhenti" ;;
    status) do_status ;;
    recover) do_recover ;;
    _loop) do_loop "$2" ;;
    *) echo "Usage: overdrive.sh start [pkg] | stop [alasan] | status | recover"; exit 1 ;;
esac
