#!/bin/sh
# Alpha Fusion selftest: menguji skrip modul di Linux biasa dengan stub Android (tanpa HP).
#   sh tools/selftest/run.sh [folder_modul]      (default: dua tingkat di atas file ini)
# Yang diuji: gamehooks (prioritas, DND, refresh SF, render, ANGLE, Game Mode API + fps, preload, grace, mitigasi),
# gamescan, shield, bugreport, trim, memfx (PSI/MGLRU/pembersih), verifikasi manifest. Yang TIDAK bisa diuji di sini: perilaku asli
# kernel/ROM (nilai sysfs, SurfaceFlinger asli, cmd game asli). Itu tetap harus dicoba di perangkat.
M="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
C="$M/common"
T=$(mktemp -d /tmp/alpha_selftest.XXXXXX)
trap 'kill $(cat "$T"/*.pid 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (dapat=[$2] harap=[$3])"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (tidak ada [$3] di [$2])" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1 (ada [$3])" ;; *) ok "$1" ;; esac; }

mkdir -p "$T/bin" "$T/st" "$T/props" "$T/db" "$T/sdcard"
# ------------------------------------------------------------------ stub Android
cat > "$T/bin/getprop" <<'S'
#!/bin/sh
cat "$T/props/$1" 2>/dev/null
S
cat > "$T/bin/setprop" <<'S'
#!/bin/sh
printf '%s' "$2" > "$T/props/$1"; echo "setprop $1=[$2]" >> "$T/calls.log"
S
cat > "$T/bin/resetprop" <<'S'
#!/bin/sh
shift; printf '%s' "$2" > "$T/props/$1"
S
cat > "$T/bin/settings" <<'S'
#!/bin/sh
DB="$T/db/settings"; touch "$DB"
case "$1" in
 get) v=$(grep "^$2 $3=" "$DB" | tail -n1 | cut -d= -f2-); echo "${v:-null}" ;;
 put) grep -v "^$2 $3=" "$DB" > "$DB.n"; echo "$2 $3=$4" >> "$DB.n"; mv "$DB.n" "$DB" ;;
 delete) grep -v "^$2 $3=" "$DB" > "$DB.n"; mv "$DB.n" "$DB" ;;
esac
S
cat > "$T/bin/cmd" <<'S'
#!/bin/sh
case "$1" in
 -l) echo "Currently running services:"; echo "  activity"; [ -f "$T/nogamecmd" ] || echo "  game"; echo "  notification" ;;
 game) echo "cmd $*" >> "$T/calls.log" ;;
 notification)
    case "$2 $3" in
      "set_dnd priority") "$T/bin/settings" put global zen_mode 1; echo "dnd priority" >> "$T/calls.log" ;;
      "set_dnd off") "$T/bin/settings" put global zen_mode 0; echo "dnd off" >> "$T/calls.log" ;;
    esac ;;
 package) echo "priority=0"; echo "$5/.Main" ;;
esac
S
cat > "$T/bin/pm" <<'S'
#!/bin/sh
case "$1" in
 list) cat "$T/installed.txt" 2>/dev/null ;;
 path)
    if [ -f "$T/pm_path_$2" ]; then cat "$T/pm_path_$2"
    elif [ "$2" = com.android.angle ] && [ -f "$T/angle_apk" ]; then echo "package:/x/angle.apk"
    else exit 1; fi ;;
esac
S
cat > "$T/bin/dumpsys" <<'S'
#!/bin/sh
A=$(cat "$T/active_hz" 2>/dev/null || echo 60)
if [ "$1" = SurfaceFlinger ] && [ -z "$2" ]; then
  id=0; [ "$A" = 90 ] && id=1; [ "$A" = 120 ] && id=2
  echo "  activeMode=DisplayMode{id=$id, hwcId=$id, resolution=1080x2400, vsyncRate=$A.000004 Hz, dpi=400x400}"
  echo "    DisplayMode{id=0, hwcId=0, resolution=1080x2400, vsyncRate=60.000004 Hz, dpi=400x400}"
  echo "    DisplayMode{id=1, hwcId=1, resolution=1080x2400, vsyncRate=90.000000 Hz, dpi=400x400}"
  echo "    DisplayMode{id=2, hwcId=2, resolution=1080x2400, vsyncRate=119.99 Hz, dpi=400x400}"
