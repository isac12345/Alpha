#!/system/bin/sh
# Alpha Fusion - alphactl: satu pintu CLI untuk aplikasi Alpha Control.
# Semua tombol di APK memanggil script ini (atau script modul yang sudah ada),
# jadi logika ada di modul dan APK hanya remote.
#
# Pemakaian: alphactl.sh <perintah> [argumen]
#   status                    key=value kondisi live (profil, suhu, baterai, game)
#   profile <battery|balanced|performance>
#   flag get|set|clear <NAMA> flag fitur di STATE_DIR (daftar putih)
#   flags                     status semua flag
#   conf get <KEY> [def] | conf set <KEY> <VAL>     pengaturan app.conf
#   thermal get | thermal set <60-90>               batas warm (derajat C)
#   games                     JSON daftar game (package, profile, fps)
#   game add <pkg> <fps_csv> <profile> | game remove <pkg>
#   sessions [N]              riwayat sesi game
#   health                    status komponen modul
#   device                    isi detected.conf
#   redetect                  deteksi ulang hardware
#   render get | render set <default|skiagl|skiavk>
#   gamerender get <pkg> | set <pkg> <default|skiagl|skiavk> | list    render per game
#   gameopt list <pkg> | set <pkg> <PRIO|DND|LITE> <on|off|1|default>   opsi per game
#   game launch <pkg>         pasang render per game lalu buka game
#   refresh list | get | set <off|Hz> | modes   refresh rate yang dikunci selama game (modes = "indeks_SF Hz")
#   features                  peta kemampuan perangkat (key=value): cmd game, SF, ANGLE, hosts, ...
#   gamefx get <pkg> | set <pkg> <gamemode|downscale|fps|preload|render> <nilai> | list    opsi per game
#   mitigation list | add <pola> <fitur> | remove <pola> <fitur> | check    matikan fitur per perangkat
#   game scan [add [profil] [fps]] | game seed <pkg>   cari game terpasang dari daftar seed, daftarkan sekaligus
#   shield status|lists|import|enable|disable|remove|allow|on|off|apply   pemblokir iklan berbasis hosts
#   bugreport                 arsip log + state ke /sdcard/Download untuk dilaporkan
#   trim [force]              fstrim semua partisi (tidak saat game aktif / baterai < 15%)
#   mem status                tekanan memori (PSI), RAM, kemampuan kernel (hanya baca)
#   mglru status|on|off       MGLRU eksperimental (default off; on = nyalakan, off = pulihkan nilai asli)
#   memclean status|on|off    pembersih adaptif saat game bila PSI tinggi (default off)
#   hud sample <pkg>          satu sampel metrik HUD (FPS, GPU, CPU, suhu)
#   rec start|stop|status|list   rekam layar (screenrecord)
#   autoctl start|stop|status daemon auto-profile
#   log [N]                   N baris terakhir alpha.log
#   modinfo                   module.prop

COMMON="$(dirname "$(readlink -f "$0")")"
MODDIR="$(dirname "$COMMON")"
STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
CONF_FILE="$STATE_DIR/app.conf"
LOG_FILE="${ALPHA_LOG_FILE:-$STATE_DIR/alpha.log}"
SYS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
SYS_POWER="${SYSFS_POWER_PREFIX:-/sys/class/power_supply}"
FASRS_NODE="${ALPHA_FASRS_MODE_NODE:-/dev/fas_rs/mode}"
mkdir -p "$STATE_DIR" 2>/dev/null
ALPHA_STATE_DIR="$STATE_DIR"
[ -f "$COMMON/gamehooks.sh" ] && . "$COMMON/gamehooks.sh"
[ -f "$COMMON/gamescan.sh" ] && . "$COMMON/gamescan.sh"

FLAG_WHITELIST="GB_FASRS_FORCE_ALPHA GB_COOLDOWN_EXTREME NO_CPUSET THERMAL_GUARD_OFF BOOT_GUARD_OFF GAME_PRIO_OFF GAME_DND_ON"

rd() { [ -r "$1" ] && tr -d '\r\n' < "$1" 2>/dev/null; }

uptime_secs() { cut -d. -f1 /proc/uptime 2>/dev/null; }

