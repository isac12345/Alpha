#!/system/bin/sh
# Alpha Fusion - gamehooks: ekstra yang jalan selama game terdaftar di foreground.
# File ini LIBRARY (di-source oleh monitor.sh dan alphactl.sh), bukan CLI.
#
#   gh_foreground <pkg> <profil_peta>  tiap pindah foreground; profil_peta kosong = bukan game
#   gh_tick                            tiap siklus monitor: grace keluar game, prioritas ulang, bersih-bersih
#   gh_start <pkg> | gh_stop           dipanggil gh_foreground / gh_tick
#   gh_recover                         pulihkan semua state (boot, uninstall, monitor restart)
#   gh_launch <pkg>                    pasang render per game lalu buka game
#   gh_render_get|gh_render_set|gh_render_list   render per game (file game_render.conf)
#
# Isi yang dikerjakan:
#   1. Prioritas proses game (nice, ionice, oom_score_adj)  : default AKTIF, matikan dengan flag GAME_PRIO_OFF
#   2. DND otomatis                                         : default MATI, aktifkan dengan flag GAME_DND_ON
#   3. Refresh rate saat game                               : conf GAME_REFRESH_HZ (off | angka Hz), default off
#                                                              (SF backdoor + settings; GAME_REFRESH_SF_IDX=<n> memaksa indeks SF)
#   4. Render per game (hanya lewat tombol Luncurkan)       : file game_render.conf "package:backend"
#   5. Opsi per game (prioritas/DND/mode ringan)            : file game_opts.conf "package:KEY=nilai"
#        PRIO=on|off, DND=on|off (kosong = ikut global), LITE=1 (matikan semua ekstra untuk game ini),
#        HZ=off|<Hz> (refresh rate khusus game; kosong = ikut GAME_REFRESH_HZ global),
#        OVD=on (Overdrive otomatis tiap game ini dibuka, lihat overdrive.sh)
#
# Semua perubahan disimpan nilai aslinya dan dikembalikan saat keluar game (setelah grace).

GH_STATE="${ALPHA_STATE_DIR:-/data/adb/alpha}"
GH_MARK="$GH_STATE/.gh_active"
GH_PEND="$GH_STATE/.gh_pending"
GH_DND_PREV="$GH_STATE/.gh_dnd_prev"
GH_REF_PREV="$GH_STATE/.gh_refresh_prev"
GH_SF_MARK="$GH_STATE/.gh_sf_set"
GH_REND_PREV="$GH_STATE/.gh_render_prev"
GH_PRIO_T="$GH_STATE/.gh_prio_t"
GH_RENDER_MAP="$GH_STATE/game_render.conf"
GH_OPTS="$GH_STATE/game_opts.conf"
GH_MIT="$GH_STATE/device_mitigation.conf"
GH_GM_MARK="$GH_STATE/.gh_gm_pkg"
GH_ANGLE_PREV="$GH_STATE/.gh_angle_prev"
GH_PRELOAD_T="$GH_STATE/.gh_preload_t"
GH_CONF="$GH_STATE/app.conf"
GH_GRACE="${ALPHA_GB_GRACE:-12}"
GH_PRIO_EVERY=45
GH_RENDER_TIMEOUT=90

_gh_now() { date +%s 2>/dev/null; }

_gh_log() {
    printf '[%s] [GAMEHOOK] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$1" "$2" \
        >> "${ALPHA_LOG_FILE:-$GH_STATE/alpha.log}" 2>/dev/null
}

_gh_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

_gh_conf() {
    _ghc_v=""
    [ -f "$GH_CONF" ] && _ghc_v=$(sed -n "s/^$1=//p" "$GH_CONF" 2>/dev/null | tail -n 1)
    [ -n "$_ghc_v" ] && printf '%s' "$_ghc_v" || printf '%s' "$2"
}

# ---------------------------------------------------------------- 0. mitigasi per perangkat
# device_mitigation.conf: satu aturan per baris, "<pola> <fitur>", pola = glob (huruf besar/kecil sama)
# yang dicocokkan ke model/device/board/hardware perangkat. Fitur: prio dnd refresh gamemode
# downscale angle render, atau "all". Contoh:  m5* refresh   |   *t606* angle   |   rmx3* all
# Fitur juga bisa dimatikan sementara lewat file FEAT_<fitur>_OFF di folder state.
_gh_device_ids() {
    if [ -z "$_GH_IDS" ]; then
        _GH_IDS=$(for _ghp in ro.product.model ro.product.device ro.product.name ro.board.platform \
            ro.hardware ro.soc.model ro.product.board; do
            _ghv=$(getprop "$_ghp" 2>/dev/null | tr 'A-Z' 'a-z')
            [ -n "$_ghv" ] && printf '%s\n' "$_ghv"
        done)
    fi
    printf '%s\n' "$_GH_IDS"
}

# return 0 = fitur $1 DILARANG oleh aturan mitigasi
gh_mit_hit() {
    [ -f "$GH_MIT" ] || return 1
    while read -r _ghm_pat _ghm_ft _ghm_rest; do
        case "$_ghm_pat" in ''|'#'*) continue ;; esac
        case "$_ghm_ft" in "$1"|all) ;; *) continue ;; esac
        _ghm_pat=$(printf '%s' "$_ghm_pat" | tr 'A-Z' 'a-z')
        _gh_device_ids | while read -r _ghm_id; do
            case "$_ghm_id" in $_ghm_pat) exit 7 ;; esac
        done
        [ $? -eq 7 ] && return 0
    done < "$GH_MIT"
    return 1
}

# return 0 = fitur $1 BOLEH jalan
gh_feat_ok() {
    [ -f "$GH_STATE/FEAT_$1_OFF" ] && return 1
    gh_mit_hit "$1" && return 1
    return 0
}

gh_mit_list() { [ -f "$GH_MIT" ] && grep -v '^[[:space:]]*#' "$GH_MIT" | grep -v '^[[:space:]]*$'; return 0; }

gh_mit_add() {
    case "$1" in ''|*[!A-Za-z0-9._*?-]*) echo "ERROR: pola tidak valid (huruf, angka, . _ - * ?)"; return 1 ;; esac
    case "$2" in prio|dnd|refresh|gamemode|downscale|angle|render|preload|mglru|memclean|trim|all) ;;
        *) echo "ERROR: fitur harus salah satu: prio dnd refresh gamemode downscale angle render preload mglru memclean trim all"; return 1 ;; esac
    touch "$GH_MIT" 2>/dev/null
    # -F: pola berisi * dan ? harus dibaca apa adanya, bukan sebagai regex
    grep -Fqx "$1 $2" "$GH_MIT" 2>/dev/null || printf '%s %s\n' "$1" "$2" >> "$GH_MIT"
    echo "OK: $1 $2"
}