elif [ "$1" = display ]; then echo "fps=60.0"; echo "fps=90.0"; echo "fps=120.0"; fi
S
cat > "$T/bin/service" <<'S'
#!/bin/sh
echo "service $*" >> "$T/calls.log"
case "$5" in 0) echo 60 > "$T/active_hz";; 1) echo 90 > "$T/active_hz";; 2) echo 120 > "$T/active_hz";; -1) echo 60 > "$T/active_hz";; esac
echo "Result: Parcel(00000000)"
S
cat > "$T/bin/renice" <<'S'
#!/bin/sh
echo "renice $*" >> "$T/calls.log"
S
cat > "$T/bin/ionice" <<'S'
#!/bin/sh
echo "ionice $*" >> "$T/calls.log"
S
cat > "$T/bin/am" <<'S'
#!/bin/sh
[ "$1" = help ] && { echo "  am kill-all"; exit 0; }
echo "am $*" >> "$T/calls.log"
S
cat > "$T/bin/ndc" <<'S'
#!/bin/sh
echo "ndc $*" >> "$T/calls.log"
S
cat > "$T/bin/pidof" <<'S'
#!/bin/sh
[ -f "$T/running_$1" ] && cat "$T/running_$1" && exit 0
exit 1
S
cat > "$T/bin/mount" <<'S'
#!/bin/sh
# mount --bind <src> <target>
[ "$1" = "--bind" ] || exit 1
[ -f "$T/mount_fail" ] && exit 1
echo "$2 $3 none bind 0 0" >> "$T/proc_mounts"; echo "mount $*" >> "$T/calls.log"
S
cat > "$T/bin/umount" <<'S'
#!/bin/sh
grep -v " $1 " "$T/proc_mounts" > "$T/proc_mounts.n"; mv "$T/proc_mounts.n" "$T/proc_mounts"; echo "umount $*" >> "$T/calls.log"
S
cat > "$T/bin/fstrim" <<'S'
#!/bin/sh
echo "fstrim $*" >> "$T/calls.log"
[ -f "$T/fstrim_fail" ] && { echo "operation not permitted"; exit 1; }
echo "$2: 1 GiB (1073741824 bytes) trimmed"
S
cat > "$T/bin/sm" <<'S'
#!/bin/sh
echo "sm $*" >> "$T/calls.log"
S
cat > "$T/bin/chcon" <<'S'
#!/bin/sh
exit 0
S
chmod +x "$T/bin/"*
touch "$T/proc_mounts"
export T PATH="$T/bin:$PATH" ALPHA_STATE_DIR="$T/st" ALPHA_LOG_FILE="$T/alpha.log" ALPHA_GB_GRACE=0 \
       ALPHA_MEMINFO="$T/meminfo" ALPHA_PSI_FILE="$T/psi" ALPHA_LRUGEN_DIR="$T/lru_none" ALPHA_BATT_CAP="$T/batt" \
       ALPHA_PROC_MOUNTS="$T/proc_mounts" ALPHA_HOSTS_TARGET="$T/etc_hosts" TMPDIR="$T"
echo "hosts asli" > "$T/etc_hosts"
sleep 600 & echo $! > "$T/sleep1.pid"; echo $! > "$T/running_com.x.game"

