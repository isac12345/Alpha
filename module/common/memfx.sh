#!/system/bin/sh
# memfx.sh — tweak memori Alpha: PSI memori (baca), MGLRU opt-in (eksperimental), pembersih adaptif opt-in.
# Library fungsi (di-source), gaya sama dengan gamehooks.sh. Semua jalur bisa di-override lewat env
# supaya bisa diuji di Linux biasa tanpa HP (lihat test_memfx.sh).
#
#   mf_caps                     key=value kemampuan: psi, mglru, freezer, lmkd
#   mf_memstat                  key=value live: psi_some10_x100, psi_full10_x100, mem_avail_mb, swap_used_mb, ...
#   mf_psi_threshold_x100       ambang PSI (persen x100) diturunkan dari properti lmkd perangkat, bukan angka tetap
#   mf_mglru_status             key=value: supported, enabled_raw, enabled, min_ttl_ms
#   mf_mglru_apply              terapkan MGLRU_MODE dari app.conf (off = tidak menyentuh apa pun)
#   mf_mglru_restore            kembalikan nilai asli yang disimpan sebelum diubah
#   mf_relief_tick <pkg>        dipanggil tiap siklus monitor SAAT game aktif; pembersih adaptif (opt-in)

MF_STATE="${ALPHA_STATE_DIR:-/data/adb/alpha}"
MF_CONF="$MF_STATE/app.conf"
MF_LOG="${ALPHA_LOG_FILE:-$MF_STATE/alpha.log}"
MF_PSI="${ALPHA_PSI_FILE:-/proc/pressure/memory}"
MF_LRU="${ALPHA_LRUGEN_DIR:-/sys/kernel/mm/lru_gen}"
MF_MEMINFO="${ALPHA_MEMINFO:-/proc/meminfo}"
MF_LRU_PREV="$MF_STATE/.mf_mglru_prev"
MF_HITS="$MF_STATE/.mf_hits"
MF_LAST="$MF_STATE/.mf_last"

# pintu mitigasi dari gamehooks.sh bila ada (fitur: mglru, memclean); tanpa gamehooks tidak memblok
_mf_ok() { command -v gh_feat_ok >/dev/null 2>&1 || return 0; gh_feat_ok "$1"; }

_mf_log() { printf '[%s] [MEMFX] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$1" "$2" >> "$MF_LOG" 2>/dev/null; }
_mf_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
_mf_conf() {
    _mfc=""
    [ -f "$MF_CONF" ] && _mfc=$(sed -n "s/^$1=//p" "$MF_CONF" 2>/dev/null | tail -n 1)
    [ -n "$_mfc" ] && printf '%s' "$_mfc" || printf '%s' "$2"
}
# titik tunggal tulis sysfs; test meng-override fungsi ini untuk meniru kernel
_mf_write() { printf '%s' "$2" > "$1" 2>/dev/null; }

# "12.34" -> 1234, "0.5" -> 50, "100.00" -> 10000. Tanpa awk/bc; aman dari jebakan oktal ("08").
_mf_x100() {
    _mx_i=${1%%.*}
    _mx_f=${1#*.}
    [ "$_mx_f" = "$1" ] && _mx_f=00
    _mx_f=$(printf '%.2s' "${_mx_f}00")
    _mx_f=${_mx_f#0}
    _mf_num "$_mx_i" || return 1
    _mf_num "${_mx_f:-0}" || return 1
    printf '%s' $(( _mx_i * 100 + ${_mx_f:-0} ))
}

# mf_psi_x100 some|full avg10|avg60|avg300
mf_psi_x100() {
    [ -r "$MF_PSI" ] || return 1
    _mp=$(sed -n "s/^$1 //p" "$MF_PSI" 2>/dev/null | head -n 1)
    [ -n "$_mp" ] || return 1
    for _mp_t in $_mp; do
        case "$_mp_t" in "$2="*) _mf_x100 "${_mp_t#*=}"; return $? ;; esac
    done
    return 1
}

_mf_meminfo_kb() { sed -n "s/^$1:[[:space:]]*\([0-9]*\).*/\1/p" "$MF_MEMINFO" 2>/dev/null | head -n 1; }

# Ambang = ambang stall parsial lmkd perangkat ini. lmkd memicu bila stall parsial >= N ms dalam jendela 1000 ms,
# jadi N ms = N/10 persen. Default sistem 70 ms (normal) / 200 ms (RAM kecil); dibaca dari properti, bukan ditanam.
mf_psi_threshold_x100() {
    _mt=$(getprop ro.lmk.psi_partial_stall_ms 2>/dev/null)
    if ! _mf_num "$_mt"; then
        if [ "$(getprop ro.config.low_ram 2>/dev/null)" = "true" ]; then _mt=200; else _mt=70; fi
    fi
    printf '%s' $(( _mt * 10 ))
}

mf_memstat() {
    if [ -r "$MF_PSI" ]; then
        printf 'psi=1\npsi_some10_x100=%s\npsi_full10_x100=%s\n' "$(mf_psi_x100 some avg10)" "$(mf_psi_x100 full avg10)"
    else
        printf 'psi=0\n'
    fi
    _ma=$(_mf_meminfo_kb MemAvailable); _mtot=$(_mf_meminfo_kb MemTotal)
    _sf=$(_mf_meminfo_kb SwapFree); _st=$(_mf_meminfo_kb SwapTotal)
    _mf_num "$_ma" && printf 'mem_avail_mb=%s\n' $(( _ma / 1024 ))
    _mf_num "$_mtot" && printf 'mem_total_mb=%s\n' $(( _mtot / 1024 ))
    if _mf_num "$_st" && _mf_num "$_sf"; then printf 'swap_used_mb=%s\n' $(( (_st - _sf) / 1024 )); fi
    printf 'psi_threshold_x100=%s\n' "$(mf_psi_threshold_x100)"
}

# ------------------------------------------------------------------ MGLRU
# /sys/kernel/mm/lru_gen/enabled: dibaca sebagai hex (mis. 0x0007); bit 0x1 = saklar utama.
# Ditulis: y (semua komponen), n (mati), atau mask. min_ttl_ms SENGAJA TIDAK disentuh (lihat SPEC bagian risiko).
_mf_raw_on() { # $1 = nilai mentah dari kernel ("0x0007", "y", "7"); sukses bila bit 0x1 menyala
    case "$1" in
        y|Y) return 0 ;;
        n|N|'') return 1 ;;
    esac
    [ $(( $1 & 1 )) -ne 0 ] 2>/dev/null
}

