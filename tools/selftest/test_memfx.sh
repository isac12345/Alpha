#!/bin/sh
# Uji memfx.sh dengan berkas palsu (tanpa HP):  sh test_memfx.sh
D="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d /tmp/memfx_test.XXXXXX); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (dapat=[%s] harap=[%s])\n' "$1" "$2" "$3"; fi; }
mkdir -p "$T/bin" "$T/st" "$T/props" "$T/lru"
cat > "$T/bin/getprop" <<'S'
#!/bin/sh
cat "$T/props/$1" 2>/dev/null
S
cat > "$T/bin/am" <<'S'
#!/bin/sh
[ "$1" = help ] && { echo "  am kill-all"; exit 0; }
echo "am $*" >> "$T/calls.log"
S
cat > "$T/bin/device_config" <<'S'
#!/bin/sh
echo "true"
S
chmod +x "$T/bin/"*
export T PATH="$T/bin:$PATH" ALPHA_STATE_DIR="$T/st" ALPHA_LOG_FILE="$T/log" ALPHA_PSI_FILE="$T/psi" ALPHA_LRUGEN_DIR="$T/lru" ALPHA_MEMINFO="$T/meminfo"
. "${MEMFX:-$D/memfx.sh}"
psi() { printf 'some avg10=%s avg60=1.00 avg300=0.50 total=12345\nfull avg10=%s avg60=0.10 avg300=0.00 total=99\n' "$1" "$2" > "$T/psi"; }

echo "== PSI parse"
psi 0.00 0.00;   chk "0.00 -> 0" "$(mf_psi_x100 some avg10)" "0"
psi 12.34 1.5;   chk "12.34 -> 1234" "$(mf_psi_x100 some avg10)" "1234"; chk "full 1.5 -> 150" "$(mf_psi_x100 full avg10)" "150"
psi 100.00 8.09; chk "100.00 -> 10000" "$(mf_psi_x100 some avg10)" "10000"; chk "08 tidak jadi oktal: 8.09 -> 809" "$(mf_psi_x100 full avg10)" "809"
chk "avg60 dibaca" "$(mf_psi_x100 some avg60)" "100"
rm -f "$T/psi"; mf_psi_x100 some avg10 >/dev/null && echo "  FAIL tanpa file harus gagal" || { PASS=$((PASS+1)); echo "  ok   tanpa PSI -> gagal bersih"; }
printf 'garbage\n' > "$T/psi"; mf_psi_x100 some avg10 >/dev/null && echo "  FAIL format rusak harus gagal" || { PASS=$((PASS+1)); echo "  ok   format rusak -> gagal bersih"; }

echo "== ambang dari properti lmkd (tidak ditanam)"
chk "default normal 70ms -> 7.00% -> 700" "$(mf_psi_threshold_x100)" "700"
printf 'true' > "$T/props/ro.config.low_ram"; chk "low_ram tanpa properti -> 200ms -> 2000" "$(mf_psi_threshold_x100)" "2000"
printf '120' > "$T/props/ro.lmk.psi_partial_stall_ms"; chk "properti perangkat menang: 120ms -> 1200" "$(mf_psi_threshold_x100)" "1200"
rm -f "$T/props/"*

echo "== memstat"
printf 'MemTotal:        3939180 kB\nMemAvailable:    1048576 kB\nSwapTotal:       2097152 kB\nSwapFree:        1572864 kB\n' > "$T/meminfo"; psi 3.00 0.50
s=$(mf_memstat | tr '\n' ' ')
chk "memstat lengkap" "$s" "psi=1 psi_some10_x100=300 psi_full10_x100=50 mem_avail_mb=1024 mem_total_mb=3846 swap_used_mb=512 psi_threshold_x100=700 "
rm -f "$T/psi"; chk "tanpa PSI: psi=0, sisanya tetap ada" "$(mf_memstat | head -n1)" "psi=0"