gh_mit_remove() {
    [ -f "$GH_MIT" ] || { echo "OK: tidak ada aturan"; return 0; }
    grep -Fvx "$1 $2" "$GH_MIT" > "$GH_MIT.tmp.$$" 2>/dev/null
    mv -f "$GH_MIT.tmp.$$" "$GH_MIT"
    echo "OK: dihapus $1 $2"
}

# fitur apa saja yang dimatikan di perangkat ini
gh_mit_check() {
    for _ghc in prio dnd refresh gamemode downscale angle render preload mglru memclean trim; do
        gh_feat_ok "$_ghc" || echo "off:$_ghc"
    done
    return 0
}

# ---------------------------------------------------------------- 0. opsi per game
# File game_opts.conf: satu baris "package:KEY=nilai". Tidak ada baris = ikut pengaturan global.
_gh_opt() {
    [ -f "$GH_OPTS" ] || return 0
    sed -n "s/^$(_gh_re "$1"):$2=//p" "$GH_OPTS" 2>/dev/null | tail -n 1 | tr -d '[:space:]'
}

# $1=pkg $2=PRIO|DND -> status 0 bila fitur itu aktif untuk game ini
_gh_enabled() {
    [ "$(_gh_opt "$1" LITE)" = "1" ] && return 1
    case "$(_gh_opt "$1" "$2")" in
        on) return 0 ;;
        off) return 1 ;;
    esac
    case "$2" in
        PRIO) [ -f "$GH_STATE/GAME_PRIO_OFF" ] && return 1; return 0 ;;
        DND) [ -f "$GH_STATE/GAME_DND_ON" ]; return $? ;;
    esac
    return 1
}

# $1=pkg $2=PRIO|DND|LITE $3=on|off|1|default (default = hapus, ikut global)
gh_opt_set() {
    case "$1" in ''|*[!A-Za-z0-9._]*) echo "ERROR: package tidak valid"; return 1 ;; esac
    case "$2" in
        PRIO|DND) case "$3" in on|off|default) ;; *) echo "ERROR: nilai $2 harus on|off|default"; return 1 ;; esac ;;
        LITE) case "$3" in 1|default) ;; *) echo "ERROR: nilai LITE harus 1|default"; return 1 ;; esac ;;
        OVD) case "$3" in on|default) ;; *) echo "ERROR: nilai OVD harus on|default"; return 1 ;; esac ;;
        HZ)
            case "$3" in
                off|default) ;;
                ''|*[!0-9]*) echo "ERROR: nilai HZ harus off|default|30-240"; return 1 ;;
                *) [ "$3" -ge 30 ] && [ "$3" -le 240 ] || { echo "ERROR: rentang HZ 30-240"; return 1; } ;;
            esac ;;
        gamemode)
            case "$3" in off|default|standard|performance|battery) ;; *) echo "ERROR: gamemode = off|standard|performance|battery"; return 1 ;; esac ;;
        downscale)
            case "$3" in off|default|0.[5-9]|0.[5-9][0-9]|1|1.0|1.00) ;; *) echo "ERROR: downscale = off atau 0.5 sampai 1.0"; return 1 ;; esac ;;
        fps)
            case "$3" in off|default) ;; ''|*[!0-9]*) echo "ERROR: fps = off atau angka 10 sampai 240"; return 1 ;;
                *) [ "$3" -ge 10 ] && [ "$3" -le 240 ] || { echo "ERROR: fps = off atau angka 10 sampai 240"; return 1; } ;; esac ;;
        preload)
            case "$3" in off|default|on) ;; *) echo "ERROR: preload = off|on"; return 1 ;; esac ;;
        *) echo "ERROR: opsi tidak dikenal (PRIO|DND|LITE|HZ|OVD|gamemode|downscale|fps|preload)"; return 1 ;;
    esac
    touch "$GH_OPTS" 2>/dev/null || { echo "ERROR: gagal tulis"; return 1; }
    grep -v "^$(_gh_re "$1"):$2=" "$GH_OPTS" > "$GH_OPTS.tmp.$$" 2>/dev/null
    _gos_rm=0
    [ "$3" = "default" ] && _gos_rm=1
    case "$2" in gamemode|downscale|fps|preload) [ "$3" = off ] && _gos_rm=1 ;; esac
    [ "$_gos_rm" = 1 ] || printf '%s:%s=%s\n' "$1" "$2" "$3" >> "$GH_OPTS.tmp.$$"
    mv -f "$GH_OPTS.tmp.$$" "$GH_OPTS" && echo "OK: $1 $2=$3"
}

# $1=pkg $2=kunci $3=bawaan -> nilai opsi (atau bawaan bila tidak diset)
gh_opt_get() {
    _gho=$(_gh_opt "$1" "$2")
    [ -n "$_gho" ] && printf '%s' "$_gho" || printf '%s' "$3"
}

# $1=pkg -> baris "KEY=nilai" untuk opsi yang diset khusus game ini
gh_opt_list() {
    [ -f "$GH_OPTS" ] || return 0
    sed -n "s/^$(_gh_re "$1")://p" "$GH_OPTS" 2>/dev/null
}

# ---------------------------------------------------------------- 1. prioritas
# nice thread dari /proc/<pid>/task/<tid>/stat (kolom 19). Nama proses bisa
# mengandung spasi/kurung, jadi buang semuanya sampai ") " terakhir dulu.
_gh_nice_of() {
    [ -r "$1" ] || return 1
    _ghn=$(sed 's/^.*) //' "$1" 2>/dev/null | cut -d' ' -f17)
    case "$_ghn" in ''|*[!0-9-]*) return 1 ;; esac
    printf '%s' "$_ghn"
}

# Terapkan hanya bila nice sekarang masih di atas target. Aman dipanggil
# berulang, dan tidak menumpuk walau renice versi ini memakai increment relatif.
_gh_renice_tid() {
    _ghr_cur=$(_gh_nice_of "/proc/$1/stat") || return 0
    [ "$_ghr_cur" -gt "$2" ] 2>/dev/null || return 0
    renice -n "$2" -p "$1" >/dev/null 2>&1
}

