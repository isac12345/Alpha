#!/system/bin/sh
# Alpha Fusion - hud_sample: metrik live untuk HUD di Alpha Control.
#
#   hud_sample.sh --once <pkg>   satu sampel (key=value), buat uji lewat `alphactl hud sample <pkg>`
#   hud_sample.sh --loop <pkg>   sampel tiap detik, tiap blok diakhiri baris "--"
#                                (APK membaca stream ini lewat satu proses su; berhenti sendiri
#                                 saat pembaca menutup pipa)
#
# CATATAN PENTING: /system/bin/sh (mksh) di sebagian ROM berhitung 32-bit. Timestamp frame (nanodetik,
#   14 digit) TIDAK BOLEH dihitung/dibandingkan di sini. Script hanya meneruskan timestamp mentah
#   (satu baris "lat=<ns> <ns> ..."); FPS dihitung di aplikasi (Kotlin, 64-bit).
#
# Keluaran:
#   lat       timestamp frame layer game (actualPresentTime, spasi-terpisah, maks 70); APK menghitung FPS-nya
#   fps_x10   FPS x10 dari jalur cadangan (counter/timestats), kosong bila jalur layer (lat) yang dipakai
#   last_ts   penanda perubahan jalur cadangan; APK mendeteksi frame macet bila nilainya sama
#   gpu       persen beban GPU, kosong bila node tidak dikenal di kernel ini
#   cpu       baris pertama /proc/stat (APK menghitung persen dari selisih antar sampel)
#   temp_mc   suhu baterai, soc_mc suhu zona termal terpanas (milli-derajat C)

STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
LAYER_CACHE="$STATE_DIR/.hud_layer"
SYS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
SYS_POWER="${SYSFS_POWER_PREFIX:-/sys/class/power_supply}"

# FPS cara Smollming: counter SurfaceFlinger 1013 (selisih per detik), fallback
# ke latency per layer kalau counter gagal/diam 3x berturut-turut.
CNT_PREV=""
CNT_TPREV=""
CNT_FAIL=0
ZERO_RUN=0
LAYER_FAIL=0
LIST_WAIT=0
LR_OUT=""
LR_N=0
PL_OUT=""
FL_LAT=""
TS_ON=0
TS_PREV=""
DBG_N=0
DBG_LOG="$STATE_DIR/hud_debug.log"
TICK_S=1
LIGHT=0   # 1 = app biasa (bukan game): sampling jarang, tanpa fallback berat
FL_RES=""
PL_LAYER=""
PL_RES=""
TS_RES=""

# Hasil lewat variabel SC_RES (bukan stdout): state counter harus hidup di
# proses loop, sedangkan $(...) berjalan di subshell dan membuang state.
sf_counter() {
    SC_RES=""
    _sc_g=""
    _sc_out=$(service call SurfaceFlinger 1013 2>/dev/null)
    [ -n "$_sc_out" ] && _sc_g=$(printf '%s' "$_sc_out" | sed -n 's/.*Parcel([[:space:]]*\([0-9a-fA-F]\{8\}\)[[:space:]]\+\([0-9a-fA-F]\{8\}\).*/\1 \2/p')
    set -- $_sc_g
    [ "$1" = "00000000" ] || { CNT_FAIL=$((CNT_FAIL + 1)); return 1; }
    _sc_c=$((0x$2)); CNT_FAIL=0
    _sc_p=$CNT_PREV; CNT_PREV=$_sc_c
    # selang NYATA dari /proc/uptime (centidetik): iterasi bisa molor, jangan asumsikan 1 dtk
    _sc_u=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)
    _sc_t=${_sc_u%.*}${_sc_u#*.}
    case "$_sc_t" in ''|*[!0-9]*) _sc_t="" ;; esac
    _sc_tp=$CNT_TPREV; CNT_TPREV=$_sc_t
    [ -n "$_sc_p" ] && [ "$_sc_c" -ge "$_sc_p" ] || return 1
    _sc_dt=$(( TICK_S * 100 ))
    [ -n "$_sc_t" ] && [ -n "$_sc_tp" ] && [ "$_sc_t" -gt "$_sc_tp" ] && _sc_dt=$(( _sc_t - _sc_tp ))
    SC_RES="$(( (_sc_c - _sc_p) * 1000 / _sc_dt )) $_sc_c"
}