echo "== MGLRU"
chk "tanpa lru_gen: supported=0" "$(mf_mglru_status)" "supported=0"
printf '0x0000\n' > "$T/lru/enabled"; printf '0\n' > "$T/lru/min_ttl_ms"
chk "terdeteksi, mati" "$(mf_mglru_status | tr '\n' ' ')" "supported=1 enabled_raw=0x0000 enabled=0 min_ttl_ms=0 "
chk "MGLRU_MODE default off: tidak menyentuh" "$(mf_mglru_apply; cat "$T/lru/enabled")" "0x0000"
# tiru kernel: tulis 'y' -> baca 0x0007; tulis angka/hex -> baca hex
# tiru kernel (sesuai kernel doc): y -> baca 0x0007; angka desimal N -> baca 0x000N (hex 4 digit)
_mf_write() { case "$2" in y) printf '0x0007\n' > "$1" ;; *[!0-9]*) return 1 ;; *) printf '0x%04x\n' "$2" > "$1"; echo "$2" >> "$T/writes.log" ;; esac; }
printf 'MGLRU_MODE=on\n' > "$T/st/app.conf"
mf_mglru_apply; chk "mode on menyalakan" "$(mf_mglru_status | sed -n 3p)" "enabled=1"
chk "nilai asli disimpan" "$(cat "$T/st/.mf_mglru_prev")" "0x0000"
chk "min_ttl_ms TIDAK disentuh" "$(cat "$T/lru/min_ttl_ms")" "0"
mf_mglru_restore; chk "restore mengembalikan mati" "$(mf_mglru_status | sed -n 3p)" "enabled=0"
chk "restore menulis DESIMAL (bukan string hex)" "$(cat "$T/writes.log")" "0"
printf '0x0005\n' > "$T/lru/enabled"; printf 'MGLRU_MODE=on\n' > "$T/st/app.conf"
printf '0x0000\n' > "$T/st/.mf_mglru_prev"; : > "$T/writes.log"; printf '0x0005\n' > "$T/st/.mf_mglru_prev"; mf_mglru_restore
chk "restore mask parsial 0x0005 -> tulis 5" "$(cat "$T/writes.log")" "5"
printf '0x0000\n' > "$T/lru/enabled"
chk "prev dibersihkan" "$([ -f "$T/st/.mf_mglru_prev" ] && echo ada || echo bersih)" "bersih"
printf '0x0007\n' > "$T/lru/enabled"; mf_mglru_apply
chk "sudah menyala bawaan ROM: tidak ada prev (tidak akan dimatikan)" "$([ -f "$T/st/.mf_mglru_prev" ] && echo ada || echo bersih)" "bersih"
printf '0x0000\n' > "$T/lru/enabled"; _mf_write() { :; }   # kernel menolak menulis
mf_mglru_apply; chk "gagal menyala -> prev dibuang + log WARN" "$([ -f "$T/st/.mf_mglru_prev" ] && echo ada || echo bersih)|$(grep -c 'WARN.*gagal menyala' "$T/log")" "bersih|1"

echo "== pembersih adaptif"
: > "$T/calls.log"; rm -f "$T/st/.mf_hits" "$T/st/.mf_last"; psi 20.00 5.00
mf_relief_tick com.x.game; chk "MEMCLEAN default 0: tidak bertindak" "$(cat "$T/calls.log")" ""
printf 'MEMCLEAN=1\nMEMCLEAN_HITS=3\nMEMCLEAN_COOLDOWN=180\n' > "$T/st/app.conf"
mf_relief_tick g; mf_relief_tick g; chk "2 sampel belum cukup" "$(cat "$T/calls.log")" ""
mf_relief_tick g; chk "sampel ke-3 -> am kill-all" "$(cat "$T/calls.log")" "am kill-all"
: > "$T/calls.log"; mf_relief_tick g; mf_relief_tick g; mf_relief_tick g
chk "cooldown menahan tindakan kedua" "$(cat "$T/calls.log")" ""
printf '%s\n' "$(( $(date +%s) - 400 ))" > "$T/st/.mf_last"; mf_relief_tick g
chk "setelah cooldown lewat -> bertindak lagi" "$(cat "$T/calls.log")" "am kill-all"
: > "$T/calls.log"; rm -f "$T/st/.mf_last" "$T/st/.mf_hits"; psi 20.00 5.00; mf_relief_tick g; mf_relief_tick g; psi 1.00 0.00; mf_relief_tick g; psi 20.00 5.00; mf_relief_tick g; mf_relief_tick g
chk "tekanan turun di tengah mereset hitungan" "$(cat "$T/calls.log")" ""
rm -f "$T/psi" "$T/st/.mf_hits"; mf_relief_tick g; chk "tanpa PSI: diam, tidak error" "$(cat "$T/calls.log")" ""
chk "ambang dari properti: 6.99% tidak memicu" "$(rm -f "$T/st/.mf_hits" "$T/st/.mf_last"; psi 6.99 0; : > "$T/calls.log"; mf_relief_tick g; mf_relief_tick g; mf_relief_tick g; cat "$T/calls.log")" ""

echo "== caps"
psi 0 0; printf '0x0000\n' > "$T/lru/enabled"
chk "caps" "$(mf_caps | tr '\n' ' ')" "psi=1 mglru=1 mglru_enabled=0 lmk_use_psi= lmk_partial_stall_ms= low_ram= freezer_cfg=true "
echo; echo "HASIL: $PASS lolos, $FAIL gagal"; [ "$FAIL" -eq 0 ]