_gh_prio_apply() {
    _gh_enabled "$1" PRIO || return 0
    gh_feat_ok prio || return 0
    _ghp_pids=$(pidof "$1" 2>/dev/null)
    [ -n "$_ghp_pids" ] || return 0
    for _ghp_pid in $_ghp_pids; do
        [ -d "/proc/$_ghp_pid" ] || continue
        _gh_renice_tid "$_ghp_pid" -10
        ionice -c 2 -n 0 -p "$_ghp_pid" >/dev/null 2>&1
        if [ -w "/proc/$_ghp_pid/oom_score_adj" ]; then
            _ghp_oom=$(tr -d '[:space:]' < "/proc/$_ghp_pid/oom_score_adj" 2>/dev/null)
            case "$_ghp_oom" in ''|*[!0-9-]*) ;; *)
                [ "$_ghp_oom" -gt -300 ] 2>/dev/null && printf '%s' "-300" 2>/dev/null > "/proc/$_ghp_pid/oom_score_adj"
            ;; esac
        fi
        # thread render/game saja, bukan semua thread (thread kerja lain biarkan scheduler)
        for _ghp_t in /proc/"$_ghp_pid"/task/*; do
            [ -r "$_ghp_t/comm" ] || continue
            _ghp_tid=${_ghp_t##*/}
            [ "$_ghp_tid" = "$_ghp_pid" ] && continue
            read -r _ghp_c < "$_ghp_t/comm" 2>/dev/null
            case "$_ghp_c" in
                RenderThread*|UnityMain*|UnityGfx*|GameThread*|RHIThread*|RenderingThread*|Thread-*Render*)
                    _gh_renice_tid "$_ghp_tid" -8 ;;
            esac
        done
    done
}

# ---------------------------------------------------------------- 2. DND
_gh_dnd_on() {
    _gh_enabled "$1" DND || return 0
    gh_feat_ok dnd || return 0
    [ -f "$GH_DND_PREV" ] && return 0
    command -v settings >/dev/null 2>&1 || return 0
    _ghd=$(settings get global zen_mode 2>/dev/null | tr -d '\r\n[:space:]')
    # DND sudah dinyalakan pengguna sendiri: jangan disentuh dan jangan dimatikan nanti.
    [ "$_ghd" = "0" ] || [ -z "$_ghd" ] || [ "$_ghd" = "null" ] || return 0
    printf '%s\n' "0" > "$GH_DND_PREV" 2>/dev/null
    if cmd notification set_dnd priority >/dev/null 2>&1; then
        _gh_log APPLIED "DND prioritas aktif"
    elif settings put global zen_mode 1 >/dev/null 2>&1; then
        _gh_log APPLIED "DND prioritas aktif (settings)"
    else
        rm -f "$GH_DND_PREV"
        _gh_log WARN "DND gagal diaktifkan"
    fi
}

_gh_dnd_off() {
    [ -f "$GH_DND_PREV" ] || return 0
    rm -f "$GH_DND_PREV"
    command -v settings >/dev/null 2>&1 || return 0
    _ghd=$(settings get global zen_mode 2>/dev/null | tr -d '\r\n[:space:]')
    # Hanya matikan bila masih mode yang kita pasang (1). Kalau pengguna sudah
    # mengubahnya sendiri selama game, biarkan.
    [ "$_ghd" = "1" ] || return 0
    cmd notification set_dnd off >/dev/null 2>&1 || settings put global zen_mode 0 >/dev/null 2>&1
    _gh_log RESTORED "DND dimatikan"
}

# ---------------------------------------------------------------- 3. refresh rate
# Cara utama = backdoor SurfaceFlinger (service call 1035 i32 <indeks mode>, -1 = auto), sama
# seperti Rairin. Pelapis = settings system min/peak_refresh_rate. Nilai settings asli disimpan
# dan dikembalikan; saat SF dipakai, restore juga menendang ke 60Hz sebentar supaya
# DisplayManager menghitung ulang (urutan yang sama dengan Rairin refresh.sh).

# Pembulatan "119.99" -> 120, "60.000004" -> 60
_gh_round_hz() {
    _gr_i=${1%%.*}
    case "$_gr_i" in ''|*[!0-9]*) return 1 ;; esac
    case "$1" in
        *.*) _gr_f=${1#*.}; _gr_f=${_gr_f%"${_gr_f#?}"}
             case "$_gr_f" in [5-9]) _gr_i=$((_gr_i + 1)) ;; esac ;;
    esac
    printf '%s' "$_gr_i"
}

# "<id> <hz>" per mode, tanpa duplikat, dari `dumpsys SurfaceFlinger`. Format baris DisplayMode
# beda antar versi Android (vsyncRate=90.0 Hz / refreshRate=90.0 / fps=90.0), jadi dibaca longgar.
gh_sf_modes() {
    command -v dumpsys >/dev/null 2>&1 || return 0
    _gm_seen=" "
    dumpsys SurfaceFlinger 2>/dev/null | grep 'DisplayMode' | grep -v 'activeMode' | while read -r _gm_l; do
        _gm_id=$(printf '%s\n' "$_gm_l" | sed -n 's/.*[( ,{]id=\([0-9][0-9]*\).*/\1/p' | head -n 1)
        [ -n "$_gm_id" ] || continue
        case "$_gm_seen" in *" $_gm_id "*) continue ;; esac
        _gm_v=$(printf '%s\n' "$_gm_l" | sed -n 's/.*\(vsyncRate\|refreshRate\|fps\)=\([0-9][0-9]*\(\.[0-9]*\)\{0,1\}\).*/\2/p' | head -n 1)
        [ -n "$_gm_v" ] || _gm_v=$(printf '%s\n' "$_gm_l" | sed -n 's/.*[ =]\([0-9][0-9]*\(\.[0-9]*\)\{0,1\}\) Hz.*/\1/p' | head -n 1)
        [ -n "$_gm_v" ] || continue
        _gm_hz=$(_gh_round_hz "$_gm_v") || continue
        _gm_seen="$_gm_seen$_gm_id "
        printf '%s %s\n' "$_gm_id" "$_gm_hz"
    done
}