pid_alive() {
    # $1 = pidfile, $2 = pola cmdline
    _pf="$1"; _pat="$2"
    [ -f "$_pf" ] || return 1
    _p=$(tr -d '[:space:]' < "$_pf" 2>/dev/null)
    [ -n "$_p" ] || return 1
    kill -0 "$_p" 2>/dev/null || return 1
    [ -r "/proc/$_p/cmdline" ] || return 1
    _c=$(tr '\000' ' ' < "/proc/$_p/cmdline" 2>/dev/null)
    case "$_c" in *"$_pat"*) return 0 ;; esac
    return 1
}

# suhu maks zona termal dalam mC. Nilai ngawur (>=125C) dibuang.
max_temp_mc() {
    _max=0
    for _z in "$SYS_THERMAL"/thermal_zone*; do
        [ -r "$_z/temp" ] || continue
        if command -v timeout >/dev/null 2>&1; then
            _v=$(timeout 1 cat "$_z/temp" 2>/dev/null | tr -d '[:space:]')
        else
            _v=$(tr -d '[:space:]' < "$_z/temp" 2>/dev/null)
        fi
        case "$_v" in ''|*[!0-9-]*) continue ;; esac
        [ "${_v#-}" -le 1000 ] 2>/dev/null && _v=$((_v * 1000))
        [ "$_v" -ge 0 ] 2>/dev/null || continue
        [ "$_v" -lt 125000 ] 2>/dev/null || continue
        [ "$_v" -gt "$_max" ] && _max=$_v
    done
    printf '%s' "$_max"
}

# suhu baterai dalam mC (sysfs battery/temp = per 0.1 C). Dipakai untuk tampilan di app.
batt_temp_mc() {
    _bt=$(rd "$SYS_POWER/battery/temp")
    case "$_bt" in ''|*[!0-9-]*) printf '%s' "$(max_temp_mc)"; return ;; esac
    printf '%s' $((_bt * 100))
}

valid_profile() { case "$1" in battery|balanced|performance) return 0 ;; *) return 1 ;; esac; }
valid_pkg() {
    case "$1" in ''|*[!A-Za-z0-9._]*) return 1 ;; esac
    case "$1" in *.*) return 0 ;; *) return 1 ;; esac
}
in_whitelist() { for _w in $FLAG_WHITELIST; do [ "$_w" = "$1" ] && return 0; done; return 1; }

conf_get() {
    _k="$1"; _d="$2"
    _v=""
    [ -f "$CONF_FILE" ] && _v=$(sed -n "s/^${_k}=//p" "$CONF_FILE" 2>/dev/null | tail -n 1)
    [ -n "$_v" ] && printf '%s' "$_v" || printf '%s' "$_d"
}

conf_set() {
    _k="$1"; _v="$2"
    case "$_k" in ''|*[!A-Z0-9_]*) echo "ERROR: key tidak valid"; return 1 ;; esac
    case "$_v" in *[!A-Za-z0-9._,:-]*) echo "ERROR: value tidak valid"; return 1 ;; esac
    touch "$CONF_FILE" 2>/dev/null
    _t="$CONF_FILE.tmp.$$"
    grep -v "^${_k}=" "$CONF_FILE" > "$_t" 2>/dev/null
    printf '%s=%s\n' "$_k" "$_v" >> "$_t"
    mv -f "$_t" "$CONF_FILE" && echo "OK: $_k=$_v"
}

# memfx: tekanan memori (PSI) dan MGLRU opt-in. Default tidak menyentuh apa pun.
ALPHA_STATE_DIR="$STATE_DIR"
[ -f "$COMMON/memfx.sh" ] && . "$COMMON/memfx.sh"

cmd_mem() {
    command -v mf_memstat >/dev/null 2>&1 || { echo "ERROR: memfx.sh tidak ada"; return 1; }
    case "$1" in
        ''|status) mf_memstat; mf_caps ;;
        *) echo "Usage: mem status"; return 1 ;;
    esac
}

cmd_mglru() {
    command -v mf_mglru_status >/dev/null 2>&1 || { echo "ERROR: memfx.sh tidak ada"; return 1; }
    case "$1" in
        ''|status) mf_mglru_status; printf 'mode=%s\n' "$(conf_get MGLRU_MODE off)" ;;
        on)  conf_set MGLRU_MODE on  >/dev/null && mf_mglru_apply; mf_mglru_status ;;
        off) conf_set MGLRU_MODE off >/dev/null && mf_mglru_restore; mf_mglru_status ;;
        *) echo "Usage: mglru status|on|off"; return 1 ;;
    esac
}