echo "== 1. sintaks semua skrip"
for f in "$C"/*.sh "$M"/*.sh "$M"/tools/*.sh; do
    if sh -n "$f" 2>/dev/null; then :; else bad "sintaks $f"; fi
done; ok "semua skrip lolos sh -n"

. "$C/gamehooks.sh"
. "$C/memfx.sh"
printf 'MemTotal: 8000000 kB\nMemAvailable: 4194304 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "$T/meminfo"
echo 80 > "$T/batt"

echo "== 2. mitigasi per perangkat"
printf 'Pixel7\n' > "$T/props/ro.product.model"; printf 'lynx\n' > "$T/props/ro.product.device"; printf 'gs201\n' > "$T/props/ro.board.platform"
gh_feat_ok refresh && ok "tanpa aturan: refresh boleh" || bad "refresh seharusnya boleh"
printf '# komentar\npixel7 refresh\n*GS2* angle\nsm-g9* all\n' > "$ALPHA_STATE_DIR/device_mitigation.conf"
_GH_IDS=""
gh_feat_ok refresh && bad "refresh harus diblok (model cocok, beda huruf besar/kecil)" || ok "pola model cocok -> refresh diblok"
gh_feat_ok angle && bad "angle harus diblok (glob board)" || ok "pola glob board -> angle diblok"
gh_feat_ok prio && ok "fitur lain tidak ikut diblok (tidak ada false positive)" || bad "prio salah diblok"
printf 'sm-g9* all\n' > "$ALPHA_STATE_DIR/device_mitigation.conf"; _GH_IDS=""
gh_feat_ok dnd && ok "pola yang tidak cocok tidak memblok apa pun" || bad "false positive pola all"
printf 'pixel* all\n' > "$ALPHA_STATE_DIR/device_mitigation.conf"; _GH_IDS=""
gh_feat_ok gamemode && bad "all harus memblok semua fitur" || ok "fitur 'all' memblok semuanya"
chk "mit_check daftar (semua fitur)" "$(gh_mit_check | wc -l | tr -d ' ')" "11"
rm -f "$ALPHA_STATE_DIR/device_mitigation.conf"; _GH_IDS=""
chk "mit_add valid" "$(gh_mit_add 'm5*' refresh)" "OK: m5* refresh"
has "mit_add fitur salah ditolak" "$(gh_mit_add x foo)" "ERROR"
has "mit_add pola berbahaya ditolak" "$(gh_mit_add 'a;b' refresh)" "ERROR"
gh_mit_remove 'm5*' refresh >/dev/null; chk "mit_remove" "$(gh_mit_list)" ""
touch "$ALPHA_STATE_DIR/FEAT_dnd_OFF"; gh_feat_ok dnd && bad "FEAT_dnd_OFF harus mematikan dnd" || ok "file FEAT_dnd_OFF mematikan fitur"; rm -f "$ALPHA_STATE_DIR/FEAT_dnd_OFF"

echo "== 3. opsi per game"
chk "set gamemode" "$(gh_opt_set com.x.game gamemode performance)" "OK: com.x.game gamemode=performance"
chk "set downscale" "$(gh_opt_set com.x.game downscale 0.7)" "OK: com.x.game downscale=0.7"
chk "get downscale" "$(gh_opt_get com.x.game downscale off)" "0.7"
has "downscale di luar rentang ditolak" "$(gh_opt_set com.x.game downscale 0.3)" "ERROR"
has "downscale bukan angka ditolak" "$(gh_opt_set com.x.game downscale abc)" "ERROR"
has "gamemode salah ditolak" "$(gh_opt_set com.x.game gamemode turbo)" "ERROR"
has "package berbahaya ditolak" "$(gh_opt_set 'a;rm' gamemode off)" "ERROR"
chk "off menghapus baris" "$(gh_opt_set com.x.game downscale off >/dev/null; gh_opt_get com.x.game downscale off)" "off"
# titik pada nama package harus literal: com.x.game tidak boleh menghapus/membaca comXxXgame
gh_opt_set comXxXgame downscale 0.6 >/dev/null; gh_opt_set com.x.game downscale 0.9 >/dev/null
chk "package mirip (titik vs huruf) tidak tertukar" "$(gh_opt_get comXxXgame downscale off)|$(gh_opt_get com.x.game downscale off)" "0.6|0.9"
gh_opt_set com.x.game downscale off >/dev/null; chk "hapus satu tidak menghapus yang mirip" "$(gh_opt_get comXxXgame downscale off)" "0.6"
gh_opt_set comXxXgame downscale off >/dev/null

echo "== 4. siklus game lengkap (prioritas, DND, refresh SF, Game Mode)"
: > "$T/calls.log"; echo 60 > "$T/active_hz"
touch "$ALPHA_STATE_DIR/GAME_DND_ON"; printf 'GAME_REFRESH_HZ=90\n' > "$ALPHA_STATE_DIR/app.conf"
gh_opt_set com.x.game downscale 0.8 >/dev/null
gh_foreground com.x.game performance
chk "marker game aktif" "$(cat "$GH_MARK" 2>/dev/null)" "com.x.game"
c=$(cat "$T/calls.log")
has "renice dipanggil" "$c" "renice"
has "DND prioritas" "$c" "dnd priority"
has "SF mode 90Hz (indeks 1)" "$c" "service call SurfaceFlinger 1035 i32 1"
has "cmd game set mode+downscale" "$c" "cmd game set --mode performance --downscale 0.8 com.x.game"
chk "refresh aktif 90" "$(cat "$T/active_hz")" "90"
gh_foreground com.android.launcher ""
sleep 1; gh_tick
c=$(cat "$T/calls.log")
has "DND dikembalikan" "$c" "dnd off"
has "SF dikembalikan ke auto" "$c" "i32 -1"
has "cmd game reset" "$c" "cmd game reset com.x.game"
chk "marker bersih" "$(ls "$ALPHA_STATE_DIR" | grep -c '^\.gh_')" "0"

echo "== 5. mitigasi benar-benar menghentikan fitur"
: > "$T/calls.log"; printf '*pixel* gamemode\n' > "$ALPHA_STATE_DIR/device_mitigation.conf"; _GH_IDS=""
gh_opt_set com.x.game downscale 0.8 >/dev/null
gh_foreground com.x.game performance
hasnt "cmd game TIDAK dipanggil saat dimitigasi" "$(cat "$T/calls.log")" "cmd game set"
gh_foreground com.android.launcher ""; sleep 1; gh_tick
rm -f "$ALPHA_STATE_DIR/device_mitigation.conf"; _GH_IDS=""
gh_opt_set com.x.game downscale off >/dev/null; rm -f "$ALPHA_STATE_DIR/GAME_DND_ON"; printf 'GAME_REFRESH_HZ=off\n' > "$ALPHA_STATE_DIR/app.conf"

echo "== 6. cmd game tidak ada (Android lama)"
: > "$T/calls.log"; touch "$T/nogamecmd"; gh_opt_set com.x.game gamemode performance >/dev/null
gh_foreground com.x.game performance
hasnt "tidak crash, tidak memanggil cmd game set" "$(cat "$T/calls.log")" "cmd game set"
has "peringatan di log" "$(cat "$T/alpha.log")" "cmd game tidak tersedia"
gh_foreground com.android.launcher ""; sleep 1; gh_tick; rm -f "$T/nogamecmd"; gh_opt_set com.x.game gamemode off >/dev/null

echo "== 7. render per game: renderer awal KOSONG harus dikembalikan (bug v53b)"
: > "$T/calls.log"; printf '' > "$T/props/debug.hwui.renderer"; printf '34' > "$T/props/ro.build.version.sdk"; printf 'true' > "$T/props/ro.hwui.use_vulkan"
chk "set skiavk" "$(gh_render_set com.x.game skiavk)" "OK: render com.x.game -> skiavk"
rm -f "$T/running_com.x.game"
has "launch menerapkan skiavk" "$(gh_launch com.x.game)" "render=skiavk"
chk "prop terpasang skiavk" "$(cat "$T/props/debug.hwui.renderer")" "skiavk"
echo $$ > "$T/running_com.x.game"
gh_foreground com.x.game performance; gh_foreground com.android.launcher ""; sleep 1; gh_tick
chk "prop kembali KOSONG setelah game selesai" "$(cat "$T/props/debug.hwui.renderer")" ""
chk "file prev dibersihkan" "$([ -f "$GH_REND_PREV" ] && echo ada || echo bersih)" "bersih"
gh_render_set com.x.game default >/dev/null

echo "== 8. ANGLE per game"
: > "$T/calls.log"
has "angle ditolak bila tidak didukung" "$(gh_render_set com.x.game angle)" "ERROR"
touch "$T/angle_apk"
chk "angle diterima bila didukung" "$(gh_render_set com.x.game angle)" "OK: render com.x.game -> angle"
rm -f "$T/running_com.x.game"; gh_launch com.x.game >/dev/null
chk "pkgs ANGLE terpasang" "$(settings get global angle_gl_driver_selection_pkgs)" "com.x.game"
chk "values ANGLE terpasang" "$(settings get global angle_gl_driver_selection_values)" "angle"
echo $$ > "$T/running_com.x.game"
gh_foreground com.x.game performance; gh_foreground com.android.launcher ""; sleep 1; gh_tick
chk "ANGLE dibuang (tidak ada nilai awal)" "$(settings get global angle_gl_driver_selection_pkgs)" "null"
# pengguna sudah punya daftar ANGLE sendiri -> digabung lalu dipulihkan persis
settings put global angle_gl_driver_selection_pkgs "com.lain" >/dev/null; settings put global angle_gl_driver_selection_values "native" >/dev/null
rm -f "$T/running_com.x.game"; gh_launch com.x.game >/dev/null
chk "daftar pengguna digabung" "$(settings get global angle_gl_driver_selection_pkgs)" "com.lain,com.x.game"
chk "values digabung sejajar" "$(settings get global angle_gl_driver_selection_values)" "native,angle"
echo $$ > "$T/running_com.x.game"
gh_foreground com.x.game performance; gh_foreground com.android.launcher ""; sleep 1; gh_tick
chk "daftar pengguna pulih persis" "$(settings get global angle_gl_driver_selection_pkgs)|$(settings get global angle_gl_driver_selection_values)" "com.lain|native"
# pengguna sudah memilih ANGLE untuk game ini -> tidak disentuh sama sekali
settings put global angle_gl_driver_selection_pkgs "com.x.game" >/dev/null; settings put global angle_gl_driver_selection_values "angle" >/dev/null
rm -f "$T/running_com.x.game"; gh_launch com.x.game >/dev/null
chk "pilihan pengguna tidak ditimpa" "$([ -f "$GH_ANGLE_PREV" ] && echo prev || echo none)" "none"
echo $$ > "$T/running_com.x.game"; gh_render_set com.x.game default >/dev/null
settings delete global angle_gl_driver_selection_pkgs; settings delete global angle_gl_driver_selection_values

echo "== 9. peluncuran yatim (game tidak pernah masuk foreground) dibersihkan oleh timeout"
gh_opt_set com.x.game gamemode performance >/dev/null; gh_render_set com.x.game angle >/dev/null
rm -f "$T/running_com.x.game"; gh_launch com.x.game >/dev/null
[ -f "$GH_GM_MARK" ] && ok "marker game mode ada setelah launch" || bad "marker game mode hilang"
GH_RENDER_TIMEOUT=0; gh_tick; GH_RENDER_TIMEOUT=90
chk "yatim: ANGLE dipulihkan" "$([ -f "$GH_ANGLE_PREV" ] && echo ada || echo bersih)" "bersih"
chk "yatim: game mode dibuang" "$([ -f "$GH_GM_MARK" ] && echo ada || echo bersih)" "bersih"
gh_opt_set com.x.game gamemode off >/dev/null; gh_render_set com.x.game default >/dev/null; echo $$ > "$T/running_com.x.game"

echo "== 10. refresh rate: indeks SF dibatalkan bila salah"
printf 'GAME_REFRESH_HZ=90\nGAME_REFRESH_SF_IDX=0\n' > "$ALPHA_STATE_DIR/app.conf"
_gh_refresh_on; chk "indeks salah -> SF tidak dipakai" "$([ -f "$GH_SF_MARK" ] && echo mark || echo none)" "none"; _gh_refresh_off
chk "daftar mode SF" "$(gh_sf_modes | tr '\n' ',')" "0 60,1 90,2 120,"
printf 'GAME_REFRESH_HZ=off\n' > "$ALPHA_STATE_DIR/app.conf"

echo "== 11. kemampuan perangkat"
f=$(gh_caps)
has "caps: cmd_game" "$f" "cmd_game=1"; has "caps: angle" "$f" "angle=1"; has "caps: sf_modes" "$f" "sf_modes=3"; has "caps: refresh_list" "$f" "refresh_list=60,90,120"

echo "== 12. scan game"
GSD="$T/gs"; mkdir -p "$GSD"; cp "$C/gamescan.sh" "$GSD/"; printf 'com.a.one\ncom.b.two # komentar\ncom.c.three\n\n' > "$GSD/gamelist.seed"
printf 'package:com.a.one\npackage:com.b.two\npackage:com.c.three\npackage:com.bukan.game\npackage:com.user.extra\n' > "$T/installed.txt"
cat > "$GSD/game_add.sh" <<'S'
#!/bin/sh
case "$1" in
 add) echo "$2:$4" >> "$ALPHA_STATE_DIR/game_profile_map.conf"; echo "add $2 skip=${GA_SKIP_MERGE:-0}" >> "$T/ga.log" ;;
 merge) echo "merge" >> "$T/ga.log" ;;
esac
S
COMMON="$GSD"; . "$GSD/gamescan.sh"
chk "kandidat dari seed" "$(gs_candidates | tr '\n' ' ')" "com.a.one com.b.two com.c.three "
printf 'com.user.extra\n' > "$ALPHA_STATE_DIR/gamelist.user"
chk "daftar pengguna ikut" "$(gs_candidates | tr '\n' ' ')" "com.a.one com.b.two com.c.three com.user.extra "
printf 'com.b.two:balanced\n' > "$ALPHA_STATE_DIR/game_profile_map.conf"
chk "yang sudah terdaftar tidak jadi kandidat" "$(gs_candidates | tr '\n' ' ')" "com.a.one com.c.three com.user.extra "
: > "$T/ga.log"
has "add_all" "$(gs_add_all performance 60)" "OK: 3 game ditambahkan"
chk "merge hanya SEKALI" "$(grep -c '^merge' "$T/ga.log")" "1"
chk "semua add pakai SKIP_MERGE" "$(grep -c 'skip=1' "$T/ga.log")" "3"
has "profil salah ditolak" "$(gs_add_all turbo)" "ERROR"
has "setelah add tidak ada kandidat" "$(gs_add_all)" "0 game baru"
COMMON="$C"
chk "seed Encore terbaca (>500 paket)" "$([ "$(grep -c . "$C/gamelist.seed")" -gt 500 ] && echo ya || echo tidak)" "ya"

echo "== 13. Shield (hosts)"
SH="sh $C/shield.sh"; L="$T/lists"; mkdir -p "$L"
printf '# daftar A\n0.0.0.0 ads.example.com\n127.0.0.1 TRACK.example.net\nlocalhost\n0.0.0.0 ads.example.com\n' > "$L/a.txt"
printf 'tracker.foo.org\r\nads.example.com\r\n# c\r\nBAD DOMAIN!!\r\n' > "$L/b.txt"
has "apply tanpa daftar aktif ditolak" "$($SH apply)" "ERROR"
has "import file" "$($SH import "$L/a.txt")" "OK"; $SH import "$L/b.txt" >/dev/null
has "import nama tidak valid ditolak" "$($SH import "$L/a.txt" 'x;y')" "ERROR"
$SH enable a >/dev/null; $SH enable b >/dev/null
has "apply sukses" "$($SH on)" "OK: Shield aktif"
A="$ALPHA_STATE_DIR/shield/active_hosts"
chk "localhost tetap" "$(sed -n 1p "$A")" "127.0.0.1 localhost"
has "domain diblokir (dinormalisasi huruf kecil)" "$(cat "$A")" "0.0.0.0 track.example.net"
has "format CRLF dibersihkan" "$(cat "$A")" "0.0.0.0 tracker.foo.org"
chk "duplikat dibuang" "$(grep -c '^0.0.0.0 ads.example.com$' "$A")" "1"
hasnt "baris sampah dibuang" "$(cat "$A")" "BAD"
hasnt "localhost tidak ikut diblokir" "$(cat "$A")" "0.0.0.0 localhost"
chk "status mounted" "$($SH status | grep '^mounted=')" "mounted=1"
chk "jumlah domain" "$($SH status | grep '^domains=')" "domains=3"
$SH allow add ads.example.com >/dev/null; $SH apply >/dev/null
hasnt "pengecualian dihormati" "$(cat "$A")" "ads.example.com"
chk "pengecualian mengurangi jumlah" "$($SH status | grep '^domains=')" "domains=2"
$SH off >/dev/null; chk "off melepas mount" "$($SH status | grep '^mounted=')" "mounted=0"
chk "hosts asli utuh" "$(cat "$T/etc_hosts")" "hosts asli"
echo "$ALPHA_HOSTS_TARGET $ALPHA_HOSTS_TARGET none bind 0 0" > "$T/proc_mounts"   # modul lain sudah mount
has "tidak menimpa mount modul lain" "$($SH on)" "ERROR"
: > "$T/proc_mounts"; touch "$T/mount_fail"; has "mount gagal dilaporkan" "$($SH apply)" "ERROR"; rm -f "$T/mount_fail"
chk "boot menerapkan bila SHIELD_ON=1" "$($SH on >/dev/null; : > "$T/proc_mounts"; $SH boot; $SH status | grep '^mounted=')" "mounted=1"
$SH off >/dev/null
# performa daftar besar (daftar riil jika ada)
BIG="${ALPHA_SELFTEST_BIGLIST:-}"
if [ -n "$BIG" ] && [ -f "$BIG" ]; then
    $SH import "$BIG" big >/dev/null; $SH enable big >/dev/null; s=$(date +%s); $SH apply >/dev/null; e=$(date +%s)
    ok "daftar besar ($(wc -l < "$BIG") baris) diproses dalam $((e-s)) dtk, domain=$($SH status | grep '^domains=' | cut -d= -f2)"; $SH off >/dev/null
fi

echo "== 14. verifikasi manifest"
V="$T/modv"; mkdir -p "$V/common" "$V/META-INF"; echo A > "$V/a.txt"; echo B > "$V/common/b.sh"; echo X > "$V/META-INF/skip"
sh "$M/tools/make_manifest.sh" "$V" >/dev/null
chk "manifest tanpa META-INF dan dirinya sendiri" "$(cut -d' ' -f3 "$V/MANIFEST.sha256" | tr '\n' ' ')" "a.txt common/b.sh "
VSNIP=$(sed -n '/^if \[ -f "\$MODPATH\/MANIFEST.sha256" \]; then/,/^fi$/p' "$M/customize.sh")
run_verify() { ( MODPATH="$V"; ui_print() { :; }; abort() { echo "ABORT:$1"; exit 9; }; eval "$VSNIP"; echo PASSED ); }
chk "file utuh lolos" "$(run_verify | tail -n1)" "PASSED"
echo tampered > "$V/common/b.sh"; has "file rusak -> abort" "$(run_verify | tail -n1)" "ABORT"
echo B > "$V/common/b.sh"; rm "$V/a.txt"; has "file hilang -> abort" "$(run_verify | tail -n1)" "ABORT"
rm "$V/MANIFEST.sha256"; chk "tanpa manifest dilewati" "$(run_verify | tail -n1)" "PASSED"

echo "== 15. bugreport"
mkdir -p "$T/mod/common"; cp "$C"/*.sh "$T/mod/common/"; echo "versionCode=1" > "$T/mod/module.prop"
echo "log baris" > "$ALPHA_STATE_DIR/alpha.log"; ALPHA_BUGREPORT_DIR="$T/out" ALPHA_LOG_FILE="$ALPHA_STATE_DIR/alpha.log" sh "$T/mod/common/bugreport.sh" > "$T/br.out"
has "bugreport sukses" "$(cat "$T/br.out")" "OK:"
AR=$(ls "$T/out"/*.tar.gz 2>/dev/null | head -n1)
[ -n "$AR" ] && ok "arsip dibuat" || bad "arsip tidak ada"
L=$(tar -tzf "$AR" 2>/dev/null | tr '\n' ' ')
has "isi: alpha.log" "$L" "alpha.log"; has "isi: device.txt" "$L" "device.txt"; has "isi: features.txt" "$L" "features.txt"
hasnt "tidak mengambil daftar semua app" "$L" "packages"


echo "== 16. Game Mode: target FPS (--fps)"
: > "$T/calls.log"
chk "fps valid" "$(gh_opt_set com.x.game fps 60)" "OK: com.x.game fps=60"
has "fps < 10 ditolak" "$(gh_opt_set com.x.game fps 5)" "ERROR"
has "fps > 240 ditolak" "$(gh_opt_set com.x.game fps 300)" "ERROR"
has "fps bukan angka ditolak" "$(gh_opt_set com.x.game fps abc)" "ERROR"
chk "batas bawah 10 diterima" "$(gh_opt_set com.x.game fps 10)" "OK: com.x.game fps=10"
chk "batas atas 240 diterima" "$(gh_opt_set com.x.game fps 240)" "OK: com.x.game fps=240"
gh_opt_set com.x.game fps 60 >/dev/null; gh_opt_set com.x.game downscale 0.8 >/dev/null
gh_foreground com.x.game performance
has "fps + downscale dikirim bersama" "$(cat "$T/calls.log")" "cmd game set --mode performance --downscale 0.8 --fps 60 com.x.game"
gh_foreground com.android.launcher ""; sleep 1; gh_tick
gh_opt_set com.x.game downscale off >/dev/null; : > "$T/calls.log"
gh_foreground com.x.game performance
has "fps saja -> mode performance otomatis" "$(cat "$T/calls.log")" "cmd game set --mode performance --fps 60 com.x.game"
gh_foreground com.android.launcher ""; sleep 1; gh_tick; gh_opt_set com.x.game fps off >/dev/null
has "gamefx get memuat fps dan preload" "$(sh "$C/alphactl.sh" gamefx get com.x.game | tr '\n' ' ')" "fps=off preload=off"

echo "== 17. preload page cache"
APPD="$T/app"; mkdir -p "$APPD/oat/arm64" "$APPD/lib/arm64"
mk() { dd if=/dev/zero of="$1" bs=1048576 count="$2" 2>/dev/null; }
mk "$APPD/base.apk" 3; mk "$APPD/split_a.apk" 2; mk "$APPD/oat/arm64/base.odex" 1; mk "$APPD/oat/arm64/base.vdex" 1; mk "$APPD/lib/arm64/libx.so" 1
printf 'package:%s/base.apk\npackage:%s/split_a.apk\n' "$APPD" "$APPD" > "$T/pm_path_com.x.game"
rm -f "$ALPHA_STATE_DIR/.gh_preload_t"; : > "$T/calls.log"
_gh_preload com.x.game; sleep 1
chk "opsi preload default off: tidak membaca apa pun" "$(grep -c 'dd if=' "$T/calls.log")" "0"
gh_opt_set com.x.game preload on >/dev/null
_gh_preload com.x.game; sleep 1.5
R=$(grep 'dd if=' "$T/calls.log" | sed 's|.*if=.*/\([^ /]*\) of.*count=|\1 |' | tr '\n' ',')
chk "urutan: odex, vdex, .so, base.apk, split" "$R" "base.odex 1,base.vdex 1,libx.so 1,base.apk 3,split_a.apk 2,"
has "log APPLIED dengan total MB" "$(cat "$T/alpha.log")" "preload com.x.game: 8 MB dibaca"
: > "$T/calls.log"; _gh_preload com.x.game; sleep 1
chk "cooldown 600 dtk menahan pengulangan" "$(grep -c 'dd if=' "$T/calls.log")" "0"
printf 'PRELOAD_COOLDOWN=0\nPRELOAD_MAX_MB=3\n' > "$ALPHA_STATE_DIR/app.conf"
: > "$T/calls.log"; _gh_preload com.x.game; sleep 1.5
R=$(grep 'dd if=' "$T/calls.log" | sed 's|.*if=.*/\([^ /]*\) of.*|\1|' | tr '\n' ',')
chk "PRELOAD_MAX_MB=3 membatasi total (APK tidak terbaca)" "$R" "base.odex,base.vdex,libx.so,"
printf 'PRELOAD_COOLDOWN=0\n' > "$ALPHA_STATE_DIR/app.conf"
printf 'MemTotal: 8000000 kB\nMemAvailable: 40960 kB\n' > "$T/meminfo"
: > "$T/calls.log"; _gh_preload com.x.game; sleep 1
chk "RAM bebas kecil: dilewati" "$(grep -c 'dd if=' "$T/calls.log")" "0"
has "dan dicatat WARN" "$(cat "$T/alpha.log")" "preload com.x.game dilewati: RAM bebas terlalu kecil"
printf 'MemTotal: 8000000 kB\nMemAvailable: 4194304 kB\n' > "$T/meminfo"
printf '*pixel* preload\n' > "$ALPHA_STATE_DIR/device_mitigation.conf"; _GH_IDS=""
: > "$T/calls.log"; _gh_preload com.x.game; sleep 1
chk "mitigasi preload memblok" "$(grep -c 'dd if=' "$T/calls.log")" "0"
rm -f "$ALPHA_STATE_DIR/device_mitigation.conf" "$ALPHA_STATE_DIR/app.conf" "$ALPHA_STATE_DIR/.gh_preload_t"; _GH_IDS=""
: > "$T/calls.log"; gh_foreground com.x.game performance; sleep 1.5
[ "$(grep -c 'dd if=' "$T/calls.log")" -gt 0 ] && ok "preload ikut jalan saat game masuk foreground" || bad "preload tidak jalan di gh_start"
gh_foreground com.android.launcher ""; sleep 1; gh_tick; gh_opt_set com.x.game preload off >/dev/null