mf_mglru_status() {
    if [ -r "$MF_LRU/enabled" ]; then
        _mr=$(tr -d '[:space:]' < "$MF_LRU/enabled" 2>/dev/null)
        printf 'supported=1\nenabled_raw=%s\nenabled=%s\n' "$_mr" "$(_mf_raw_on "$_mr" && echo 1 || echo 0)"
        [ -r "$MF_LRU/min_ttl_ms" ] && printf 'min_ttl_ms=%s\n' "$(tr -d '[:space:]' < "$MF_LRU/min_ttl_ms" 2>/dev/null)"
    else
        printf 'supported=0\n'
    fi
}

mf_mglru_apply() {
    _mm=$(_mf_conf MGLRU_MODE off)
    if [ "$_mm" != on ]; then mf_mglru_restore; return 0; fi
    _mf_ok mglru || return 0
    [ -w "$MF_LRU/enabled" ] || { _mf_log WARN "MGLRU diminta tapi kernel tidak mendukung"; return 0; }
    _mr=$(tr -d '[:space:]' < "$MF_LRU/enabled" 2>/dev/null)
    _mf_raw_on "$_mr" && return 0   # sudah menyala (bawaan ROM atau sudah kita nyalakan): tidak ada yang diubah, tidak ada yang dipulihkan
    [ -f "$MF_LRU_PREV" ] || printf '%s\n' "$_mr" > "$MF_LRU_PREV"
    _mf_write "$MF_LRU/enabled" y
    _mr2=$(tr -d '[:space:]' < "$MF_LRU/enabled" 2>/dev/null)
    if _mf_raw_on "$_mr2"; then
        _mf_log APPLIED "MGLRU menyala ($_mr -> $_mr2)"
    else
        _mf_log WARN "MGLRU gagal menyala (baca ulang: $_mr2)"
        rm -f "$MF_LRU_PREV"
    fi
}

mf_mglru_restore() {
    [ -f "$MF_LRU_PREV" ] || return 0
    _mp=$(sed -n '1p' "$MF_LRU_PREV")
    rm -f "$MF_LRU_PREV"
    [ -n "$_mp" ] || return 0
    [ -w "$MF_LRU/enabled" ] || return 0
    # Kernel doc memperlihatkan input berupa "y" atau angka desimal (mis. `echo 5`). Nilai asli dibaca sebagai
    # "0x0007"/"0x0000", jadi ubah ke desimal lewat aritmetika shell sebelum ditulis balik.
    case "$_mp" in y|Y) _mp=y ;; n|N) _mp=0 ;; *) _mp=$(( _mp )) 2>/dev/null || _mp=0 ;; esac
    _mf_write "$MF_LRU/enabled" "$_mp"
    _mf_log RESTORED "MGLRU dikembalikan ke $_mp"
}

