SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

ui_print "================================================="
ui_print "  Alpha + Uperf Fusion (Safe Merge)"
ui_print "  Governor/Freq: 100% dipegang fas-rs (bukan Alpha/Uperf)"
ui_print "================================================="

# ---------------------------------------------------------
# 1. Guardrail arsitektur (dari Alpha v1) - wajib ARM64
# ---------------------------------------------------------
DEVICE_ARCH="$ARCH"
if [ -z "$DEVICE_ARCH" ]; then
    DEVICE_ARCH=$(uname -m 2>/dev/null)
fi

case "$DEVICE_ARCH" in
    arm64|aarch64)
        ui_print "- Arsitektur ARM64 terverifikasi ($DEVICE_ARCH)."
        ;;
    *)
        ui_print "***********************************************"
        ui_print "! Modul ini hanya mendukung perangkat ARM64!"
        ui_print "! Arsitektur terdeteksi: ${DEVICE_ARCH:-unknown}"
        ui_print "***********************************************"
        abort "Instalasi dibatalkan."
        ;;
esac

# ---------------------------------------------------------
# 2. Setup direktori kerja Alpha
# ---------------------------------------------------------
WORK_DIR="/data/adb/alpha"
ui_print "- Menyiapkan direktori kerja Alpha: $WORK_DIR"
mkdir -p "$WORK_DIR"
chmod 0755 "$WORK_DIR"
# M6: tulis penanda Alpha — uninstall.sh pakai ini untuk menentukan
# apakah config uperf/fas-rs milik Alpha boleh dihapus.
printf '%s\n' "1" > "$WORK_DIR/.alpha_installed" 2>/dev/null

# Bersihkan cache deteksi lama saat reinstall agar hardware terdeteksi ulang
rm -f "$WORK_DIR/detected.conf"
rm -f "$WORK_DIR/alpha.log"

# modul31: bersih state basi saat flash-timpa (tanpa uninstall dulu).
# rm -f tidak pernah gagal, jadi aman dijalankan ulang berapa kali pun.
# Yang DIHAPUS (transient/snapshot): boost_level, GAMEBOOST_LEVEL,
# .gb_active, .gb_cooldown_count, .gb_level_orig, .gb_pending, pids,
# native_boost.conf BASI (tanpa NATIVE_VERSION=30 -> backup ulang fresh
# saat boot, bukan restore nilai boost lama), log + cache monitor.
# Yang DIPERTAHANKAN (data user): game_profile_map.conf (daftar game),
# active_profile/current_state, SF_LATCH_UNSIGNALED, .disable_tweaks,
# .alpha/.companion/.asoulopt_installed.
rm -f "$WORK_DIR/boost_level" "$WORK_DIR/GAMEBOOST_LEVEL" \
    "$WORK_DIR/.gb_active" "$WORK_DIR/.gb_cooldown_count" \
    "$WORK_DIR/.gb_level_orig" "$WORK_DIR/.gb_pending" \
    "$WORK_DIR/monitor.pid" "$WORK_DIR/watchdog.pid" \
    "$WORK_DIR/apply.lock" "$WORK_DIR/.profile_transitions.log" \
    "$WORK_DIR/.daily_loadbalanced" "$WORK_DIR/.daily_loadhigh_count" \
    "$WORK_DIR/.foreground-events" "$WORK_DIR/.foreground_last_pkg" \
    "$WORK_DIR/.hud_foreground_pkg" 2>/dev/null
rm -f "$WORK_DIR"/.monitor-dumpsys.* 2>/dev/null
if [ -f "$WORK_DIR/native_boost.conf" ]; then
    if ! grep -q "^NATIVE_VERSION=30" "$WORK_DIR/native_boost.conf" 2>/dev/null; then
        rm -f "$WORK_DIR/native_boost.conf" 2>/dev/null
        ui_print "- Snapshot native basi dibuang, backup ulang fresh saat boot."
    fi
fi

# ---------------------------------------------------------
# 3. Pilih config Uperf sesuai chipset (subsistem thread/cgroup classifier saja)
# ---------------------------------------------------------
UPERF_USER_PATH="/sdcard/Android/yc/uperf"
UPERF_SUPPORTED=0

