#!/system/bin/sh
# Alpha + Uperf + fas-rs Fusion
# Sinkronkan [game_list] di fas-rs games.toml -> exclusion rule "Alpha-FasrsManaged"
# di uperf.json, supaya package yang sudah didaftarkan ke fas-rs otomatis TIDAK
# lagi disentuh cpuset-nya oleh uperf (menghindari rebutan thread classification).
#
# Aturan pilih-engine: cukup edit [game_list] di fas-rs/games.toml.
#   - Package ADA di [game_list]      -> dipegang fas-rs, uperf otomatis skip.
#   - Package TIDAK ADA di [game_list] -> tetap dipegang uperf seperti biasa.
# Tidak perlu file konfigurasi terpisah; games.toml adalah satu-satunya sumber.
#
# Dipanggil dengan 2 argumen: $1 = path games.toml, $2 = path uperf.json (live)

FASRS_TOML="$1"
UPERF_JSON="$2"
PLACEHOLDER="ALPHA_NO_GAMES_YET_PLACEHOLDER"

[ -f "$FASRS_TOML" ] || exit 0
[ -f "$UPERF_JSON" ] || exit 0

# Ambil baris di dalam section [game_list] sampai section berikutnya (atau EOF),
# lalu ambil nama package (teks di antara tanda kutip pertama tiap baris).
# Hanya pakai sed (tanpa awk/jq) supaya aman di busybox minimal.
pkg_list=$(sed -n '/^\[game_list\]/,/^\[/p' "$FASRS_TOML" | sed -n 's/^"\([^"]*\)".*/\1/p')

if [ -z "$pkg_list" ]; then
    regex_val="$PLACEHOLDER"
else
    regex_val=""
    for pkg in $pkg_list; do
        # escape titik supaya jadi literal match, bukan wildcard regex
        esc_pkg=$(printf '%s' "$pkg" | sed 's/[.]/\\./g')
        if [ -z "$regex_val" ]; then
            regex_val="$esc_pkg"
        else
            regex_val="$regex_val|$esc_pkg"
        fi
    done
fi

# Timpa nilai "regex" milik rule "Alpha-FasrsManaged" saja (idempotent,
# aman dijalankan berkali-kali tiap boot walau games.toml berubah-ubah).
sed -i '/"name": "Alpha-FasrsManaged"/{n;s#"regex": *".*"#"regex": "'"$regex_val"'"#
}' "$UPERF_JSON"
