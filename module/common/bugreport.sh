#!/system/bin/sh
# Alpha Fusion - bugreport: kumpulkan satu arsip untuk dilaporkan.
#   bugreport.sh            -> /sdcard/Download/Alpha_bugreport_<tanggal>.tar.gz (atau folder bila tar tidak ada)
# Isi: log Alpha (2000 baris terakhir), konfigurasi/state Alpha, status, kemampuan perangkat, versi modul,
# model/SoC/Android, mode layar yang didukung, daftar game TERDAFTAR di Alpha.
# TIDAK diambil: daftar semua app, akun, serial/IMEI, isi /sdcard, riwayat.
COMMON="${0%/*}"
STATE_DIR="${ALPHA_STATE_DIR:-/data/adb/alpha}"
OUT_ROOT="${ALPHA_BUGREPORT_DIR:-/sdcard/Download}"
TS=$(date '+%Y%m%d_%H%M%S' 2>/dev/null)
NAME="Alpha_bugreport_$TS"
W="${TMPDIR:-/data/local/tmp}/$NAME"
mkdir -p "$W" "$OUT_ROOT" 2>/dev/null || { echo "ERROR: tidak bisa membuat folder kerja"; exit 1; }

tail -n 2000 "$STATE_DIR/alpha.log" > "$W/alpha.log" 2>/dev/null
for f in detected.conf defaults.conf app.conf game_profile_map.conf game_render.conf game_opts.conf \
         device_mitigation.conf active_profile current_state; do
    [ -f "$STATE_DIR/$f" ] && cp "$STATE_DIR/$f" "$W/$f" 2>/dev/null
done
ls -a "$STATE_DIR" > "$W/state_files.txt" 2>/dev/null
{
    echo "== module.prop"; cat "$COMMON/../module.prop" 2>/dev/null
    echo; echo "== getprop (ringkas)"
    for p in ro.product.manufacturer ro.product.model ro.product.device ro.board.platform ro.hardware \
             ro.soc.model ro.build.version.release ro.build.version.sdk ro.build.fingerprint ro.build.type \
             ro.hwui.use_vulkan debug.hwui.renderer ro.gfx.angle.supported; do
        printf '%s=%s\n' "$p" "$(getprop $p 2>/dev/null)"
    done
    echo; echo "== kernel"; uname -a 2>/dev/null
    echo; echo "== swaps"; cat /proc/swaps 2>/dev/null
    echo; echo "== refresh settings"
    for k in min_refresh_rate peak_refresh_rate user_refresh_rate; do
        printf '%s=%s\n' "$k" "$(settings get system $k 2>/dev/null)"
    done
    echo; echo "== SurfaceFlinger modes"
    dumpsys SurfaceFlinger 2>/dev/null | grep -E 'DisplayMode|activeMode' | head -n 24
    echo; echo "== modul root terpasang (nama saja)"; ls /data/adb/modules 2>/dev/null
} > "$W/device.txt" 2>&1
sh "$COMMON/alphactl.sh" status > "$W/status.txt" 2>&1
sh "$COMMON/alphactl.sh" flags > "$W/flags.txt" 2>&1
sh "$COMMON/alphactl.sh" features > "$W/features.txt" 2>&1
sh "$COMMON/alphactl.sh" health > "$W/health.txt" 2>&1

if command -v tar >/dev/null 2>&1; then
    ( cd "${W%/*}" && tar -czf "$OUT_ROOT/$NAME.tar.gz" "$NAME" ) 2>/dev/null && {
        rm -rf "$W"; echo "OK: $OUT_ROOT/$NAME.tar.gz"; exit 0; }
fi
rm -rf "$OUT_ROOT/$NAME" 2>/dev/null
mv "$W" "$OUT_ROOT/$NAME" 2>/dev/null && echo "OK: $OUT_ROOT/$NAME (folder, tar tidak tersedia)" || { echo "ERROR: gagal menyimpan"; exit 1; }