if [ -f "$MODPATH/uperf/script/libsysinfo.sh" ]; then
    . "$MODPATH/uperf/script/libsysinfo.sh"

    ui_print "- Mendeteksi chipset untuk profil Uperf..."
    ui_print "  ro.board.platform=$(getprop ro.board.platform)"
    ui_print "  ro.product.board=$(getprop ro.product.board)"

    UPERF_TARGET="$(getprop ro.board.platform)"
    UPERF_CFGNAME="$(get_config_name "$UPERF_TARGET")"
    if [ "$UPERF_CFGNAME" = "unsupported" ]; then
        UPERF_TARGET="$(getprop ro.product.board)"
        UPERF_CFGNAME="$(get_config_name "$UPERF_TARGET")"
    fi

    if [ "$UPERF_CFGNAME" != "unsupported" ] && [ -f "$MODPATH/uperf/config/$UPERF_CFGNAME.json" ]; then
        mkdir -p "$UPERF_USER_PATH"
        cp -f "$MODPATH/uperf/config/$UPERF_CFGNAME.json" "$UPERF_USER_PATH/uperf.json"
        # M1: Nonaktifkan modul cpu di salinan uperf.json — Alpha/fas-rs
        # memegang penuh kendali CPU governor/freq, supaya tidak rebutan.
        # Cek verifikasi: pastikan baris setelah "cpu": berisi "enable": false.
        _uperf_cpu_tmp="$UPERF_USER_PATH/.uperf.json.cpu_tmp"
        cp -f "$UPERF_USER_PATH/uperf.json" "$_uperf_cpu_tmp" 2>/dev/null
        if sed -i '/"cpu":/{n;s/"enable": true/"enable": false/}' "$UPERF_USER_PATH/uperf.json" 2>/dev/null \
           && grep -A1 '"cpu"' "$UPERF_USER_PATH/uperf.json" 2>/dev/null | grep -q '"enable": false'; then
            # M1: Validasi JSON setelah modifikasi — pastikan tidak corrupt
            _json_ok=0
            if command -v python3 >/dev/null 2>&1; then
                python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$UPERF_USER_PATH/uperf.json" 2>/dev/null && _json_ok=1
            elif command -v jq >/dev/null 2>&1; then
                jq empty "$UPERF_USER_PATH/uperf.json" 2>/dev/null && _json_ok=1
            else
                # Fallback: validasi struktur dasar (buka+tutup kurung)
                _opens=$(tr -cd '{' < "$UPERF_USER_PATH/uperf.json" 2>/dev/null | wc -c)
                _closes=$(tr -cd '}' < "$UPERF_USER_PATH/uperf.json" 2>/dev/null | wc -c)
                [ "$_opens" -gt 0 ] 2>/dev/null && [ "$_opens" = "$_closes" ] 2>/dev/null && _json_ok=1
            fi
            if [ "$_json_ok" = "1" ]; then
                ui_print "- Uperf cpu.enable dinonaktifkan (Alpha/fas-rs pegang CPU)."
            else
                cp -f "$_uperf_cpu_tmp" "$UPERF_USER_PATH/uperf.json" 2>/dev/null
                ui_print "! Peringatan: uperf.json corrupt setelah edit, file asli dipertahankan."
            fi
        else
            cp -f "$_uperf_cpu_tmp" "$UPERF_USER_PATH/uperf.json" 2>/dev/null
            ui_print "! Peringatan: gagal nonaktifkan cpu.enable, uperf.json asli dipertahankan."
        fi
        rm -f "$_uperf_cpu_tmp" 2>/dev/null
        [ ! -e "$UPERF_USER_PATH/perapp_powermode.txt" ] && cp -f "$MODPATH/uperf/config/perapp_powermode.txt" "$UPERF_USER_PATH/perapp_powermode.txt"
        # Injeksi idempoten rule "Alpha-FasrsManaged" (exclusion game fas-rs).
        # Struktur object PERSIS mengikuti rule sejenis yang sudah ada di
        # modules.sched.rules[] config ini, ditaruh TEPAT sebelum "Default
        # rule" (regex "." match-all) supaya package fas-rs cocok ke rule ini
        # dulu dan dapat treatment netral (ac=auto pc=auto = jangan sentuh).
        # common/sync_uperf_exclusion.sh mengandalkan baris "regex" yang
        # langsung berada setelah baris "name" rule ini - format di bawah
        # menjaga adjacency tersebut. Cek-duplikat dulu supaya aman
        # dijalankan ulang saat update modul.
        if grep -q '"name": "Alpha-FasrsManaged"' "$UPERF_USER_PATH/uperf.json" 2>/dev/null; then
            ui_print "- Rule Alpha-FasrsManaged sudah ada di uperf.json."
        elif ! grep -q '"name": "Default rule"' "$UPERF_USER_PATH/uperf.json" 2>/dev/null; then
            ui_print "! Marker Default rule tidak ditemukan, injeksi Alpha-FasrsManaged dilewati (sync exclusion nonaktif)."
        else
            ALPHA_RULE_TMP="$UPERF_USER_PATH/.uperf.json.alpha_tmp"
            rm -f "$ALPHA_RULE_TMP" 2>/dev/null
            ALPHA_RULE_PREV=""
            ALPHA_RULE_FIRST=1
            while IFS= read -r ALPHA_RULE_LINE || [ -n "$ALPHA_RULE_LINE" ]; do
                if [ "$ALPHA_RULE_FIRST" = "1" ]; then
                    ALPHA_RULE_PREV="$ALPHA_RULE_LINE"
                    ALPHA_RULE_FIRST=0
                    continue
                fi
                case "$ALPHA_RULE_LINE" in
                    *'"name": "Default rule"'*)
                        case "$ALPHA_RULE_PREV" in
                            *'{'*)
                                printf '%s\n' '        {' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '          "name": "Alpha-FasrsManaged",' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '          "regex": "ALPHA_NO_GAMES_YET_PLACEHOLDER",' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '          "pinned": true,' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '          "rules": [' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '            {' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '              "k": ".",' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '              "ac": "auto",' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '              "pc": "auto"' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '            }' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '          ]' >> "$ALPHA_RULE_TMP"
                                printf '%s\n' '        },' >> "$ALPHA_RULE_TMP"
                                ;;
                        esac
                        ;;
                esac
                printf '%s\n' "$ALPHA_RULE_PREV" >> "$ALPHA_RULE_TMP"
                ALPHA_RULE_PREV="$ALPHA_RULE_LINE"
            done < "$UPERF_USER_PATH/uperf.json"
            if [ "$ALPHA_RULE_FIRST" = "0" ]; then
                printf '%s\n' "$ALPHA_RULE_PREV" >> "$ALPHA_RULE_TMP"
            fi
            if grep -q '"name": "Alpha-FasrsManaged"' "$ALPHA_RULE_TMP" 2>/dev/null; then
                mv -f "$ALPHA_RULE_TMP" "$UPERF_USER_PATH/uperf.json"
                ui_print "- Rule Alpha-FasrsManaged disuntik ke uperf.json (sebelum Default rule)."
            else
                rm -f "$ALPHA_RULE_TMP" 2>/dev/null
                ui_print "! Injeksi Alpha-FasrsManaged gagal (format tak dikenal), sync exclusion nonaktif."
            fi
        fi
        UPERF_SUPPORTED=1
        ui_print "- Profil Uperf cocok: $UPERF_CFGNAME.json (thread/cgroup classifier akan aktif)"
    else
        ui_print "! Chipset [$UPERF_TARGET] belum ada profil Uperf."
        ui_print "! Backend Uperf (thread classifier) akan DINONAKTIFKAN, Alpha tetap jalan normal."
    fi