# ------------------------------------------------------------------ PSI + pembersih adaptif (opt-in)
# Hanya bertindak bila: MEMCLEAN=1, game aktif (dipanggil hanya saat game), PSI some avg10 >= ambang
# selama MEMCLEAN_HITS sampel berturut-turut, dan sudah lewat MEMCLEAN_COOLDOWN detik dari tindakan terakhir.
# Tindakan: `am kill-all` (hanya proses yang aman dimatikan: cached/background, bukan app foreground).
mf_relief_tick() {
    [ "$(_mf_conf MEMCLEAN 0)" = 1 ] || return 0
    _mf_ok memclean || return 0
    _mv=$(mf_psi_x100 some avg10) || return 0
    _mth=$(mf_psi_threshold_x100)
    _mhn=$(_mf_conf MEMCLEAN_HITS 3); _mf_num "$_mhn" || _mhn=3
    _mcd=$(_mf_conf MEMCLEAN_COOLDOWN 180); _mf_num "$_mcd" || _mcd=180
    if [ "$_mv" -ge "$_mth" ]; then
        _mh=$(cat "$MF_HITS" 2>/dev/null); _mf_num "$_mh" || _mh=0
        _mh=$((_mh + 1)); printf '%s\n' "$_mh" > "$MF_HITS"
    else
        rm -f "$MF_HITS"; return 0
    fi
    [ "$_mh" -ge "$_mhn" ] || return 0
    _mn=$(date +%s 2>/dev/null); _mf_num "$_mn" || return 0
    _ml=$(cat "$MF_LAST" 2>/dev/null); _mf_num "$_ml" || _ml=0
    [ $(( _mn - _ml )) -ge "$_mcd" ] || return 0
    # ROM ini bisa tidak punya `am kill-all` (terbukti di itel P65): jangan pura-pura bertindak.
    if ! am help 2>&1 | grep -q 'kill-all'; then
        printf '%s\n' "$_mn" > "$MF_LAST"; rm -f "$MF_HITS"
        _mf_log WARN "am kill-all tidak tersedia di ROM ini, pembersih adaptif dilewati"
        return 0
    fi
    am kill-all >/dev/null 2>&1
    printf '%s\n' "$_mn" > "$MF_LAST"; rm -f "$MF_HITS"
    _mf_log APPLIED "tekanan memori ${_mv} (ambang ${_mth}, x100) selama $_mh sampel -> am kill-all${1:+ saat $1}"
}

# ------------------------------------------------------------------ kemampuan (hanya baca)
mf_caps() {
    printf 'psi=%s\n' "$([ -r "$MF_PSI" ] && echo 1 || echo 0)"
    printf 'mglru=%s\n' "$([ -r "$MF_LRU/enabled" ] && echo 1 || echo 0)"
    printf 'mglru_enabled=%s\n' "$([ -r "$MF_LRU/enabled" ] && _mf_raw_on "$(tr -d '[:space:]' < "$MF_LRU/enabled")" && echo 1 || echo 0)"
    printf 'lmk_use_psi=%s\n' "$(getprop ro.lmk.use_psi 2>/dev/null)"
    printf 'lmk_partial_stall_ms=%s\n' "$(getprop ro.lmk.psi_partial_stall_ms 2>/dev/null)"
    printf 'low_ram=%s\n' "$(getprop ro.config.low_ram 2>/dev/null)"
    printf 'freezer_cfg=%s\n' "$(command -v device_config >/dev/null 2>&1 && device_config get activity_manager_native_boot use_freezer 2>/dev/null)"
}

# Bebaskan RAM sekali saat game mulai (opt-in: MEMCLEAN_ON_START=1). Setara "Free RAM" di AZenith tapi
# memakai `am kill-all` (hanya proses yang aman dimatikan), bukan force-stop massal.
mf_start_clean() {
    [ "$(_mf_conf MEMCLEAN_ON_START 0)" = 1 ] || return 0
    _mf_ok memclean || return 0
    am help 2>&1 | grep -q 'kill-all' || { _mf_log WARN "am kill-all tidak tersedia, free RAM saat game mulai dilewati"; return 0; }
    am kill-all >/dev/null 2>&1
    _mf_log APPLIED "am kill-all saat game mulai${1:+: $1}"
}
