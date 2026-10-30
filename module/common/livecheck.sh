#!/system/bin/sh
# Alpha Fusion - cek fitur langsung (<= ~10 dtk, aman, tidak mengubah setelan permanen).
# Keluaran: STATUS|nama|keterangan   (OK / GAGAL / LEWAT)
STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
CPUFREQ=/sys/devices/system/cpu/cpufreq
DEVFREQ=/sys/class/devfreq
r() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }
alive() { # $1=pidfile $2=pola cmdline
    [ -f "$1" ] || return 1
    _p=$(tr -d '[:space:]' < "$1" 2>/dev/null)
    [ -n "$_p" ] && [ -r "/proc/$_p/cmdline" ] && tr '\000' ' ' < "/proc/$_p/cmdline" 2>/dev/null | grep -q "$2"
}

# --- proses modul
alive "$STATE_DIR/monitor.pid" monitor.sh && r OK "Monitor" "jalan" || r GAGAL "Monitor" "tidak jalan"
alive "$STATE_DIR/watchdog.pid" watchdog.sh && r OK "Watchdog" "jalan" || r GAGAL "Watchdog" "tidak jalan"
alive "$STATE_DIR/autoctl.pid" autoctl.sh && r OK "Auto-profile" "jalan" || r GAGAL "Auto-profile" "tidak jalan"
if [ -n "$(pidof uperf 2>/dev/null)" ]; then r OK "Uperf" "jalan"; else r LEWAT "Uperf" "tidak jalan (normal saat Overdrive/fas-rs memegang CPU)"; fi
if [ -n "$(pidof fas-rs 2>/dev/null)" ]; then r OK "fas-rs" "jalan"; else r LEWAT "fas-rs" "tidak jalan"; fi

# --- Overdrive: node frekuensi bisa ditulis (nilai sama ditulis balik, tidak mengubah apa pun)
ok=0; bad=0
for n in "$CPUFREQ"/policy*/scaling_min_freq; do
    [ -f "$n" ] || continue
    v=$(cat "$n" 2>/dev/null); [ -n "$v" ] || continue
    if printf '%s' "$v" > "$n" 2>/dev/null; then ok=$((ok + 1)); else bad=$((bad + 1)); fi
done
[ "$ok" -gt 0 ] && [ "$bad" -eq 0 ] && r OK "Overdrive: lantai CPU" "$ok kluster bisa diatur" || r GAGAL "Overdrive: lantai CPU" "ok=$ok gagal=$bad"
g=""
for d in "$DEVFREQ"/*gpu*; do [ -f "$d/min_freq" ] && [ -f "$d/max_freq" ] && { g=$d; break; }; done
if [ -n "$g" ]; then
    v=$(cat "$g/min_freq" 2>/dev/null)
    if printf '%s' "$v" > "$g/min_freq" 2>/dev/null; then r OK "Overdrive: lantai GPU" "${g##*/} bisa diatur"; else r GAGAL "Overdrive: lantai GPU" "${g##*/} tidak bisa ditulis"; fi
else
    r LEWAT "Overdrive: lantai GPU" "node GPU tidak ditemukan"
fi
if [ -f "$STATE_DIR/.ovd_active" ]; then r OK "Overdrive" "sedang aktif ($(sed -n 2p "$STATE_DIR/.ovd_active" 2>/dev/null))"; else r LEWAT "Overdrive" "tidak aktif sekarang"; fi

# --- sensor suhu
t=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
[ -n "$t" ] && r OK "Suhu baterai" "$((t / 10)) C" || r GAGAL "Suhu baterai" "tidak terbaca"
mx=0
for z in /sys/class/thermal/thermal_zone*/temp; do v=$(cat "$z" 2>/dev/null); case "$v" in ''|*[!0-9]*) continue ;; esac; [ "$v" -lt 150000 ] && [ "$v" -gt "$mx" ] && mx=$v; done
[ "$mx" -gt 0 ] && r OK "Suhu SoC" "$((mx / 1000)) C (zona terpanas)" || r GAGAL "Suhu SoC" "tidak terbaca"

# --- Game Mode Android: uji nyata pada app Alpha sendiri, lalu dibuang
if command -v cmd >/dev/null 2>&1 && cmd game help >/dev/null 2>&1; then
    T=com.alphabubble
    cmd game reset "$T" >/dev/null 2>&1
    if cmd game set --mode 2 --downscale 0.9 "$T" >/dev/null 2>&1 && cmd game list-configs "$T" 2>/dev/null | grep -q 'Scaling:0.9'; then
        r OK "Game Mode + skala resolusi" "terpasang dan terbaca (diuji lalu dibuang)"
    else
        r GAGAL "Game Mode + skala resolusi" "ROM menolak perintah"
    fi
    cmd game reset "$T" >/dev/null 2>&1
    cmd game list-configs "$T" 2>/dev/null | grep -q 'Scaling' && r GAGAL "Game Mode reset" "override tidak terhapus" || r OK "Game Mode reset" "override terhapus"
else
    r LEWAT "Game Mode" "cmd game tidak ada di ROM ini"
fi

# --- lain-lain
cmd -l 2>/dev/null | grep -q '^[[:space:]]*notification$' && r OK "DND otomatis" "perintah tersedia" || r LEWAT "DND otomatis" "perintah tidak ada"
rr=$(getprop debug.hwui.renderer 2>/dev/null); r OK "Renderer" "${rr:-default}"
[ -r /proc/pressure/memory ] && r OK "PSI memori" "tersedia" || r LEWAT "PSI memori" "kernel tidak punya"
[ -e /sys/kernel/mm/lru_gen/enabled ] && r OK "MGLRU" "didukung" || r LEWAT "MGLRU" "kernel tidak punya"
if [ -f "$STATE_DIR/.bubble_want" ]; then
    dumpsys activity services com.alphabubble/.BubbleService 2>/dev/null | grep -q ServiceRecord && r OK "Floating" "service hidup" || r GAGAL "Floating" "service mati (watchdog akan menghidupkan)"
else
    r LEWAT "Floating" "tidak diminta aktif"
fi

# --- sumber FPS (butuh game terbuka)
fg=$(cat "$STATE_DIR/.hud_foreground_pkg" 2>/dev/null)
if [ -f "$STATE_DIR/.game_t0" ] && [ -n "$fg" ]; then
    o=$(sh "$(dirname "$0")/hud_sample.sh" --once "$fg" 2>/dev/null)
    f=$(printf '%s\n' "$o" | sed -n 's/^fps_x10=//p' | head -n 1); l=$(printf '%s\n' "$o" | sed -n 's/^lat=//p' | head -n 1)
    if [ -n "$f" ]; then r OK "Sumber FPS" "$fg = $((f / 10)) FPS"; elif [ -n "$l" ]; then r OK "Sumber FPS" "$fg (layer latency tersedia)"; else r GAGAL "Sumber FPS" "ROM tidak memberi angka FPS untuk $fg"; fi
else
    r LEWAT "Sumber FPS" "buka game dulu lalu cek lagi"
fi