# Daftar layer milik paket (tanpa baris pembantu "Background for"/"Bounds for"/"Dim ").
layer_list() {
    dumpsys SurfaceFlinger --list 2>/dev/null | grep -F "$1" | grep -v -E '^(Background for|Bounds for|Dim )'
}

# Kandidat berurut prioritas (maks 6): SurfaceView BLAST > SurfaceView > BLAST > lainnya.
# Game bisa punya lebih dari satu SurfaceView (mis. iklan/WebView), jadi tidak cukup
# mengambil satu saja: layer terbaik dipilih dari yang benar-benar punya frame.
layer_candidates() {
    _lc_all=$(layer_list "$1")
    [ -n "$_lc_all" ] || return 1
    {
        printf '%s\n' "$_lc_all" | grep -F "SurfaceView" | grep -F "BLAST"
        printf '%s\n' "$_lc_all" | grep -F "SurfaceView" | grep -v -F "BLAST"
        printf '%s\n' "$_lc_all" | grep -F "BLAST" | grep -v -F "SurfaceView"
        printf '%s\n' "$_lc_all" | grep -v -F "BLAST" | grep -v -F "SurfaceView"
    } | head -n "$([ "$LIGHT" = 1 ] && echo 2 || echo 6)"
}

# Timestamp frame mentah layer: kolom 2 (actualPresentTime) dari 70 baris terakhir
# `dumpsys SurfaceFlinger --latency`. Hanya uji teks (case), tanpa aritmetika pada nilai besar.
# Hasil: LR_OUT = timestamp dipisah spasi (satu per frame), LR_N = jumlah baris valid.
lat_rows() {
    LR_OUT=""
    LR_N=0
    _lr_out=$(dumpsys SurfaceFlinger --latency "$1" 2>/dev/null | tail -n 70)
    [ -n "$_lr_out" ] || return 1
    _lr_i=0
    while read -r _lr_a _lr_b _lr_c; do
        _lr_i=$((_lr_i + 1))
        [ "$_lr_i" -eq 1 ] && continue
        case "$_lr_b" in ''|0|9223372036854775807|*[!0-9]*) continue ;; esac
        LR_OUT="$LR_OUT $_lr_b"
        LR_N=$((LR_N + 1))
    done <<EOF
$_lr_out
EOF
    [ "$LR_N" -ge 3 ]
}

# Bilangan bulat pertama dari isi node (format beda antar vendor: "45", "45 %", "46@800000000Hz", "36 36 4")
first_int() {
    [ -r "$1" ] || return 1
    _fi=$(head -n 1 "$1" 2>/dev/null | tr -cs '0-9' ' ' | sed 's/^ *//' | cut -d' ' -f1)
    [ -n "$_fi" ] || return 1
    printf '%s' "$_fi"
}

GPU_PATH=""
gp_path() {
    [ -n "$GPU_PATH" ] && [ -d "$GPU_PATH" ] && return 0
    # node resmi dari deteksi Alpha (mis. /sys/class/devfreq/23100000.gpu)
    GPU_PATH=$(sed -n 's/^GPU_DEVFREQ_PATH="\(.*\)"/\1/p' "$STATE_DIR/detected.conf" 2>/dev/null | head -n 1)
    if [ -z "$GPU_PATH" ] || [ ! -d "$GPU_PATH" ]; then
        for _gp_d in /sys/class/devfreq/*gpu* /sys/class/kgsl/kgsl-3d0; do
            [ -d "$_gp_d" ] && { GPU_PATH="$_gp_d"; break; }
        done
    fi
    [ -n "$GPU_PATH" ] && [ -d "$GPU_PATH" ]
}

gpu_freq_mhz() {
    gp_path || return 1
    _gf=$(first_int "$GPU_PATH/cur_freq") || _gf=$(first_int "$GPU_PATH/devfreq/cur_freq") || return 1
    if [ "$_gf" -ge 10000000 ]; then _gf=$((_gf / 1000000))
    elif [ "$_gf" -ge 10000 ]; then _gf=$((_gf / 1000)); fi
    printf '%s' "$_gf"
}

gpu_load() {
    _g_nodes="/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage
        /sys/class/kgsl/kgsl-3d0/devfreq/gpu_load /sys/kernel/gpu/gpu_busy
        /sys/kernel/ged/hal/gpu_utilization /sys/kernel/debug/ged/hal/gpu_utilization
        /sys/module/ged/parameters/gpu_loading /proc/mtk_mali/gpu_utilization
        /sys/class/misc/mali0/device/utilization /sys/class/misc/mali0/device/gpu_utilization
        /proc/mali/utilization"
    gp_path && _g_nodes="$_g_nodes $GPU_PATH/load $GPU_PATH/utilization $GPU_PATH/gpu_load
        $GPU_PATH/device/utilization $GPU_PATH/device/gpu_utilization"
    for _g_n in $_g_nodes /sys/class/devfreq/*gpu*/load /sys/class/devfreq/*gpu*/utilisation \
        /sys/class/devfreq/*mali*/load; do
        _g_v=$(first_int "$_g_n") && { printf '%s' "$_g_v"; return 0; }
    done
    # Adreno: gpubusy = "busy total" (selisih interval), lainnya persen langsung
    if [ -r /sys/class/kgsl/kgsl-3d0/gpubusy ]; then
        read -r _g_b _g_t < /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null
        case "$_g_b$_g_t" in ''|*[!0-9]*) ;; *)
            [ "$_g_t" -gt 0 ] && { printf '%s' $((_g_b * 100 / _g_t)); return 0; }
        ;; esac
    fi
    return 1
}