cmd_memclean() {
    case "$1" in
        ''|status) printf 'memclean=%s\nhits=%s\ncooldown=%s\n' "$(conf_get MEMCLEAN 0)" "$(conf_get MEMCLEAN_HITS 3)" "$(conf_get MEMCLEAN_COOLDOWN 180)" ;;
        on)  conf_set MEMCLEAN 1 ;;
        off) conf_set MEMCLEAN 0 ;;
        *) echo "Usage: memclean status|on|off"; return 1 ;;
    esac
}

cmd_status() {
    _cur=$(rd "$STATE_DIR/current_state"); [ -n "$_cur" ] || _cur=none
    _act=$(rd "$STATE_DIR/active_profile"); [ -n "$_act" ] || _act=none
    printf 'profile=%s\nactive=%s\n' "$_cur" "$_act"
    pid_alive "$STATE_DIR/monitor.pid" monitor.sh && echo monitor=1 || echo monitor=0
    pid_alive "$STATE_DIR/watchdog.pid" watchdog.sh && echo watchdog=1 || echo watchdog=0
    pid_alive "$STATE_DIR/autoctl.pid" autoctl.sh && echo auto=1 || echo auto=0
    if [ -r "$FASRS_NODE" ]; then
        echo fasrs_node=1
        printf 'fasrs_mode=%s\n' "$(rd "$FASRS_NODE")"
        echo cpu_owner=fas-rs
    else
        echo fasrs_node=0
        echo fasrs_mode=
        if pidof fas-rs >/dev/null 2>&1; then echo cpu_owner=fas-rs; else echo cpu_owner=alpha; fi
    fi
    printf 'temp_mc=%s\n' "$(batt_temp_mc)"
    printf 'soc_temp_mc=%s\n' "$(max_temp_mc)"
    printf 'batt=%s\n' "$(rd "$SYS_POWER/battery/capacity")"
    printf 'batt_status=%s\n' "$(rd "$SYS_POWER/battery/status")"
    printf 'gb_active=%s\n' "$(rd "$STATE_DIR/.gb_active")"
    printf 'boost_level=%s\n' "$(rd "$STATE_DIR/boost_level")"
    _gp=""; _gs=0
    if [ -f "$STATE_DIR/.game_t0" ]; then
        read -r _t0 _gp < "$STATE_DIR/.game_t0" 2>/dev/null
        _now=$(uptime_secs)
        case "$_t0" in ''|*[!0-9]*) ;; *) [ -n "$_now" ] && _gs=$((_now - _t0)) ;; esac
        [ "$_gs" -ge 0 ] 2>/dev/null || _gs=0
    fi
    printf 'game_pkg=%s\ngame_secs=%s\n' "$_gp" "$_gs"
    printf 'hud_pkg=%s\n' "$(rd "$STATE_DIR/.gh_active")"
    pid_alive "$STATE_DIR/.rec_pid" screenrec.sh && echo rec=1 || echo rec=0
    printf 'thermal_warm_c=%s\n' "$(cmd_thermal_get)"
    if [ -f "$COMMON/overdrive.sh" ]; then
        ALPHA_STATE_DIR="$STATE_DIR" sh "$COMMON/overdrive.sh" status 2>/dev/null
    else
        printf 'ovd=0\novd_pkg=\novd_level=\novd_last=\n'
    fi
    if command -v mf_psi_x100 >/dev/null 2>&1; then
        printf 'psi_some10_x100=%s\n' "$(mf_psi_x100 some avg10 2>/dev/null)"
        printf 'mglru=%s\n' "$([ -r "$MF_LRU/enabled" ] && { _mf_raw_on "$(tr -d '[:space:]' < "$MF_LRU/enabled")" && echo 1 || echo 0; } || echo na)"
        printf 'mglru_mode=%s\nmemclean=%s\n' "$(conf_get MGLRU_MODE off)" "$(conf_get MEMCLEAN 0)"
    fi
    printf 'ver=%s\n' "$(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)"
}

cmd_profile() {
    valid_profile "$1" || { echo "ERROR: profil tidak valid (battery|balanced|performance)"; return 1; }
    sh "$COMMON/apply_now.sh" "$1" manual >/dev/null 2>&1
    _rc=$?
    # apply_now bisa SKIPPED (sudah current) -> tetap exit 0
    [ "$_rc" -eq 0 ] && echo "OK: profile=$1" || echo "ERROR: apply_now rc=$_rc"
    return "$_rc"
}