# Hz mode yang sedang aktif menurut SF (kosong bila tidak terbaca)
gh_sf_active_hz() {
    command -v dumpsys >/dev/null 2>&1 || return 0
    _ga_l=$(dumpsys SurfaceFlinger 2>/dev/null | grep 'activeMode' | grep 'DisplayMode' | head -n 1)
    [ -n "$_ga_l" ] || return 0
    _ga_v=$(printf '%s\n' "$_ga_l" | sed -n 's/.*\(vsyncRate\|refreshRate\|fps\)=\([0-9][0-9]*\(\.[0-9]*\)\{0,1\}\).*/\2/p' | head -n 1)
    [ -n "$_ga_v" ] || _ga_v=$(printf '%s\n' "$_ga_l" | sed -n 's/.*[ =]\([0-9][0-9]*\(\.[0-9]*\)\{0,1\}\) Hz.*/\1/p' | head -n 1)
    [ -n "$_ga_v" ] && _gh_round_hz "$_ga_v"
}

_gh_sf_call() {
    command -v service >/dev/null 2>&1 || return 1
    _gs_out=$(service call SurfaceFlinger 1035 i32 "$1" 2>&1) || return 1
    case "$_gs_out" in *xception*|*rror*) return 1 ;; esac
    return 0
}

# Indeks SF untuk Hz target: conf GAME_REFRESH_SF_IDX kalau diisi angka, kalau tidak dicari dari daftar mode.
_gh_sf_index_for() {
    _gi=$(_gh_conf GAME_REFRESH_SF_IDX auto)
    if _gh_num "$_gi"; then printf '%s' "$_gi"; return 0; fi
    gh_sf_modes | while read -r _gi_id _gi_hz; do
        [ "$_gi_hz" = "$1" ] && { printf '%s' "$_gi_id"; break; }
    done
}

_gh_refresh_on() {
    gh_feat_ok refresh || return 0
    # opsi HZ khusus game menimpa pengaturan global (off = game ini tidak dipaksa)
    _ghh=$(_gh_opt "$1" HZ)
    [ -n "$_ghh" ] || _ghh=$(_gh_conf GAME_REFRESH_HZ off)
    _gh_num "$_ghh" || return 0
    [ "$_ghh" -ge 30 ] 2>/dev/null && [ "$_ghh" -le 240 ] 2>/dev/null || return 0
    command -v settings >/dev/null 2>&1 || return 0
    if [ ! -f "$GH_REF_PREV" ]; then
        _ghh_mn=$(settings get system min_refresh_rate 2>/dev/null | tr -d '\r\n[:space:]')
        _ghh_pk=$(settings get system peak_refresh_rate 2>/dev/null | tr -d '\r\n[:space:]')
        _ghh_us=$(settings get system user_refresh_rate 2>/dev/null | tr -d '\r\n[:space:]')
        printf '%s %s %s\n' "${_ghh_mn:-null}" "${_ghh_pk:-null}" "${_ghh_us:-null}" > "$GH_REF_PREV" 2>/dev/null
    fi
    # pelapis: settings
    settings put system min_refresh_rate "${_ghh}.0" >/dev/null 2>&1
    settings put system peak_refresh_rate "${_ghh}.0" >/dev/null 2>&1
    # utama: backdoor SurfaceFlinger
    _ghh_idx=$(_gh_sf_index_for "$_ghh")
    if _gh_num "$_ghh_idx" && _gh_sf_call "$_ghh_idx"; then
        : > "$GH_SF_MARK" 2>/dev/null
        # SF butuh waktu pindah mode: tunggu sampai ~1,5 dtk sebelum menyimpulkan indeksnya salah
        _ghh_try=0
        while :; do
            sleep 0.3
            _ghh_act=$(gh_sf_active_hz)
            _gh_num "$_ghh_act" || break
            [ "$_ghh_act" = "$_ghh" ] && break
            _ghh_try=$((_ghh_try + 1))
            [ "$_ghh_try" -ge 5 ] && break
        done
        if _gh_num "$_ghh_act" && [ "$_ghh_act" != "$_ghh" ]; then
            # indeks salah untuk layar ini: batalkan, biarkan pelapis settings yang bekerja
            _gh_sf_call -1
            rm -f "$GH_SF_MARK"
            _gh_log WARN "SF indeks $_ghh_idx menghasilkan ${_ghh_act}Hz, bukan ${_ghh}Hz; dibatalkan, pakai settings saja"
            return 0
        fi
        _gh_log APPLIED "refresh rate dikunci ${_ghh}Hz (SF indeks $_ghh_idx + settings)"
    else
        _gh_log APPLIED "refresh rate dikunci ${_ghh}Hz (settings saja; SF tidak tersedia)"
    fi
}

_gh_refresh_off() {
    [ -f "$GH_REF_PREV" ] || [ -f "$GH_SF_MARK" ] || return 0
    _ghr_mn=null; _ghr_pk=null; _ghr_us=null
    [ -f "$GH_REF_PREV" ] && read -r _ghr_mn _ghr_pk _ghr_us < "$GH_REF_PREV" 2>/dev/null
    : "${_ghr_us:=null}"
    rm -f "$GH_REF_PREV"
    command -v settings >/dev/null 2>&1 || return 0
    if [ -f "$GH_SF_MARK" ]; then
        rm -f "$GH_SF_MARK"
        _gh_sf_call -1
        # tendang ke 60Hz sebentar supaya DisplayManager menghitung ulang (urutan Rairin refresh.sh)
        settings put system peak_refresh_rate "60.0" >/dev/null 2>&1
        settings put system min_refresh_rate "60.0" >/dev/null 2>&1
        sleep 0.2
    fi
    for _ghr_k in min_refresh_rate:"$_ghr_mn" peak_refresh_rate:"$_ghr_pk" user_refresh_rate:"$_ghr_us"; do
        _ghr_key=${_ghr_k%%:*}
        _ghr_val=${_ghr_k#*:}
        case "$_ghr_val" in
            ''|null) settings delete system "$_ghr_key" >/dev/null 2>&1 ;;
            *) settings put system "$_ghr_key" "$_ghr_val" >/dev/null 2>&1 ;;
        esac
    done
    _gh_log RESTORED "refresh rate dikembalikan"
}

# Daftar Hz yang didukung layar, satu per baris, urut naik.
gh_refresh_list() {
    command -v dumpsys >/dev/null 2>&1 || return 0
    _gl=$(gh_sf_modes | while read -r _gl_id _gl_hz; do echo "$_gl_hz"; done | sort -un)
    [ -n "$_gl" ] || _gl=$(dumpsys display 2>/dev/null | grep -o 'fps=[0-9]*' | cut -d= -f2 | sort -un)
    [ -n "$_gl" ] && printf '%s\n' "$_gl"
}