else
    ui_print "! libsysinfo.sh Uperf tidak ditemukan, backend Uperf dilewati."
fi

# Config chipset lain sudah tidak diperlukan setelah dipilih, hapus untuk hemat ruang
rm -rf "$MODPATH/uperf/config"

# ---------------------------------------------------------
# 4. Stage AsoulOpt (thread-affinity daemon, modul terpisah).
#    Instalasi aktual DITUNDA ke service.sh (boot pertama, one-shot):
#    customize.sh ini sendiri sedang berjalan sebagai proses instalasi,
#    jadi nested install modul lain di sini berisiko race dengan
#    installer root manager yang sedang aktif.
# ---------------------------------------------------------
ASOULOPT_STAGED="$MODPATH/uperf/asoulopt-staged.zip"
if [ "$UPERF_SUPPORTED" = "1" ] && [ -f "$MODPATH/uperf/modules/asoulopt.zip" ]; then
    if [ -f "$MODPATH/common/asoulopt_install.sh" ]; then
        . "$MODPATH/common/asoulopt_install.sh"
        asoulopt_msg() { ui_print "$1"; }
        asoulopt_detect_manager
        ASOULOPT_MANAGER_NOW="$ASOULOPT_MANAGER"
        ui_print "- Root manager terdeteksi: $ASOULOPT_MANAGER_NOW."
        ui_print "- AsoulOpt dijadwalkan dipasang otomatis saat boot pertama (service.sh, sekali saja)."
    else
        ui_print "! Helper asoulopt_install.sh tidak ditemukan, AsoulOpt dilewati."
    fi
    mv -f "$MODPATH/uperf/modules/asoulopt.zip" "$ASOULOPT_STAGED" 2>/dev/null
