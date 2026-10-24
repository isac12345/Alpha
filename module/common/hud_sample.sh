#!/system/bin/sh
# Alpha Fusion - hud_sample: metrik live untuk HUD di Alpha Control.
#
#   hud_sample.sh --once <pkg>   satu sampel (key=value), buat uji lewat `alphactl hud sample <pkg>`
#   hud_sample.sh --loop <pkg>   sampel tiap detik, tiap blok diakhiri baris "--"
#                                (APK membaca stream ini lewat satu proses su; berhenti sendiri
#                                 saat pembaca menutup pipa)
#
# Keluaran:
#   fps_x10   FPS x10 dari timestamp frame layer game (dumpsys SurfaceFlinger --latency); kosong bila layer tidak ketemu
#   last_ts   timestamp frame terakhir; APK memakainya untuk mendeteksi frame macet (nilai sama = fps 0)
#   gpu       persen beban GPU, kosong bila node tidak dikenal di kernel ini
#   cpu       baris pertama /proc/stat (APK menghitung persen dari selisih antar sampel)
#   temp_mc   suhu baterai, soc_mc suhu zona termal terpanas (milli-derajat C)

STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
LAYER_CACHE="$STATE_DIR/.hud_layer"
SYS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
SYS_POWER="${SYSFS_POWER_PREFIX:-/sys/class/power_supply}"
INT64_MAX=9223372036854775807

# FPS cara Smollming: counter SurfaceFlinger 1013 (selisih per detik), fallback
# ke latency per layer kalau counter gagal/diam 3x berturut-turut.
CNT_PREV=""
CNT_FAIL=0
ZERO_RUN=0

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
    [ -n "$_sc_p" ] && [ "$_sc_c" -ge "$_sc_p" ] || return 1
    SC_RES="$(( (_sc_c - _sc_p) * 10 )) $_sc_c"
}

find_layer() {
    _fl_list=$(dumpsys SurfaceFlinger --list 2>/dev/null)
    _fl=""
    # urutan: SurfaceView BLAST (konten game) > SurfaceView > layer BLAST app > layer apa pun milik app
    _fl=$(printf '%s\n' "$_fl_list" | grep -F "SurfaceView" | grep -F "$1" | grep -F "BLAST" | tail -n 1)
    [ -n "$_fl" ] || _fl=$(printf '%s\n' "$_fl_list" | grep -F "SurfaceView" | grep -F "$1" | tail -n 1)
    [ -n "$_fl" ] || _fl=$(printf '%s\n' "$_fl_list" | grep -F "$1" | grep -F "BLAST" | tail -n 1)
    [ -n "$_fl" ] || _fl=$(printf '%s\n' "$_fl_list" | grep -F "$1" | tail -n 1)
    printf '%s' "$_fl"
}

# stdout: "<fps_x10> <last_ts>" atau kosong
latency_fps() {
    _lf_out=$(dumpsys SurfaceFlinger --latency "$1" 2>/dev/null)
    [ -n "$_lf_out" ] || return 1
    _lf_max=0
    _lf_i=0
    while read -r _lf_a _lf_b _lf_c; do
        _lf_i=$((_lf_i + 1))
        [ "$_lf_i" -eq 1 ] && continue
        case "$_lf_b" in ''|0|"$INT64_MAX"|*[!0-9]*) continue ;; esac
        [ "$_lf_b" -gt "$_lf_max" ] && _lf_max=$_lf_b
    done <<EOF
$_lf_out
EOF
    [ "$_lf_max" -gt 0 ] || return 1
    _lf_lo=$((_lf_max - 1000000000))
    _lf_min=$_lf_max
    _lf_n=0
    _lf_i=0
    while read -r _lf_a _lf_b _lf_c; do
        _lf_i=$((_lf_i + 1))
        [ "$_lf_i" -eq 1 ] && continue
        case "$_lf_b" in ''|0|"$INT64_MAX"|*[!0-9]*) continue ;; esac
        [ "$_lf_b" -ge "$_lf_lo" ] || continue
        _lf_n=$((_lf_n + 1))
        [ "$_lf_b" -lt "$_lf_min" ] && _lf_min=$_lf_b
    done <<EOF
$_lf_out
EOF
    if [ "$_lf_n" -gt 1 ] && [ "$_lf_max" -gt "$_lf_min" ]; then
        printf '%s %s' $(( (_lf_n - 1) * 10000000000 / (_lf_max - _lf_min) )) "$_lf_max"
    else
        # bukan 0: data kurang = tidak tahu (HUD tampil "--", seperti Smollming)
        return 1
    fi
}

