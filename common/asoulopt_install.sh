#!/system/bin/sh
asoulopt_detect_manager() {
    ASOULOPT_MANAGER="UNKNOWN"
    ASOULOPT_MAGISK_BIN=""
    ASOULOPT_KSUD_BIN=""
    if command -v magisk >/dev/null 2>&1; then
        ASOULOPT_MAGISK_BIN="$(command -v magisk)"
        ASOULOPT_MANAGER="MAGISK"
        return 0
    fi
    if command -v ksud >/dev/null 2>&1; then
        ASOULOPT_KSUD_BIN="$(command -v ksud)"
        ASOULOPT_MANAGER="KERNELSU"
        return 0
    fi
    if [ -x "/data/adb/ksud" ]; then
        ASOULOPT_KSUD_BIN="/data/adb/ksud"
        ASOULOPT_MANAGER="KERNELSU"
        return 0
    fi
    return 1
}

asoulopt_install_once() {
    asoulopt_zip="$1"
    asoulopt_flag="$2"
    if [ -f "$asoulopt_flag" ]; then
        asoulopt_msg "AsoulOpt: sudah diproses sebelumnya ($(cat "$asoulopt_flag" 2>/dev/null)), dilewati."
        return 0
    fi
    if [ ! -f "$asoulopt_zip" ]; then
        asoulopt_msg "AsoulOpt: paket $asoulopt_zip tidak ada, dilewati."
        printf 'skip:missing-zip\n' > "$asoulopt_flag" 2>/dev/null
        return 0
    fi
    asoulopt_detect_manager
    asoulopt_manager="$ASOULOPT_MANAGER"
    asoulopt_msg "AsoulOpt: root manager terdeteksi: $asoulopt_manager"
    case "$asoulopt_manager" in
        MAGISK)
            killall -9 AsoulOpt 2>/dev/null
            rm -rf /data/adb/modules*/asoul_affinity_opt 2>/dev/null
            if "$ASOULOPT_MAGISK_BIN" --install-module "$asoulopt_zip"; then
                asoulopt_msg "AsoulOpt: terpasang via magisk --install-module. Aktif setelah reboot."
                printf 'ok:MAGISK\n' > "$asoulopt_flag" 2>/dev/null
                rm -f "$asoulopt_zip" 2>/dev/null
                return 0
            fi
            asoulopt_msg "AsoulOpt: GAGAL dipasang via magisk --install-module (bukan masalah chipset). Akan dicoba lagi saat boot berikutnya."
            return 1
            ;;
        KERNELSU)
            killall -9 AsoulOpt 2>/dev/null
            rm -rf /data/adb/modules*/asoul_affinity_opt 2>/dev/null
            if "$ASOULOPT_KSUD_BIN" module install "$asoulopt_zip"; then
                asoulopt_msg "AsoulOpt: terpasang via ksud module install. Aktif setelah reboot."
                printf 'ok:KERNELSU\n' > "$asoulopt_flag" 2>/dev/null
                rm -f "$asoulopt_zip" 2>/dev/null
                return 0
            fi
            asoulopt_msg "AsoulOpt: GAGAL dipasang via ksud module install (bukan masalah chipset). Akan dicoba lagi saat boot berikutnya."
            return 1
            ;;
        *)
            asoulopt_msg "AsoulOpt: DILEWATI - root manager tidak dikenali (binary magisk maupun ksud tidak ditemukan). BUKAN masalah chipset. Untuk mencoba lagi, hapus $asoulopt_flag."
            printf 'skip:unknown-manager\n' > "$asoulopt_flag" 2>/dev/null
            return 0
            ;;
    esac
}
