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
    [ -f "$GH_STATE/GAME_PRIO_OFF" ] && return 0
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
    [ -f "$GH_STATE/GAME_DND_ON" ] || return 0
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
    _ghh=$(_gh_conf GAME_REFRESH_HZ off)
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
    sed -n "s/^$1://p" "$GH_RENDER_MAP" 2>/dev/null | tail -n 1 | tr -d '[:space:]'
}

# $1=pkg $2=skiagl|skiavk|default (default = hapus pengaturan khusus)
gh_render_set() {
    case "$1" in ''|*[!A-Za-z0-9._]*) echo "ERROR: package tidak valid"; return 1 ;; esac
    case "$2" in
        default)
            if [ -f "$GH_RENDER_MAP" ]; then
                # grep -v keluar 1 kalau hasilnya kosong, jadi jangan dirantai dengan &&
                grep -v "^$1:" "$GH_RENDER_MAP" > "$GH_RENDER_MAP.tmp.$$" 2>/dev/null
                mv -f "$GH_RENDER_MAP.tmp.$$" "$GH_RENDER_MAP"
            fi
            echo "OK: render $1 -> ikut global"
            return 0 ;;
        skiagl|skiavk)
            _gh_render_valid "$2" || { echo "ERROR: $2 tidak didukung perangkat ini"; return 1; }
            touch "$GH_RENDER_MAP" 2>/dev/null
            grep -v "^$1:" "$GH_RENDER_MAP" > "$GH_RENDER_MAP.tmp.$$" 2>/dev/null
            printf '%s:%s\n' "$1" "$2" >> "$GH_RENDER_MAP.tmp.$$"
            mv -f "$GH_RENDER_MAP.tmp.$$" "$GH_RENDER_MAP" && echo "OK: render $1 -> $2"
            return 0 ;;
        *) echo "ERROR: backend tidak valid (default|skiagl|skiavk)"; return 1 ;;
    esac
}

gh_render_list() {
    [ -f "$GH_RENDER_MAP" ] && cat "$GH_RENDER_MAP"
    return 0
}

_gh_render_restore() {
    [ -f "$GH_REND_PREV" ] || return 0
    _ghx=$(sed -n '1p' "$GH_REND_PREV" 2>/dev/null)
    rm -f "$GH_REND_PREV"
    _ghx=${_ghx%%|*}
    command -v setprop >/dev/null 2>&1 || return 0
    setprop debug.hwui.renderer "$_ghx" >/dev/null 2>&1
    _gh_log RESTORED "debug.hwui.renderer dikembalikan"
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
    if [ -n "$_ghl_be" ] && _gh_render_valid "$_ghl_be"; then
        if [ ! -f "$GH_REND_PREV" ]; then
            printf '%s|%s\n' "$(getprop debug.hwui.renderer 2>/dev/null)" "$(_gh_now)" > "$GH_REND_PREV" 2>/dev/null
        fi
        setprop debug.hwui.renderer "$_ghl_be" >/dev/null 2>&1
        _gh_log APPLIED "render $_ghl_be untuk $1 (peluncuran)"
    fi
    _ghl_c=$(cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$1" 2>/dev/null | tail -n 1 | tr -d '\r')
    case "$_ghl_c" in
        */*) am start -n "$_ghl_c" >/dev/null 2>&1 ;;
        *) monkey -p "$1" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 ;;
    esac
    echo "OK: launch $1${_ghl_be:+ render=$_ghl_be}"
}

# ---------------------------------------------------------------- siklus hidup
gh_start() {
    printf '%s\n' "$1" > "$GH_MARK" 2>/dev/null
    rm -f "$GH_PEND"
    _gh_log INFO "game aktif: $1"
    _gh_prio_apply "$1"
    _gh_now > "$GH_PRIO_T" 2>/dev/null
    _gh_dnd_on
    _gh_refresh_on
}

gh_stop() {
    _ghs=$(cat "$GH_MARK" 2>/dev/null)
    rm -f "$GH_MARK" "$GH_PEND" "$GH_PRIO_T"
    _gh_dnd_off
    _gh_refresh_off
    _gh_render_restore
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
    if [ -f "$GH_MARK" ]; then
        if [ -f "$GH_PEND" ]; then
            _ght_p=$(tr -d '[:space:]' < "$GH_PEND" 2>/dev/null)
            if _gh_num "$_ght_p" && [ $((_ght_now - _ght_p)) -ge "$GH_GRACE" ]; then
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
    return 0
}