echo "== 18. grace keluar game bisa diatur"
GH_GRACE=12
now=$(date +%s)
gh_foreground com.x.game performance
printf 'GAME_GRACE_SEC=30\n' > "$ALPHA_STATE_DIR/app.conf"
chk "grace dibaca dari konf" "$(_gh_grace)" "30"
gh_foreground com.android.launcher ""; echo $((now - 20)) > "$GH_PEND"; gh_tick
chk "20 dtk < 30 dtk: game masih dianggap aktif" "$([ -f "$GH_MARK" ] && echo aktif || echo selesai)" "aktif"
echo $((now - 35)) > "$GH_PEND"; gh_tick
chk "35 dtk > 30 dtk: game selesai" "$([ -f "$GH_MARK" ] && echo aktif || echo selesai)" "selesai"
for v in 2 500 abc ''; do printf 'GAME_GRACE_SEC=%s\n' "$v" > "$ALPHA_STATE_DIR/app.conf"; chk "nilai tidak valid [$v] -> default 12" "$(_gh_grace)" "12"; done
rm -f "$ALPHA_STATE_DIR/app.conf"; GH_GRACE=0

echo "== 19. trim"
printf '/dev/x /data f2fs rw 0 0\n/dev/y /system ext4 ro 0 0\n/dev/z /mnt/other ext4 rw 0 0\n' > "$T/mounts_trim"
TR="sh $C/trim.sh"; export ALPHA_PROC_MOUNTS_TRIM="$T/mounts_trim"
trimrun() { ALPHA_PROC_MOUNTS="$T/mounts_trim" $TR "$@"; }
: > "$T/calls.log"; o=$(trimrun)
has "trim: dua partisi ter-mount" "$o" "OK: 2 partisi di-trim"
chk "hanya partisi ter-mount yang dipanggil" "$(grep -c '^fstrim' "$T/calls.log")" "2"
has "keluaran fstrim ditampilkan" "$o" "/data: 1 GiB"
touch "$ALPHA_STATE_DIR/.gh_active"; has "game aktif -> ditolak" "$(trimrun)" "ERROR: game sedang aktif"
has "force mengabaikan game aktif" "$(trimrun force)" "OK: 2 partisi"; rm -f "$ALPHA_STATE_DIR/.gh_active"
echo 10 > "$T/batt"; has "baterai 10% -> ditolak" "$(trimrun)" "ERROR: baterai 10%"
has "force mengabaikan baterai" "$(trimrun force)" "OK: 2 partisi"; echo 80 > "$T/batt"
touch "$T/fstrim_fail"; has "fstrim gagal di satu partisi tidak menghentikan" "$(trimrun)" "dilewati"; rm -f "$T/fstrim_fail"
export ALPHA_FSTRIM=fstrim_tidak_ada
: > "$T/calls.log"; has "tanpa fstrim: pakai sm idle-maint" "$(trimrun)" "sm idle-maint run"
mv "$T/bin/sm" "$T/bin/sm.off"; has "tanpa fstrim dan sm: error jelas" "$(trimrun)" "ERROR: fstrim tidak tersedia"
mv "$T/bin/sm.off" "$T/bin/sm"; unset ALPHA_FSTRIM