# ---------------------------------------------------------------- 4. render per game
_gh_render_valid() {
    case "$1" in
        skiagl) return 0 ;;
        angle) _gh_angle_supported; return $? ;;
        skiavk)
            _ghv_api=$(getprop ro.build.version.sdk 2>/dev/null)
            _gh_num "$_ghv_api" || return 1
            [ "$_ghv_api" -ge 31 ] || return 1
            [ "$(getprop ro.hwui.use_vulkan 2>/dev/null)" = "true" ] || return 1
            return 0 ;;
        *) return 1 ;;
    esac
}

# stdout: backend khusus game, atau kosong (= ikut global)
gh_render_get() {
    [ -f "$GH_RENDER_MAP" ] || return 0
    sed -n "s/^$(_gh_re "$1")://p" "$GH_RENDER_MAP" 2>/dev/null | tail -n 1 | tr -d '[:space:]'
}

# $1=pkg $2=skiagl|skiavk|default (default = hapus pengaturan khusus)
gh_render_set() {
    case "$1" in ''|*[!A-Za-z0-9._]*) echo "ERROR: package tidak valid"; return 1 ;; esac
    case "$2" in
        default)
            if [ -f "$GH_RENDER_MAP" ]; then
                # grep -v keluar 1 kalau hasilnya kosong, jadi jangan dirantai dengan &&
                grep -v "^$(_gh_re "$1"):" "$GH_RENDER_MAP" > "$GH_RENDER_MAP.tmp.$$" 2>/dev/null
                mv -f "$GH_RENDER_MAP.tmp.$$" "$GH_RENDER_MAP"
            fi
            echo "OK: render $1 -> ikut global"
            return 0 ;;
        skiagl|skiavk|angle)
            gh_feat_ok render || { echo "ERROR: render per game dimatikan oleh mitigasi perangkat"; return 1; }
            _gh_render_valid "$2" || { echo "ERROR: $2 tidak didukung perangkat ini"; return 1; }
            touch "$GH_RENDER_MAP" 2>/dev/null
            grep -v "^$(_gh_re "$1"):" "$GH_RENDER_MAP" > "$GH_RENDER_MAP.tmp.$$" 2>/dev/null
            printf '%s:%s\n' "$1" "$2" >> "$GH_RENDER_MAP.tmp.$$"
            mv -f "$GH_RENDER_MAP.tmp.$$" "$GH_RENDER_MAP" && echo "OK: render $1 -> $2"
            return 0 ;;
        *) echo "ERROR: backend tidak valid (default|skiagl|skiavk|angle)"; return 1 ;;
    esac
}

gh_render_list() {
    [ -f "$GH_RENDER_MAP" ] && cat "$GH_RENDER_MAP"
    return 0
}

_gh_re() { printf '%s' "$1" | sed 's/\./\\./g'; }

_gh_render_restore() {
    [ -f "$GH_REND_PREV" ] || return 0
    _ghx=$(sed -n '1p' "$GH_REND_PREV" 2>/dev/null)
    _ghx=${_ghx%%|*}
    if ! command -v setprop >/dev/null 2>&1; then
        _gh_log WARN "render restore: setprop tidak ditemukan di PATH ($PATH), coba lagi nanti"
        return 0
    fi
    # Nilai awal KOSONG = renderer bawaan sistem; tetap harus ditulis balik (kosong), kalau tidak
    # renderer pilihan game tertinggal untuk semua app sampai reboot.
    setprop debug.hwui.renderer "$_ghx" >/dev/null 2>&1
    if [ -z "$_ghx" ] && [ -n "$(getprop debug.hwui.renderer 2>/dev/null)" ]; then
        command -v resetprop >/dev/null 2>&1 && resetprop -n debug.hwui.renderer "" >/dev/null 2>&1
    fi
    # verifikasi: file penanda baru dihapus bila nilai benar-benar kembali (kalau gagal, dicoba lagi di siklus berikut)
    _ghy=$(getprop debug.hwui.renderer 2>/dev/null)
    if [ "$_ghy" = "$_ghx" ]; then
        rm -f "$GH_REND_PREV"
        _gh_log RESTORED "debug.hwui.renderer dikembalikan ke '${_ghx:-bawaan}'"
    else
        _gh_log WARN "render restore: setelah setprop nilai masih '$_ghy' (target '$_ghx'), diulang di siklus berikut"
    fi
}