cmd_flag() {
    _op="$1"; _n="$2"
    in_whitelist "$_n" || { echo "ERROR: flag tidak dikenal: $_n"; return 1; }
    case "$_op" in
        get) [ -f "$STATE_DIR/$_n" ] && echo 1 || echo 0 ;;
        set) : > "$STATE_DIR/$_n" 2>/dev/null && echo "OK: $_n=1" || { echo "ERROR: gagal tulis"; return 1; } ;;
        clear) rm -f "$STATE_DIR/$_n" 2>/dev/null; echo "OK: $_n=0" ;;
        *) echo "Usage: flag get|set|clear <NAMA>"; return 1 ;;
    esac
}

cmd_flags() {
    for _n in $FLAG_WHITELIST; do
        [ -f "$STATE_DIR/$_n" ] && echo "$_n=1" || echo "$_n=0"
    done
}

cmd_thermal_get() {
    _t=$(tr -cd '0-9' 2>/dev/null < "$STATE_DIR/THERMAL_WARM_C")
    case "$_t" in ''|*[!0-9]*) _t=75 ;; esac
    [ "$_t" -ge 60 ] 2>/dev/null && [ "$_t" -le 90 ] 2>/dev/null || _t=75
    printf '%s' "$_t"
}

cmd_thermal() {
    case "$1" in
        get) cmd_thermal_get; echo ;;
        set)
            case "$2" in ''|*[!0-9]*) echo "ERROR: angka derajat"; return 1 ;; esac
            if [ "$2" -lt 60 ] || [ "$2" -gt 90 ]; then echo "ERROR: rentang 60-90"; return 1; fi
            printf '%s\n' "$2" > "$STATE_DIR/THERMAL_WARM_C" && echo "OK: warm=$2"
            ;;
        *) echo "Usage: thermal get|set <60-90>"; return 1 ;;
    esac
}

fps_of() {
    # nilai fps game dari games.toml, dinormalkan "30,60"
    _f="$MODDIR/fasrs/games.toml"
    [ -f "$_f" ] || return 0
    sed -n "s/^\"$1\"[[:space:]]*=[[:space:]]*//p" "$_f" 2>/dev/null | head -n 1 | tr -d '[] "' 
}

cmd_games() {
    _map="$STATE_DIR/game_profile_map.conf"
    _toml="$MODDIR/fasrs/games.toml"
    _seen=" "
    _first=1
    printf '['
    if [ -f "$_map" ]; then
        while IFS= read -r _l || [ -n "$_l" ]; do
            _l=$(printf '%s' "$_l" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            case "$_l" in ''|'#'*) continue ;; esac
            _pkg=${_l%%:*}; _pr=${_l#*:}
            valid_pkg "$_pkg" || continue
            valid_profile "$_pr" || continue
            [ "$_first" = 1 ] || printf ','
            _first=0
            _seen="$_seen$_pkg "
            printf '{"package":"%s","profile":"%s","fps":"%s"}' "$_pkg" "$_pr" "$(fps_of "$_pkg")"
        done < "$_map"
    fi
    if [ -f "$_toml" ]; then
        _pk=$(sed -n '/^\[game_list\]/,/^\[/p' "$_toml" | sed -n 's/^"\([^"]*\)".*/\1/p')
        for _pkg in $_pk; do
            valid_pkg "$_pkg" || continue
            case "$_seen" in *" $_pkg "*) continue ;; esac
            [ "$_first" = 1 ] || printf ','
            _first=0
            printf '{"package":"%s","profile":"balanced","fps":"%s"}' "$_pkg" "$(fps_of "$_pkg")"
        done
    fi
    printf ']\n'
}

cmd_game() {
    case "$1" in
        add)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            _fps="${3:-30,60}"; _pr="${4:-balanced}"
            sh "$COMMON/game_add.sh" add "$2" "$_fps" "$_pr"
            ;;
        remove)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            sh "$COMMON/game_add.sh" remove "$2"
            ;;
        launch)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            gh_launch "$2"
            ;;
        scan)
            command -v gs_candidates >/dev/null 2>&1 || { echo "ERROR: gamescan.sh tidak ada"; return 1; }
            case "$2" in
                add) gs_add_all "$3" "$4" ;;
                *) gs_candidates ;;
            esac
            ;;
        seed) gs_user_add "$2" ;;
        *) echo "Usage: game add <pkg> <fps_csv> <profile> | game remove <pkg> | game launch <pkg> | game scan [add [profil] [fps]] | game seed <pkg>"; return 1 ;;
    esac
}