else
    ui_print "- Melewati AsoulOpt (chipset tidak didukung atau paket tidak ada)."
fi
rm -rf "$MODPATH/uperf/modules"

# ---------------------------------------------------------
# 5. Set permission
# ---------------------------------------------------------
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/common/detect.sh" 0 0 0755
set_perm "$MODPATH/common/engine.sh" 0 0 0755
set_perm "$MODPATH/common/game_manager.sh" 0 0 0755
set_perm "$MODPATH/common/monitor.sh" 0 0 0755
set_perm "$MODPATH/common/watchdog.sh" 0 0 0755
set_perm "$MODPATH/common/apply_now.sh" 0 0 0755
set_perm "$MODPATH/common/sync_uperf_exclusion.sh" 0 0 0755
set_perm "$MODPATH/common/engine_manager.sh" 0 0 0755
set_perm "$MODPATH/common/game_add.sh" 0 0 0755
set_perm "$MODPATH/common/render_manager.sh" 0 0 0755
# modul31: .bin hanya ada di zip tahap rilis (encode shc), tidak ada di
# zip git. Guard [ -f ] supaya tidak error "stat failed" saat file absen
# (biang error tiap flash, bersih maupun timpa). Tak ada yang mengeksekusi
# .bin (service.sh selalu pakai .sh), jadi skip = aman.
(
    for _alpha_bin in "$MODPATH/common/monitor.bin" "$MODPATH/common/watchdog.bin" \
        "$MODPATH/common/apply_now.bin" "$MODPATH/common/game_add.bin" \
        "$MODPATH/common/engine_manager.bin" "$MODPATH/common/game_manager.bin" \
        "$MODPATH/common/sync_uperf_exclusion.bin" "$MODPATH/bin/pgr-log.bin"; do
        if [ -f "$_alpha_bin" ]; then
            set_perm "$_alpha_bin" 0 0 0755
        fi
    done
)
set_perm "$MODPATH/common/asoulopt_install.sh" 0 0 0644
set_perm "$MODPATH/common/companion_install.sh" 0 0 0644
set_perm "$MODPATH/common/profiles.sh" 0 0 0644

if [ -d "$MODPATH/uperf/bin" ]; then
    set_perm_recursive "$MODPATH/uperf/bin" 0 0 0755 0755
fi
if [ -d "$MODPATH/uperf/script" ]; then
    set_perm_recursive "$MODPATH/uperf/script" 0 0 0755 0755
fi