# Bilangan bulat pertama dari isi node (format beda antar vendor: "45", "45 %", "46@800000000Hz", "36 36 4")
first_int() {
    [ -r "$1" ] || return 1
    _fi=$(head -n 1 "$1" 2>/dev/null | tr -cs '0-9' ' ' | sed 's/^ *//' | cut -d' ' -f1)
    [ -n "$_fi" ] || return 1
    printf '%s' "$_fi"
}

gpu_load() {
    _g_kg=/sys/class/kgsl/kgsl-3d0
    # Adreno: gpubusy = "busy total" (selisih interval), lainnya persen langsung
    for _g_n in "$_g_kg/gpu_busy_percentage" "$_g_kg/devfreq/gpu_load" "/sys/kernel/gpu/gpu_busy" \
        /sys/kernel/ged/hal/gpu_utilization /sys/kernel/debug/ged/hal/gpu_utilization \
        /sys/module/ged/parameters/gpu_loading /proc/mtk_mali/gpu_utilization; do
        _g_v=$(first_int "$_g_n") && { printf '%s' "$_g_v"; return 0; }
    done
    for _g_n in /sys/class/devfreq/*gpu*/load /sys/class/devfreq/*gpu*/utilisation \
        /sys/class/devfreq/*gpu*/mali_ondemand/utilisation /sys/class/devfreq/*mali*/load; do
        _g_v=$(first_int "$_g_n") && { printf '%s' "$_g_v"; return 0; }
    done
    if [ -r "$_g_kg/gpubusy" ]; then
        read -r _g_b _g_t < "$_g_kg/gpubusy" 2>/dev/null
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

fps_layer() {
    _fl_pkg="$1"
    _fl_layer="" _fl_res=""
    command -v dumpsys >/dev/null 2>&1 || return 1
    if [ -f "$LAYER_CACHE" ]; then
        IFS='|' read -r _fl_cp _fl_cl < "$LAYER_CACHE"
        [ "$_fl_cp" = "$_fl_pkg" ] && _fl_layer="$_fl_cl"
    fi
    [ -n "$_fl_layer" ] && _fl_res=$(latency_fps "$_fl_layer")
    if [ -z "$_fl_res" ]; then
        # layer basi (game restart ganti nomor layer) atau belum pernah dicari
        _fl_layer=$(find_layer "$_fl_pkg")
        if [ -n "$_fl_layer" ]; then
            printf '%s|%s\n' "$_fl_pkg" "$_fl_layer" > "$LAYER_CACHE" 2>/dev/null
            _fl_res=$(latency_fps "$_fl_layer")
        fi
    fi
    [ -n "$_fl_res" ] || return 1
    printf '%s' "$_fl_res"
}

sample() {
    _s_pkg="$1"
    _s_fps=""
    if [ -n "$_s_pkg" ]; then
        if [ "$CNT_FAIL" -lt 3 ]; then
            sf_counter; _s_cnt=$SC_RES
            case "$_s_cnt" in
                "") [ "$CNT_FAIL" -ge 3 ] && _s_fps=$(fps_layer "$_s_pkg") ;;
                "0 "*)
                    ZERO_RUN=$((ZERO_RUN + 1))
                    if [ "$ZERO_RUN" -ge 3 ]; then
                        _s_fps=$(fps_layer "$_s_pkg")
                        case "$_s_fps" in
                            [1-9]*) CNT_FAIL=3 ;;
                            *) _s_fps=$_s_cnt ;;
                        esac
                        ZERO_RUN=0
                    else
                        _s_fps=$_s_cnt
                    fi
                    ;;
                *) ZERO_RUN=0; _s_fps=$_s_cnt ;;
            esac
        else
            _s_fps=$(fps_layer "$_s_pkg")
        fi
    fi
    set -- $_s_fps
    printf 'fps_x10=%s\nlast_ts=%s\n' "${1:-}" "${2:-}"
    printf 'gpu=%s\n' "$(gpu_load)"
    read -r _s_cpu < /proc/stat 2>/dev/null
    printf 'cpu=%s\n' "$_s_cpu"
    printf 'temp_mc=%s\nsoc_mc=%s\n' "$(batt_temp_mc)" "$(soc_temp_mc)"
}

case "$1" in
    --once) sample "$2" ;;
    --loop)
        while :; do
            sample "$2" || exit 0
            echo "--" || exit 0
            sleep 1
        done
        ;;
    *) echo "Usage: hud_sample.sh --once|--loop <package>"; exit 1 ;;
esac