cmd_gamerender() {
    case "$1" in
        get)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            _gr=$(gh_render_get "$2"); printf '%s\n' "${_gr:-default}"
            ;;
        set)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            gh_render_set "$2" "$3"
            ;;
        list) gh_render_list ;;
        *) echo "Usage: gamerender get <pkg> | set <pkg> <default|skiagl|skiavk|angle> | list"; return 1 ;;
    esac
}

cmd_gamefx() {
    case "$1" in
        get)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            printf 'gamemode=%s\n' "$(gh_opt_get "$2" gamemode off)"
            printf 'downscale=%s\n' "$(gh_opt_get "$2" downscale off)"
            printf 'fps=%s\n' "$(gh_opt_get "$2" fps off)"
            printf 'preload=%s\n' "$(gh_opt_get "$2" preload off)"
            _gx=$(gh_render_get "$2"); printf 'render=%s\n' "${_gx:-default}"
            ;;
        set)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            case "$3" in
                gamemode|downscale|fps|preload) gh_opt_set "$2" "$3" "$4" ;;
                render) gh_render_set "$2" "$4" ;;
                *) echo "ERROR: kunci = gamemode|downscale|fps|preload|render"; return 1 ;;
            esac
            ;;
        list) gh_opt_list; gh_render_list | sed 's/^\([^:]*\):/\1:render=/' ;;
        *) echo "Usage: gamefx get <pkg> | set <pkg> <gamemode|downscale|fps|preload|render> <nilai> | list"; return 1 ;;
    esac
}

cmd_mitigation() {
    case "$1" in
        list) gh_mit_list ;;
        add) gh_mit_add "$2" "$3" ;;
        remove) gh_mit_remove "$2" "$3" ;;
        check) gh_mit_check ;;
        *) echo "Usage: mitigation list | add <pola> <fitur> | remove <pola> <fitur> | check"; return 1 ;;
    esac
}