soc_temp_mc() {
    _st_max=0
    for _st_z in "$SYS_THERMAL"/thermal_zone*; do
        [ -r "$_st_z/temp" ] || continue
        read -r _st_v < "$_st_z/temp" 2>/dev/null
        case "$_st_v" in ''|*[!0-9-]*) continue ;; esac
        [ "${_st_v#-}" -le 1000 ] 2>/dev/null && _st_v=$((_st_v * 1000))
        [ "$_st_v" -ge 0 ] 2>/dev/null || continue
        [ "$_st_v" -lt 125000 ] 2>/dev/null || continue
        [ "$_st_v" -gt "$_st_max" ] && _st_max=$_st_v
    done
    printf '%s' "$_st_max"
}

batt_temp_mc() {
    read -r _bt < "$SYS_POWER/battery/temp" 2>/dev/null
    case "$_bt" in ''|*[!0-9-]*) printf '0' ;; *) printf '%s' $((_bt * 100)) ;; esac
}

# Pilih layer terbaik: yang punya frame terbanyak (urutan prioritas menang bila seri).
# Hasil lewat PL_LAYER / PL_OUT (bukan stdout, supaya state tidak hilang di subshell).
pick_layer() {
    PL_LAYER=""
    PL_OUT=""
    _pl_bn=0
    _pl_cands=$(layer_candidates "$1") || return 1
    while IFS= read -r _pl_l; do
        [ -n "$_pl_l" ] || continue
        lat_rows "$_pl_l" || continue
        if [ "$LR_N" -gt "$_pl_bn" ]; then
            _pl_bn=$LR_N
            PL_LAYER=$_pl_l
            PL_OUT=$LR_OUT
        fi
    done <<EOF
$_pl_cands
EOF
    [ -n "$PL_LAYER" ]
}

# Timestamp frame layer app. Hasil di FL_LAT (baris "lat=...") atau kosong.
fps_layer() {
    _fl_pkg="$1"
    FL_LAT=""
    _fl_layer=""
    command -v dumpsys >/dev/null 2>&1 || return 1
    if [ -f "$LAYER_CACHE" ]; then
        IFS='|' read -r _fl_cp _fl_cl < "$LAYER_CACHE"
        [ "$_fl_cp" = "$_fl_pkg" ] && _fl_layer="$_fl_cl"
    fi
    if [ -n "$_fl_layer" ] && lat_rows "$_fl_layer"; then
        FL_LAT=$LR_OUT
    else
        # layer basi (game restart ganti nomor layer) atau belum pernah dicari.
        # Mendaftar ulang layer itu berat: paling sering sekali per 3 sampel.
        if [ "$LIST_WAIT" -le 0 ]; then
            if [ "$LIGHT" = 1 ]; then LIST_WAIT=15; else LIST_WAIT=3; fi
            if pick_layer "$_fl_pkg"; then
                printf '%s|%s\n' "$_fl_pkg" "$PL_LAYER" > "$LAYER_CACHE" 2>/dev/null
                FL_LAT=$PL_OUT
            else
                rm -f "$LAYER_CACHE" 2>/dev/null
            fi
        else
            LIST_WAIT=$((LIST_WAIT - 1))
        fi
    fi
    [ -n "$FL_LAT" ]
}