echo "== 20. memori terintegrasi (PSI, pembersih adaptif, free RAM saat mulai)"
psi() { printf 'some avg10=%s avg60=1.00 avg300=0.50 total=1\nfull avg10=%s avg60=0.10 avg300=0.00 total=1\n' "$1" "$2" > "$T/psi"; }
psi 20.00 5.00
: > "$T/calls.log"; gh_foreground com.x.game performance; gh_tick; gh_tick; gh_tick
chk "MEMCLEAN default 0: tidak ada am kill-all" "$(grep -c 'am kill-all' "$T/calls.log")" "0"
gh_foreground com.android.launcher ""; sleep 1; gh_tick
printf 'MEMCLEAN_ON_START=1\n' > "$ALPHA_STATE_DIR/app.conf"
: > "$T/calls.log"; gh_foreground com.x.game performance
chk "MEMCLEAN_ON_START=1: am kill-all sekali saat game mulai" "$(grep -c 'am kill-all' "$T/calls.log")" "1"
gh_foreground com.android.launcher ""; sleep 1; gh_tick
printf 'MEMCLEAN=1\nMEMCLEAN_HITS=2\nMEMCLEAN_COOLDOWN=0\n' > "$ALPHA_STATE_DIR/app.conf"; rm -f "$ALPHA_STATE_DIR/.mf_hits" "$ALPHA_STATE_DIR/.mf_last"
: > "$T/calls.log"; psi 1.00 0.00; gh_tick; gh_tick
chk "di luar game: pembersih tidak jalan walau PSI tinggi" "$(psi 30.00 9.00; gh_tick; gh_tick; grep -c 'am kill-all' "$T/calls.log")" "0"
gh_foreground com.x.game performance; : > "$T/calls.log"; rm -f "$ALPHA_STATE_DIR/.mf_hits"; psi 30.00 9.00
gh_tick; chk "tick 1 (hit 1 dari 2): belum" "$(grep -c 'am kill-all' "$T/calls.log")" "0"
gh_tick; chk "tick 2: am kill-all dipicu dari gh_tick saat game aktif" "$(grep -c 'am kill-all' "$T/calls.log")" "1"
printf '*pixel* memclean\n' > "$ALPHA_STATE_DIR/device_mitigation.conf"; _GH_IDS=""; : > "$T/calls.log"; rm -f "$ALPHA_STATE_DIR/.mf_hits"
gh_tick; gh_tick; gh_tick; chk "mitigasi memclean memblok pembersih" "$(grep -c 'am kill-all' "$T/calls.log")" "0"
rm -f "$ALPHA_STATE_DIR/device_mitigation.conf" "$ALPHA_STATE_DIR/app.conf"; _GH_IDS=""
gh_foreground com.android.launcher ""; sleep 1; gh_tick
# CLI
chk "alphactl mem status" "$(sh "$C/alphactl.sh" mem status | head -n 1)" "psi=1"
chk "alphactl mglru status (kernel tanpa lru_gen)" "$(sh "$C/alphactl.sh" mglru status | head -n 1)" "supported=0"
f=$(sh "$C/alphactl.sh" features | tr '\n' ' ')
has "features memuat kemampuan game dan memori" "$f" "cmd_game="; has "features memuat psi dan mglru" "$f" "mglru="
printf 'MGLRU_MODE=on\n' > "$ALPHA_STATE_DIR/app.conf"; printf '*pixel* mglru\n' > "$ALPHA_STATE_DIR/device_mitigation.conf"; _GH_IDS=""
mkdir -p "$T/lru_none"; printf '0x0000\n' > "$T/lru_none/enabled"
mf_mglru_apply; chk "mitigasi mglru memblok penyalaan" "$(cat "$T/lru_none/enabled")" "0x0000"
rm -f "$ALPHA_STATE_DIR/device_mitigation.conf" "$ALPHA_STATE_DIR/app.conf" "$T/lru_none/enabled"; _GH_IDS=""
has "mitigation add menerima fitur baru" "$(gh_mit_add 'x*' preload; gh_mit_add 'x*' mglru; gh_mit_add 'x*' memclean; gh_mit_add 'x*' trim)" "OK: x* trim"
gh_mit_remove 'x*' preload >/dev/null; gh_mit_remove 'x*' mglru >/dev/null; gh_mit_remove 'x*' memclean >/dev/null; gh_mit_remove 'x*' trim >/dev/null
r=$(MEMFX="$C/memfx.sh" sh "$M/tools/selftest/test_memfx.sh" 2>&1 | grep '^HASIL')
p=$(printf '%s' "$r" | sed -n 's/HASIL: \([0-9]*\) lolos.*/\1/p'); f2=$(printf '%s' "$r" | sed -n 's/.* \([0-9]*\) gagal/\1/p')
[ -n "$p" ] && { PASS=$((PASS + p)); FAIL=$((FAIL + f2)); [ "$f2" = 0 ] && ok "memfx unit test ($p pemeriksaan) lolos" || bad "memfx unit test: $f2 gagal"; } || bad "memfx unit test tidak menghasilkan ringkasan"

echo; echo "HASIL: $PASS lolos, $FAIL gagal"
[ "$FAIL" -eq 0 ]