# Ekspor satu berkas teks berisi semua yang dibutuhkan untuk diagnosa. Tidak berisi data pribadi (tanpa isi app/chat).
cmd_logexport() {
    _ld="/sdcard/Download"
    [ -d "$_ld" ] && [ -w "$_ld" ] || _ld="$STATE_DIR"
    _lf="$_ld/alpha-log-$(date '+%Y%m%d-%H%M%S' 2>/dev/null).txt"
    {
        echo "=== Alpha log export $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) ==="
        echo "module versionCode: $(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)"
        echo "model: $(getprop ro.product.model 2>/dev/null)  android: $(getprop ro.build.version.release 2>/dev/null)  platform: $(getprop ro.board.platform 2>/dev/null)"
        echo "kernel: $(uname -r 2>/dev/null)"
        echo; echo "=== status ==="; cmd_status 2>/dev/null
        echo; echo "=== health ==="; cmd_health 2>/dev/null
        echo; echo "=== flags ==="; cmd_flags 2>/dev/null
        echo; echo "=== app.conf ==="; [ -f "$CONF_FILE" ] && cat "$CONF_FILE"
        echo; echo "=== opsi per game (game_opts.conf) ==="; [ -f "$STATE_DIR/game_opts.conf" ] && cat "$STATE_DIR/game_opts.conf"
        echo; echo "=== overdrive ==="; [ -f "$COMMON/overdrive.sh" ] && ALPHA_STATE_DIR="$STATE_DIR" sh "$COMMON/overdrive.sh" status
        echo; echo "=== frekuensi saat ini ==="
        for _p in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -d "$_p" ] && echo "$(basename "$_p") gov=$(cat "$_p/scaling_governor" 2>/dev/null) min=$(cat "$_p/scaling_min_freq" 2>/dev/null) max=$(cat "$_p/scaling_max_freq" 2>/dev/null) cur=$(cat "$_p/scaling_cur_freq" 2>/dev/null)"
        done
        for _g in /sys/class/devfreq/*gpu*; do
            [ -d "$_g" ] && echo "gpu $(basename "$_g") min=$(cat "$_g/min_freq" 2>/dev/null) max=$(cat "$_g/max_freq" 2>/dev/null) cur=$(cat "$_g/cur_freq" 2>/dev/null)"
        done
        echo; echo "=== alpha.log (400 baris terakhir) ==="; tail -n 400 "$STATE_DIR/alpha.log" 2>/dev/null
        echo; echo "=== hud_debug.log ==="; tail -n 120 "$STATE_DIR/hud_debug.log" 2>/dev/null
    } > "$_lf" 2>&1
    echo "OK: $_lf"
}

cmd_ovd() {
    [ -f "$COMMON/overdrive.sh" ] || { echo "ERROR: overdrive.sh tidak ada"; return 1; }
    case "$1" in
        start) [ -z "$2" ] || valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
               ALPHA_STATE_DIR="$STATE_DIR" sh "$COMMON/overdrive.sh" start "$2" ;;
        stop) ALPHA_STATE_DIR="$STATE_DIR" sh "$COMMON/overdrive.sh" stop "${2:-manual}" ;;
        status) ALPHA_STATE_DIR="$STATE_DIR" sh "$COMMON/overdrive.sh" status ;;
        *) echo "Usage: ovd start [pkg] | ovd stop | ovd status"; return 1 ;;
    esac
}

cmd_gameopt() {
    case "$1" in
        list)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            gh_opt_list "$2"
            ;;
        set)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            gh_opt_set "$2" "$3" "$4"
            ;;
        *) echo "Usage: gameopt list <pkg> | set <pkg> <PRIO|DND|LITE> <on|off|1|default>"; return 1 ;;
    esac
}

cmd_refresh() {
    case "$1" in
        list) gh_refresh_list ;;
        modes) gh_sf_modes ;;
        get) conf_get GAME_REFRESH_HZ off; echo ;;
        set)
            case "$2" in
                off) ;;
                ''|*[!0-9]*) echo "ERROR: isi off atau angka Hz"; return 1 ;;
                *)
                    if [ "$2" -lt 30 ] || [ "$2" -gt 240 ]; then echo "ERROR: rentang 30-240 Hz"; return 1; fi
                    _rl=$(gh_refresh_list)
                    if [ -n "$_rl" ]; then
                        case " $(echo $_rl) " in *" $2 "*) ;; *) echo "ERROR: layar ini tidak mendukung $2 Hz"; return 1 ;; esac
                    fi
                    ;;
            esac
            conf_set GAME_REFRESH_HZ "$2" || return 1
            # game sedang jalan: terapkan langsung
            if [ -f "$STATE_DIR/.gh_active" ]; then _gh_refresh_off; _gh_refresh_on "$(cat "$STATE_DIR/.gh_active" 2>/dev/null)"; fi
            ;;
        *) echo "Usage: refresh list | get | set <off|Hz>"; return 1 ;;
    esac
}

cmd_hud() {
    case "$1" in
        sample)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            sh "$COMMON/hud_sample.sh" --once "$2"
            ;;
        *) echo "Usage: hud sample <pkg>"; return 1 ;;
    esac
}

cmd_sessions() {
    _n="${1:-20}"
    case "$_n" in ''|*[!0-9]*) _n=20 ;; esac
    [ -f "$STATE_DIR/sessions.log" ] && tail -n "$_n" "$STATE_DIR/sessions.log"
    return 0
}

cmd_health() {
    pidof uperf >/dev/null 2>&1 && echo uperf=1 || echo uperf=0
    pidof fas-rs >/dev/null 2>&1 && echo fasrs=1 || echo fasrs=0
    pid_alive "$STATE_DIR/monitor.pid" monitor.sh && echo monitor=1 || echo monitor=0
    pid_alive "$STATE_DIR/watchdog.pid" watchdog.sh && echo watchdog=1 || echo watchdog=0
    pid_alive "$STATE_DIR/autoctl.pid" autoctl.sh && echo auto=1 || echo auto=0
    [ -f "$STATE_DIR/BOOT_GUARD_OFF" ] && echo bootguard=0 || echo bootguard=1
    _bf=$(tr -cd '0-9' 2>/dev/null < "$STATE_DIR/.boot_fail_count"); echo "boot_fail=${_bf:-0}"
    [ -f "$STATE_DIR/.disable_tweaks" ] && echo disable_tweaks=1 || echo disable_tweaks=0
    printf 'ver=%s\n' "$(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)"
}

cmd_device() { [ -f "$STATE_DIR/detected.conf" ] && cat "$STATE_DIR/detected.conf"; return 0; }

cmd_redetect() {
    rm -f "$STATE_DIR/detected.conf" 2>/dev/null
    ALPHA_FORCE_DETECT=1 sh "$COMMON/detect.sh" >/dev/null 2>&1
    cmd_device
}

cmd_autoctl() {
    case "$1" in
        start)
            if pid_alive "$STATE_DIR/autoctl.pid" autoctl.sh; then echo "OK: sudah jalan"; return 0; fi
            rm -f "$STATE_DIR/autoctl.pid" 2>/dev/null
            ALPHA_STATE_DIR="$STATE_DIR" nohup sh "$COMMON/autoctl.sh" >> "$LOG_FILE" 2>&1 &
            echo "OK: autoctl start pid=$!"
            ;;
        stop)
            if pid_alive "$STATE_DIR/autoctl.pid" autoctl.sh; then
                kill "$(tr -d '[:space:]' < "$STATE_DIR/autoctl.pid")" 2>/dev/null
            fi
            rm -f "$STATE_DIR/autoctl.pid" 2>/dev/null
            echo "OK: autoctl stop"
            ;;
        status) pid_alive "$STATE_DIR/autoctl.pid" autoctl.sh && echo 1 || echo 0 ;;
        *) echo "Usage: autoctl start|stop|status"; return 1 ;;
    esac
}

cmd_log() {
    _n="${1:-300}"
    case "$_n" in ''|*[!0-9]*) _n=300 ;; esac
    [ "$_n" -le 3000 ] || _n=3000
    [ -f "$LOG_FILE" ] && tail -n "$_n" "$LOG_FILE"
    return 0
}

case "$1" in
    status) cmd_status ;;
    profile) cmd_profile "$2" ;;
    flag) cmd_flag "$2" "$3" ;;
    flags) cmd_flags ;;
    conf)
        case "$2" in
            get) conf_get "$3" "$4"; echo ;;
            set) conf_set "$3" "$4" ;;
            all) [ -f "$CONF_FILE" ] && cat "$CONF_FILE" ;;
            *) echo "Usage: conf get <KEY> [def] | conf set <KEY> <VAL> | conf all"; exit 1 ;;
        esac
        ;;
    thermal) cmd_thermal "$2" "$3" ;;
    games) cmd_games ;;
    game) cmd_game "$2" "$3" "$4" "$5" ;;
    sessions) cmd_sessions "$2" ;;
    health) cmd_health ;;
    device) cmd_device ;;
    redetect) cmd_redetect ;;
    render) sh "$COMMON/render_manager.sh" "$2" "$3" ;;
    gamerender) cmd_gamerender "$2" "$3" "$4" ;;
    gameopt) cmd_gameopt "$2" "$3" "$4" "$5" ;;
    ovd) cmd_ovd "$2" "$3" ;;
    logexport) cmd_logexport ;;
    mem) cmd_mem "$2" ;;
    mglru) cmd_mglru "$2" ;;
    memclean) cmd_memclean "$2" ;;
    refresh) cmd_refresh "$2" "$3" ;;
    hud) cmd_hud "$2" "$3" ;;
    rec) sh "$COMMON/screenrec.sh" "$2" "$3" ;;
    autoctl) cmd_autoctl "$2" ;;
    renderrestore) _gh_render_restore; [ -f "$GH_REND_PREV" ] && echo "pending: $(cat "$GH_REND_PREV")" || echo "OK: tidak ada penanda; renderer=$(getprop debug.hwui.renderer)" ;;
    features) gh_caps; mf_caps ;;
    trim) sh "$COMMON/trim.sh" "$2" ;;
    gamefx) cmd_gamefx "$2" "$3" "$4" "$5" ;;
    mitigation) cmd_mitigation "$2" "$3" "$4" ;;
    shield) shift; sh "$COMMON/shield.sh" "$@" ;;
    bugreport) sh "$COMMON/bugreport.sh" ;;
    log) cmd_log "$2" ;;
    modinfo) cat "$MODDIR/module.prop" ;;
    *) sed -n '2,42p' "$0" ;;
esac