# Cadangan terakhir: statistik frame SurfaceFlinger per layer (--timestats), dipakai RaiRin juga.
# totalFrames tiap layer milik paket dijumlahkan, FPS = selisih per sampel (jeda ~1 detik).
# Hasil di TS_RES ("<fps_x10> <totalFrames>" atau kosong).
ts_fps() {
    TS_RES=""
    _tf_pkg="$1"
    if [ "$TS_ON" -eq 0 ]; then
        dumpsys SurfaceFlinger --timestats -enable >/dev/null 2>&1
        TS_ON=1
    fi
    _tf_out=$(dumpsys SurfaceFlinger --timestats -dump 2>/dev/null)
    [ -n "$_tf_out" ] || return 1
    _tf_max=0
    _tf_in=0
    while IFS= read -r _tf_l; do
        case "$_tf_l" in
            *layerName*) case "$_tf_l" in *"$_tf_pkg"*) _tf_in=1 ;; *) _tf_in=0 ;; esac ;;
            *totalFrames*)
                [ "$_tf_in" -eq 1 ] || continue
                _tf_v=${_tf_l##*=}
                _tf_v=$(printf '%s' "$_tf_v" | tr -cd '0-9')
                [ -n "$_tf_v" ] && [ "$_tf_v" -gt "$_tf_max" ] && _tf_max=$_tf_v
                ;;
        esac
    done <<EOF
$_tf_out
EOF
    [ "$_tf_max" -gt 0 ] || return 1
    _tf_p=$TS_PREV
    TS_PREV=$_tf_max
    [ -n "$_tf_p" ] && [ "$_tf_max" -ge "$_tf_p" ] || return 1
    # lompatan besar = daftar layer berubah (bukan frame sungguhan): buang, jangan tampilkan angka ngawur
    [ $((_tf_max - _tf_p)) -le 500 ] || return 1
    TS_RES="$(( (_tf_max - _tf_p) * 10 )) $_tf_max"
    return 0
}

# Jejak diagnosa: hanya ditulis saat FPS belum terbaca, jarang (tiap 15 sampel), dan dibatasi 64 KB.
dbg_dump() {
    DBG_N=$((DBG_N + 1))
    [ $((DBG_N % 15)) -eq 1 ] || return 0
    _db_sz=$(wc -c < "$DBG_LOG" 2>/dev/null)
    [ -n "$_db_sz" ] && [ "$_db_sz" -gt 65536 ] && return 0
    {
        printf '=== %s pkg=%s cnt_fail=%s layer_fail=%s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "$1" "$CNT_FAIL" "$LAYER_FAIL"
        _db_c=$(layer_candidates "$1" 2>/dev/null)
        printf 'kandidat:\n%s\n' "$_db_c"
        _db_first=$(printf '%s\n' "$_db_c" | head -n 1)
        if [ -n "$_db_first" ]; then
            printf 'latency (4 baris) layer pertama:\n'
            dumpsys SurfaceFlinger --latency "$_db_first" 2>&1 | head -n 4
        fi
        printf 'timestats (baris layerName/totalFrames milik pkg):\n'
        dumpsys SurfaceFlinger --timestats -dump 2>&1 | grep -F -A1 "$1" | head -n 6
    } >> "$DBG_LOG" 2>/dev/null
}