# ---------------------------------------------------------
# 6. Setup fas-rs (frame-aware CPU scheduler). Ini pemegang tunggal
#    governor/scaling-freq di modul gabungan ini.
# ---------------------------------------------------------
FASRS_DIR="/sdcard/Android/fas-rs"
FASRS_CONF="$FASRS_DIR/games.toml"
FASRS_MERGE_FLAG="$FASRS_DIR/.need_merge"
FASRS_SUPPORTED=1

ui_print "- Memeriksa syarat fas-rs (ARM64, Android 12+, kernel 5.8+)..."

if [ "$API" -le 30 ] 2>/dev/null; then
    ui_print "! Android < 12 (API=$API), fas-rs TIDAK akan dijalankan."
    FASRS_SUPPORTED=0
fi

FASRS_KREL="$(uname -r)"
if echo "$FASRS_KREL" | awk -F. '{exit !( $1 < 5 || ($1 == 5 && $2 < 8) )}'; then
    ui_print "! Kernel $FASRS_KREL < 5.8, fas-rs butuh dukungan eBPF yang lebih baru. fas-rs TIDAK akan dijalankan."
    FASRS_SUPPORTED=0
fi

if [ "$FASRS_SUPPORTED" = "1" ] && [ -f "$MODPATH/fasrs/fas-rs" ]; then
    if [ -f "$FASRS_CONF" ]; then
        touch "$FASRS_MERGE_FLAG"
        ui_print "- games.toml lama ditemukan, akan di-merge otomatis saat boot pertama."
    else
        mkdir -p "$FASRS_DIR"
        cp -f "$MODPATH/fasrs/games.toml" "$FASRS_CONF"
    fi
    cp -f "$MODPATH/fasrs/README_CN.md" "$FASRS_DIR/doc_cn.md" 2>/dev/null
    cp -f "$MODPATH/fasrs/README_EN.md" "$FASRS_DIR/doc_en.md" 2>/dev/null
    set_perm_recursive "$MODPATH/fasrs" 0 0 0755 0644
    set_perm "$MODPATH/fasrs/fas-rs" 0 0 0755
    sh "$MODPATH/fasrs/init_vtools.sh" "$(realpath "$MODPATH/module.prop")"
    setprop fas-rs-installed true 2>/dev/null
    ui_print "- fas-rs siap. Konfigurasi ada di: $FASRS_DIR"
else
    ui_print "- Melewati setup fas-rs (syarat tidak terpenuhi atau binary tidak ada)."
    ui_print "! CATATAN: tanpa fas-rs, modul ini TIDAK melakukan kontrol governor/freq"
    ui_print "!          apa pun (fitur itu memang sengaja diserahkan ke fas-rs)."
fi

# ---------------------------------------------------------
# 7. Companion APK (Alpha Control, kontrol native utama).
#    Coba install langsung di sini HANYA kalau Android booted (flash via
#    manager app): pm install menyentuh PackageManagerService, BUKAN
#    subsistem modul, jadi tidak kena race nested-install seperti kasus
#    AsoulOpt dulu. Kalau flash via recovery (pm tidak ada / belum boot),
#    lewati diam-diam - service.sh akan coba sekali saat boot pertama.
#    Guard versi di companion_install.sh: tidak install ulang kalau sudah
#    current (preferensi/permission user aman), tidak pernah downgrade.
# ---------------------------------------------------------
if [ -f "$MODPATH/common/companion_install.sh" ] && [ -f "$MODPATH/companion/AlphaBubble.apk" ]; then
    set_perm "$MODPATH/companion/AlphaBubble.apk" 0 0 0644
    if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && command -v pm >/dev/null 2>&1; then
        . "$MODPATH/common/companion_install.sh"
        if alpha_companion_install_once "$MODPATH/companion/AlphaBubble.apk" "$WORK_DIR/.companion_installed"; then
            ui_print "- Companion app Alpha Control terpasang/up-to-date."
        else
            ui_print "- Companion app dijadwalkan dipasang saat boot pertama."
        fi
    else
        ui_print "- Companion app dijadwalkan dipasang saat boot pertama (recovery flash)."
    fi
fi

ui_print "- Instalasi Alpha + Uperf + fas-rs Fusion selesai. Reboot untuk mengaktifkan."