# Tombol Luncurkan: pasang backend khusus game, lalu buka game. Backend baru
# hanya terbaca proses yang baru dimulai, jadi game yang sedang jalan tidak disentuh.
gh_launch() {
    case "$1" in ''|*[!A-Za-z0-9._]*) echo "ERROR: package tidak valid"; return 1 ;; esac
    if pidof "$1" >/dev/null 2>&1; then
        echo "ERROR: game sedang jalan, tutup dulu lalu luncurkan lagi dari sini"
        return 1
    fi
    _ghl_be=$(gh_render_get "$1")
    if [ -n "$_ghl_be" ] && gh_feat_ok render && _gh_render_valid "$_ghl_be"; then
        case "$_ghl_be" in
            angle)
                _gh_angle_on "$1" || _ghl_be=""
                ;;
            *)
                if [ ! -f "$GH_REND_PREV" ]; then
                    printf '%s|%s\n' "$(getprop debug.hwui.renderer 2>/dev/null)" "$(_gh_now)" > "$GH_REND_PREV" 2>/dev/null
                fi
                setprop debug.hwui.renderer "$_ghl_be" >/dev/null 2>&1
                _gh_log APPLIED "render $_ghl_be untuk $1 (peluncuran)"
                ;;
        esac
    else
        _ghl_be=""
    fi
    # Game Mode API (mode + downscale) juga hanya efektif penuh bila dipasang sebelum proses game mulai
    _gh_gm_on "$1"
    _gh_preload "$1"
    _ghl_c=$(cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$1" 2>/dev/null | tail -n 1 | tr -d '\r')
    case "$_ghl_c" in
        */*) am start -n "$_ghl_c" >/dev/null 2>&1 ;;
        *) monkey -p "$1" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 ;;
    esac
    echo "OK: launch $1${_ghl_be:+ render=$_ghl_be}"
}

# ---------------------------------------------------------------- 0c. Game Mode API (cmd game)
# Android 12+: `cmd game set --mode <m> [--downscale <r>] <pkg>`; `cmd game reset <pkg>` membuang override.
# Downscale dibaca sistem saat proses game DIMULAI, jadi baru terasa kalau game dibuka lewat tombol Luncurkan.
# PERHATIAN: `reset` membuang SEMUA override game itu, termasuk yang kamu atur sendiri di Game Dashboard.
_gh_gamecmd_ok() {
    command -v cmd >/dev/null 2>&1 || return 1
    cmd -l 2>/dev/null | grep -q '^[[:space:]]*game$'
}

_gh_gm_on() {
    _ghg_pkg="$1"
    _ghg_mode=$(gh_opt_get "$_ghg_pkg" gamemode off)
    _ghg_ds=$(gh_opt_get "$_ghg_pkg" downscale off)
    _ghg_fps=$(gh_opt_get "$_ghg_pkg" fps off)
    [ "$_ghg_mode" = off ] && [ "$_ghg_ds" = off ] && [ "$_ghg_fps" = off ] && return 0
    gh_feat_ok gamemode || return 0
    gh_feat_ok downscale || _ghg_ds=off
    [ "$_ghg_mode" = off ] && [ "$_ghg_ds" = off ] && [ "$_ghg_fps" = off ] && return 0
    if [ -f "$GH_GM_MARK" ] && [ "$(sed -n '1p' "$GH_GM_MARK" 2>/dev/null | cut -d'|' -f1)" = "$_ghg_pkg" ]; then
        return 0
    fi
    _gh_gamecmd_ok || { _gh_log WARN "cmd game tidak tersedia di perangkat ini (Android < 12?)"; return 0; }
    # downscale dan fps butuh mode; default performance
    [ "$_ghg_mode" = off ] && _ghg_mode=performance
    set -- --mode "$_ghg_mode"
    [ "$_ghg_ds" != off ] && set -- "$@" --downscale "$_ghg_ds"
    [ "$_ghg_fps" != off ] && set -- "$@" --fps "$_ghg_fps"
    cmd game set "$@" "$_ghg_pkg" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        printf '%s|%s\n' "$_ghg_pkg" "$(_gh_now)" > "$GH_GM_MARK" 2>/dev/null
        _gh_log APPLIED "game mode $_ghg_mode downscale=$_ghg_ds fps=$_ghg_fps untuk $_ghg_pkg"
    else
        _gh_log WARN "cmd game set gagal untuk $_ghg_pkg"
    fi
}

_gh_gm_off() {
    [ -f "$GH_GM_MARK" ] || return 0
    _ghg_p=$(sed -n '1p' "$GH_GM_MARK" 2>/dev/null)
    rm -f "$GH_GM_MARK"
    _ghg_p=${_ghg_p%%|*}
    [ -n "$_ghg_p" ] || return 0
    _gh_gamecmd_ok && cmd game reset "$_ghg_p" >/dev/null 2>&1
    _gh_log RESTORED "game mode override dibuang untuk $_ghg_p"
}

# ---------------------------------------------------------------- 0d. ANGLE per game
# ANGLE = OpenGL ES di atas Vulkan. Dipilih per package lewat settings global
# angle_gl_driver_selection_pkgs/values; hanya dibaca proses yang baru dimulai (tombol Luncurkan).
_gh_angle_supported() {
    [ "$(getprop ro.gfx.angle.supported 2>/dev/null)" = "true" ] && return 0
    for _gha_f in /system/lib64/libEGL_angle.so /vendor/lib64/egl/libEGL_angle.so /system/lib64/egl/libEGL_angle.so; do
        [ -f "$_gha_f" ] && return 0
    done
    command -v pm >/dev/null 2>&1 && pm path com.android.angle >/dev/null 2>&1 && return 0
    return 1
}

_gh_angle_on() {
    _gha_pkg="$1"
    command -v settings >/dev/null 2>&1 || return 1
    [ -f "$GH_ANGLE_PREV" ] && return 0
    _gha_pp=$(settings get global angle_gl_driver_selection_pkgs 2>/dev/null | tr -d '\r\n')
    _gha_pv=$(settings get global angle_gl_driver_selection_values 2>/dev/null | tr -d '\r\n')
    case "$_gha_pp" in null) _gha_pp="" ;; esac
    case "$_gha_pv" in null) _gha_pv="" ;; esac
    # sudah dipilih pengguna sendiri: jangan diubah, tidak perlu dipulihkan
    case ",$_gha_pp," in *",$_gha_pkg,"*) return 0 ;; esac
    printf '%s|%s|%s\n' "$_gha_pp" "$_gha_pv" "$(_gh_now)" > "$GH_ANGLE_PREV" 2>/dev/null
    settings put global angle_gl_driver_selection_pkgs "${_gha_pp:+$_gha_pp,}$_gha_pkg" >/dev/null 2>&1
    settings put global angle_gl_driver_selection_values "${_gha_pv:+$_gha_pv,}angle" >/dev/null 2>&1
    _gh_log APPLIED "ANGLE untuk $_gha_pkg (peluncuran)"
}

_gh_angle_restore() {
    [ -f "$GH_ANGLE_PREV" ] || return 0
    _gha_l=$(sed -n '1p' "$GH_ANGLE_PREV" 2>/dev/null)
    rm -f "$GH_ANGLE_PREV"
    command -v settings >/dev/null 2>&1 || return 0
    _gha_pp=${_gha_l%%|*}; _gha_r=${_gha_l#*|}; _gha_pv=${_gha_r%%|*}
    if [ -n "$_gha_pp" ]; then
        settings put global angle_gl_driver_selection_pkgs "$_gha_pp" >/dev/null 2>&1
        settings put global angle_gl_driver_selection_values "$_gha_pv" >/dev/null 2>&1
    else
        settings delete global angle_gl_driver_selection_pkgs >/dev/null 2>&1
        settings delete global angle_gl_driver_selection_values >/dev/null 2>&1
    fi
    _gh_log RESTORED "ANGLE dikembalikan"
}

# ---------------------------------------------------------------- 0d2. preload page cache per game
# Membaca berkas game ke page cache lebih dulu (kode terkompilasi, library native, APK) supaya loading awal
# tidak menunggu flash. Page cache bisa dibuang kernel kapan saja, jadi aman bagi RAM; biayanya satu lonjakan I/O.
# Urutan: oat/*.odex|vdex (kode terkompilasi) -> lib/*/*.so -> base.apk -> split APK, sampai batas ukuran.
# Batas = 1/4 dari MemAvailable saat itu (bukan angka tetap); PRELOAD_MAX_MB di app.conf bisa menurunkannya.
# Sekali per PRELOAD_COOLDOWN detik (default 600) per game. Manfaat belum terukur: uji dengan waktu loading sendiri.
_gh_meminfo_kb() { sed -n "s/^$1:[[:space:]]*\([0-9]*\).*/\1/p" "${ALPHA_MEMINFO:-/proc/meminfo}" 2>/dev/null | head -n 1; }

_gh_preload() {
    _gpl_pkg="$1"
    [ "$(gh_opt_get "$_gpl_pkg" preload off)" = on ] || return 0
    gh_feat_ok preload || return 0
    command -v pm >/dev/null 2>&1 || return 0
    _gpl_now=$(_gh_now); _gh_num "$_gpl_now" || return 0
    _gpl_cd=$(_gh_conf PRELOAD_COOLDOWN 600); _gh_num "$_gpl_cd" || _gpl_cd=600
    if [ -f "$GH_PRELOAD_T" ]; then
        _gpl_l=$(sed -n '1p' "$GH_PRELOAD_T" 2>/dev/null)
        if [ "${_gpl_l%%|*}" = "$_gpl_pkg" ]; then
            _gpl_t=${_gpl_l#*|}
            _gh_num "$_gpl_t" && [ $((_gpl_now - _gpl_t)) -lt "$_gpl_cd" ] && return 0
        fi
    fi
    _gpl_kb=$(_gh_meminfo_kb MemAvailable); _gh_num "$_gpl_kb" || return 0
    _gpl_cap=$((_gpl_kb / 4 / 1024))
    # RAM bebas terlalu kecil -> lewati (pengecekan SEBELUM batas pengguna, supaya PRELOAD_MAX_MB kecil tetap dihormati)
    if [ "$_gpl_cap" -lt 16 ]; then _gh_log WARN "preload $_gpl_pkg dilewati: RAM bebas terlalu kecil (${_gpl_cap} MB)"; return 0; fi
    _gpl_max=$(_gh_conf PRELOAD_MAX_MB 0)
    if _gh_num "$_gpl_max" && [ "$_gpl_max" -gt 0 ] && [ "$_gpl_max" -lt "$_gpl_cap" ]; then _gpl_cap=$_gpl_max; fi
    _gpl_paths=$(pm path "$_gpl_pkg" 2>/dev/null | sed -n 's/^package://p' | tr -d '\r')
    [ -n "$_gpl_paths" ] || return 0
    printf '%s|%s\n' "$_gpl_pkg" "$_gpl_now" > "$GH_PRELOAD_T" 2>/dev/null
    (
        _gpl_left=$_gpl_cap; _gpl_n=0
        _gpl_dir=$(dirname "$(printf '%s\n' "$_gpl_paths" | head -n 1)")
        for _gpl_f in "$_gpl_dir"/oat/*/*.odex "$_gpl_dir"/oat/*/*.vdex "$_gpl_dir"/lib/*/*.so $_gpl_paths; do
            [ "$_gpl_left" -gt 0 ] || break
            [ -f "$_gpl_f" ] || continue
            _gpl_sz=$(wc -c < "$_gpl_f" 2>/dev/null | tr -d '[:space:]'); _gh_num "$_gpl_sz" || continue
            _gpl_mb=$(( (_gpl_sz + 1048575) / 1048576 )); [ "$_gpl_mb" -gt 0 ] || _gpl_mb=1
            [ "$_gpl_mb" -le "$_gpl_left" ] || _gpl_mb=$_gpl_left
            if command -v ionice >/dev/null 2>&1; then
                ionice -c2 -n7 dd if="$_gpl_f" of=/dev/null bs=1048576 count="$_gpl_mb" >/dev/null 2>&1
            else
                dd if="$_gpl_f" of=/dev/null bs=1048576 count="$_gpl_mb" >/dev/null 2>&1
            fi
            _gpl_left=$((_gpl_left - _gpl_mb)); _gpl_n=$((_gpl_n + _gpl_mb))
        done
        _gh_log APPLIED "preload $_gpl_pkg: $_gpl_n MB dibaca (batas $_gpl_cap MB)"
    ) >/dev/null 2>&1 &
}

# Grace keluar game (detik) yang bisa diatur: app.conf GAME_GRACE_SEC, 3-120; default = GH_GRACE (12).
_gh_grace() {
    _ggr=$(_gh_conf GAME_GRACE_SEC "$GH_GRACE")
    if _gh_num "$_ggr" && [ "$_ggr" -ge 3 ] && [ "$_ggr" -le 120 ]; then printf '%s' "$_ggr"; else printf '%s' "$GH_GRACE"; fi
}

# ---------------------------------------------------------------- 0e. peta kemampuan
gh_caps() {
    _ghk_sdk=$(getprop ro.build.version.sdk 2>/dev/null)
    printf 'sdk=%s\n' "$_ghk_sdk"
    printf 'settings=%s\n' "$(command -v settings >/dev/null 2>&1 && echo 1 || echo 0)"
    printf 'cmd_game=%s\n' "$(_gh_gamecmd_ok && echo 1 || echo 0)"
    printf 'sf_service=%s\n' "$(command -v service >/dev/null 2>&1 && echo 1 || echo 0)"
    printf 'sf_modes=%s\n' "$(gh_sf_modes | wc -l | tr -d '[:space:]')"
    printf 'refresh_list=%s\n' "$(gh_refresh_list | tr '\n' ',' | sed 's/,$//')"
    printf 'angle=%s\n' "$(_gh_angle_supported && echo 1 || echo 0)"
    printf 'vulkan=%s\n' "$(_gh_render_valid skiavk && echo 1 || echo 0)"
    printf 'screenrecord=%s\n' "$(command -v screenrecord >/dev/null 2>&1 && echo 1 || echo 0)"
    printf 'dnd_cmd=%s\n' "$(command -v cmd >/dev/null 2>&1 && cmd notification help >/dev/null 2>&1 && echo 1 || echo 0)"
    printf 'hosts_mount=%s\n' "$(command -v mount >/dev/null 2>&1 && [ -e /system/etc/hosts ] && echo 1 || echo 0)"
    printf 'mitigated=%s\n' "$(gh_mit_check | sed 's/^off://' | tr '\n' ',' | sed 's/,$//')"
}

# ---------------------------------------------------------------- Overdrive (mesin sendiri, overdrive.sh)
_gh_ovd_sh() {
    for _gc in "${COMMON:-/nonexistent}/overdrive.sh" "${MODDIR:-/nonexistent}/overdrive.sh" \
               "${ALPHA_MOD_DIR:-/nonexistent}/common/overdrive.sh" \
               /data/adb/modules/alpha_uperf_fasrs_fusion/common/overdrive.sh; do
        [ -f "$_gc" ] && { printf '%s' "$_gc"; return 0; }
    done
    return 1
}

_gh_ovd_exists() {
    [ -f "$GH_STATE/.ovd_active" ] || [ -f "$GH_STATE/.ovd_prev" ] || [ -f "$GH_STATE/.ovd_stopped" ]
}

_gh_ovd() {   # $1=start|stop|recover  $2=pkg/alasan
    _gos=$(_gh_ovd_sh) || return 0
    ALPHA_STATE_DIR="$GH_STATE" sh "$_gos" "$1" "$2" >/dev/null 2>&1
}

# ---------------------------------------------------------------- siklus hidup
gh_start() {
    printf '%s\n' "$1" > "$GH_MARK" 2>/dev/null
    rm -f "$GH_PEND"
    _gh_log INFO "game aktif: $1"
    _gh_prio_apply "$1"
    _gh_now > "$GH_PRIO_T" 2>/dev/null
    _gh_dnd_on "$1"
    [ "$(_gh_opt "$1" LITE)" = "1" ] || _gh_refresh_on "$1"
    # Overdrive otomatis untuk game ini (opsi OVD=on); mode ringan menimpa.
    if [ "$(_gh_opt "$1" OVD)" = "on" ] && [ "$(_gh_opt "$1" LITE)" != "1" ]; then
        _gh_ovd start "$1"
    fi
    _gh_gm_on "$1"
    _gh_preload "$1"
    command -v mf_start_clean >/dev/null 2>&1 && mf_start_clean "$1"
}

gh_stop() {
    _ghs=$(cat "$GH_MARK" 2>/dev/null)
    rm -f "$GH_MARK" "$GH_PEND" "$GH_PRIO_T"
    _gh_ovd_exists && _gh_ovd stop "game selesai"
    _gh_dnd_off
    _gh_refresh_off
    _gh_render_restore
    _gh_angle_restore
    _gh_gm_off
    [ -n "$_ghs" ] && _gh_log INFO "game selesai: $_ghs"
    return 0
}

gh_recover() {
    gh_stop
}

# $1 = package di foreground, $2 = profil dari game_profile_map (kosong = bukan game)
gh_foreground() {
    _ghf_pkg="$1"
    if [ -n "$2" ]; then
        rm -f "$GH_PEND"
        _ghf_cur=$(cat "$GH_MARK" 2>/dev/null)
        if [ "$_ghf_cur" != "$_ghf_pkg" ]; then
            [ -n "$_ghf_cur" ] && gh_stop
            gh_start "$_ghf_pkg"
        fi
        return 0
    fi
    [ -f "$GH_MARK" ] || return 0
    [ -f "$GH_PEND" ] || _gh_now > "$GH_PEND" 2>/dev/null
    return 0
}

gh_tick() {
    _ght_now=$(_gh_now)
    _gh_num "$_ght_now" || return 0
    # Penjaga Overdrive mati tapi uperf/fas-rs masih beku atau frekuensi masih terkunci: pulihkan.
    if _gh_ovd_exists; then
        _gop=$(cat "$GH_STATE/.ovd_pid" 2>/dev/null | tr -d '[:space:]')
        if ! _gh_num "$_gop" || [ ! -d "/proc/$_gop" ]; then _gh_ovd recover; fi
    fi
    if [ -f "$GH_MARK" ]; then
        command -v mf_relief_tick >/dev/null 2>&1 && mf_relief_tick "$(cat "$GH_MARK" 2>/dev/null)"
        if [ -f "$GH_PEND" ]; then
            _ght_p=$(tr -d '[:space:]' < "$GH_PEND" 2>/dev/null)
            if _gh_num "$_ght_p" && [ $((_ght_now - _ght_p)) -ge "$(_gh_grace)" ]; then
                gh_stop
                return 0
            fi
        fi
        _ght_l=$(tr -d '[:space:]' < "$GH_PRIO_T" 2>/dev/null)
        _gh_num "$_ght_l" || _ght_l=0
        if [ $((_ght_now - _ght_l)) -ge "$GH_PRIO_EVERY" ]; then
            _gh_prio_apply "$(cat "$GH_MARK" 2>/dev/null)"
            printf '%s\n' "$_ght_now" > "$GH_PRIO_T" 2>/dev/null
        fi
        return 0
    fi
    # Tidak ada game aktif tapi ada sisa state (monitor mati mendadak, peluncuran tanpa masuk game)
    if [ -f "$GH_DND_PREV" ] || [ -f "$GH_REF_PREV" ] || [ -f "$GH_SF_MARK" ]; then
        gh_stop
    fi
    if [ -f "$GH_REND_PREV" ]; then
        _ght_r=$(sed -n '1p' "$GH_REND_PREV" 2>/dev/null)
        _ght_r=${_ght_r#*|}
        if _gh_num "$_ght_r" && [ $((_ght_now - _ght_r)) -ge "$GH_RENDER_TIMEOUT" ]; then
            _gh_render_restore
        fi
    fi
    # Peluncuran yang tidak pernah masuk foreground: ANGLE dan Game Mode override dibuang setelah timeout yang sama
    if [ -f "$GH_ANGLE_PREV" ]; then
        _ght_a=$(sed -n '1p' "$GH_ANGLE_PREV" 2>/dev/null)
        _ght_a=${_ght_a#*|}; _ght_a=${_ght_a#*|}
        if _gh_num "$_ght_a" && [ $((_ght_now - _ght_a)) -ge "$GH_RENDER_TIMEOUT" ]; then
            _gh_angle_restore
        fi
    fi
    if [ -f "$GH_GM_MARK" ]; then
        _ght_g=$(sed -n '1p' "$GH_GM_MARK" 2>/dev/null)
        _ght_g=${_ght_g#*|}
        if _gh_num "$_ght_g" && [ $((_ght_now - _ght_g)) -ge "$GH_RENDER_TIMEOUT" ]; then
            _gh_gm_off
        fi
    fi
    return 0
}