sample() {
    _s_pkg="$1"
    _s_fps=""
    _s_lat=""
    if [ -n "$_s_pkg" ]; then
        if [ "$CNT_FAIL" -lt 3 ]; then
            sf_counter; _s_cnt=$SC_RES
            case "$_s_cnt" in
                "") ;;
                "0 "*)
                    ZERO_RUN=$((ZERO_RUN + 1))
                    if [ "$ZERO_RUN" -ge 3 ]; then
                        # counter diam 3x: coba layer; kalau layer punya frame, counter dianggap tidak dipakai.
                        if fps_layer "$_s_pkg"; then CNT_FAIL=3; _s_lat=$FL_LAT; else _s_fps=$_s_cnt; fi
                        ZERO_RUN=0
                    else
                        _s_fps=$_s_cnt
                    fi
                    ;;
                *) ZERO_RUN=0; _s_fps=$_s_cnt ;;
            esac
        fi
        if [ "$CNT_FAIL" -ge 3 ] && [ -z "$_s_lat" ]; then
            if fps_layer "$_s_pkg"; then
                _s_lat=$FL_LAT
                LAYER_FAIL=0
            else
                LAYER_FAIL=$((LAYER_FAIL + 1))
                if [ "$LAYER_FAIL" -ge 3 ] && [ "$LIGHT" != 1 ]; then
                    ts_fps "$_s_pkg" && _s_fps=$TS_RES
                    [ -n "$_s_fps" ] || dbg_dump "$_s_pkg"
                fi
            fi
        fi
    fi
    set -- $_s_fps
    printf 'fps_x10=%s\nlast_ts=%s\n' "${1:-}" "${2:-}"
    printf 'pkg=%s\n' "$_s_pkg"
    printf 'lat=%s\n' "$_s_lat"
    printf 'gpu=%s\n' "$(gpu_load || printf '%s' '--')"
    printf 'gpu_freq=%s\n' "$(gpu_freq_mhz || printf '%s' '--')"
    read -r _s_cpu < /proc/stat 2>/dev/null
    printf 'cpu=%s\n' "$_s_cpu"
    printf 'temp_mc=%s\nsoc_mc=%s\n' "$(batt_temp_mc)" "$(soc_temp_mc)"
}

# matikan timestats yang kita nyalakan sendiri (jangan dibiarkan aktif terus di SurfaceFlinger)
trap '[ "$TS_ON" = 1 ] && dumpsys SurfaceFlinger --timestats -disable >/dev/null 2>&1; exit 0' EXIT HUP INT TERM

case "$1" in
    --once) CNT_FAIL=3; sample "$2" ;;   # satu sampel: counter butuh dua titik, jadi langsung jalur layer
    --loop)
        # "--loop auto [cadangan]": paket diikuti otomatis dari app yang sedang di depan
        # (ditulis monitor.sh ke .hud_foreground_pkg), jadi satu proses cukup untuk game
        # maupun launcher/browser/sosmed. Ganti paket = reset cache layer, tanpa proses baru.
        _lp_pkg="$2"; _lp_auto=0; _lp_fb="$3"; _lp_last=""
        [ "$2" = "auto" ] && _lp_auto=1
        while :; do
            if [ "$_lp_auto" = 1 ]; then
                _lp_pkg=""
                read -r _lp_pkg < "$STATE_DIR/.hud_foreground_pkg" 2>/dev/null
                [ -n "$_lp_pkg" ] || _lp_pkg="$_lp_fb"
                if [ "$_lp_pkg" != "$_lp_last" ]; then
                    _lp_last="$_lp_pkg"
                    CNT_FAIL=3; ZERO_RUN=0; LAYER_FAIL=0; LIST_WAIT=0; TS_PREV=""; _lp_back=0
                    rm -f "$LAYER_CACHE" 2>/dev/null
                fi
            fi
            # game (ditandai .gh_active) = tiap 1 dtk; app lain = tiap 2 dtk dan ringan,
            # supaya dumpsys SurfaceFlinger tidak membuat Play Store/sosmed tersendat
            LIGHT=1; _lp_slp=2; [ "${_lp_back:-0}" = 1 ] && _lp_slp=5
            read -r _lp_gm < "$STATE_DIR/.gh_active" 2>/dev/null
            [ -n "$_lp_gm" ] && [ "$_lp_gm" = "$_lp_pkg" ] && { LIGHT=0; _lp_slp=1; }
            [ "$_lp_auto" = 1 ] || { LIGHT=0; _lp_slp=1; }
            TICK_S=$_lp_slp
            _lp_u0=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)
            sample "$_lp_pkg" || exit 0
            echo "--" || exit 0
            # sampel lambat (>=0,6 dtk) = SurfaceFlinger sedang berat: di app non-game mundur ke 5 dtk
            if [ "$LIGHT" = 1 ]; then
                _lp_u1=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)
                _lp_c0=${_lp_u0%.*}${_lp_u0#*.}; _lp_c1=${_lp_u1%.*}${_lp_u1#*.}
                case "$_lp_c0$_lp_c1" in ''|*[!0-9]*) ;; *)
                    [ $((_lp_c1 - _lp_c0)) -ge 60 ] && { _lp_back=1; _lp_slp=5; } ;;
                esac
            fi
            sleep "$_lp_slp"
        done
        ;;
    *) echo "Usage: hud_sample.sh --once|--loop <package|auto>"; exit 1 ;;
esac
