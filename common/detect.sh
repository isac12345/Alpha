#!/system/bin/sh
# Alpha v1 - Hardware & Topology Detection Engine
# Hasil deteksi dicache ke /data/adb/alpha/detected.conf (idempotent)
# Pola: DETECT SEKALI DI AWAL -> SIMPAN KE CACHE -> tweak baca cache saja.
# Naikkan DETECT_VERSION setiap logic deteksi berubah supaya cache lama
# otomatis di-refresh (tanpa detect ulang tiap boot).

DETECT_VERSION=2

CONF_DIR="${ALPHA_CONF_DIR:-/data/adb/alpha}"
CACHE_FILE="$CONF_DIR/detected.conf"

SYSFS_CPU_PREFIX="${SYSFS_CPU_PREFIX:-/sys/devices/system/cpu}"
SYSFS_BLOCK_PREFIX="${SYSFS_BLOCK_PREFIX:-/sys/block}"
SYSFS_GPU_PREFIX="${SYSFS_GPU_PREFIX:-/sys}"
SYSFS_THERMAL_PREFIX="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"

detect_soc() {
    local codename=""
    
    # 1. Prioritas utama: Device Tree
    if [ -f /proc/device-tree/model ]; then
        codename=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
    fi
    if [ -z "$codename" ] && [ -f /proc/device-tree/compatible ]; then
        codename=$(tr -d '\0' < /proc/device-tree/compatible 2>/dev/null | cut -d ',' -f1)
    fi
    
    # 2. Fallback: Android system properties
    if [ -z "$codename" ]; then
        codename=$(getprop ro.soc.model 2>/dev/null)
    fi
    if [ -z "$codename" ]; then
        codename=$(getprop ro.soc.manufacturer 2>/dev/null)
    fi
    if [ -z "$codename" ]; then
        codename=$(getprop ro.mediatek.platform 2>/dev/null)
    fi
    if [ -z "$codename" ]; then
        codename=$(getprop ro.board.platform 2>/dev/null)
    fi
    if [ -z "$codename" ]; then
        codename=$(getprop ro.hardware 2>/dev/null)
    fi
    
    # 3. Fallback: /proc/cpuinfo
    if [ -z "$codename" ] && [ -f /proc/cpuinfo ]; then
        codename=$(grep -m1 -E 'Hardware|Processor' /proc/cpuinfo 2>/dev/null | cut -d ':' -f2 | sed 's/^[ \t]*//')
    fi
    
    local clean_name
    clean_name=$(printf '%s' "${codename:-unknown}" | tr '[:upper:]' '[:lower:]')
    
    # Klasifikasi ke 5 vendor besar atau fallback unknown
    case "$clean_name" in
        *qualcomm*|*qcom*|*sm[0-9]*|*sdm*|*msm*|*snapdragon*)
            echo "qcom"
            ;;
        *mediatek*|*mt[0-9]*|*helio*|*dimensity*)
            echo "mtk"
            ;;
        *samsung*|*exynos*|*erd*|*s5e*|*universal*)
            echo "exynos"
            ;;
        *unisoc*|*ums*|*sp[0-9]*|*spreadtrum*)
            echo "unisoc"
            ;;
        *google*|*tensor*|*gs[0-9]*)
            echo "tensor"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

detect_clusters() {
    local policies=""
    for p in "$SYSFS_CPU_PREFIX"/cpufreq/policy*; do
        if [ -d "$p" ]; then
            local pol_name
            pol_name=$(basename "$p")
            policies="${policies}${pol_name} "
        fi
    done
    printf '%s' "$policies" | sed 's/[ \t]*$//'
}

detect_storage() {
    local devices=""
    for dev in "$SYSFS_BLOCK_PREFIX"/mmcblk* "$SYSFS_BLOCK_PREFIX"/sd* "$SYSFS_BLOCK_PREFIX"/nvme* "$SYSFS_BLOCK_PREFIX"/ufs*; do
        if [ -d "$dev/queue" ]; then
            local dev_name
            dev_name=$(basename "$dev")
            # Filter hanya block device utama (bukan partisi misal mmcblk0p1)
            case "$dev_name" in
                *p[0-9]*|*[0-9]rpmb|*[0-9]boot*)
                    continue
                    ;;
                *)
                    devices="${devices}${dev_name} "
                    ;;
            esac
        fi
    done
    printf '%s' "$devices" | sed 's/[ \t]*$//'
}

# Sapu ISI file compatible semua node devfreq, cocokkan pola (basic regex,
# case-insensitive). Return 0 kalau ada SATU node yang match. Glob nama
# folder TIDAK dipakai di sini sama sekali.
devfreq_compat_match() {
    local match_pat="$1"
    local match_node match_file
    for match_node in "$SYSFS_GPU_PREFIX"/class/devfreq/*; do
        [ -d "$match_node" ] || continue
        match_file="$match_node/device/of_node/compatible"
        [ -r "$match_file" ] || match_file="$match_node/of_node/compatible"
        [ -r "$match_file" ] || continue
        if tr '\0' '\n' < "$match_file" 2>/dev/null | grep -qi "$match_pat"; then
            return 0
        fi
    done
    return 1
}

detect_gpu_vendor() {
    if [ -d "$SYSFS_GPU_PREFIX/class/kgsl/kgsl-3d0" ]; then
        echo "ADRENO"
        return 0
    fi
    if [ -d "$SYSFS_GPU_PREFIX/class/misc/mali0" ]; then
        echo "MALI"
        return 0
    fi
    # Content-first: cocokkan ISI file compatible (bukan nama folder) di
    # semua node devfreq. Ini yang menangkap penamaan non-standar seperti
    # Unisoc (compatible "sprd,mali-natt" di folder "23100000.gpu").
    if devfreq_compat_match 'mali'; then
        echo "MALI"
        return 0
    fi
    for mali_path in "$SYSFS_GPU_PREFIX"/devices/platform/*.mali* "$SYSFS_GPU_PREFIX"/devices/*/*.mali*; do
        if [ -d "$mali_path" ]; then
            echo "MALI"
            return 0
        fi
    done
    for mali_devfreq in "$SYSFS_GPU_PREFIX"/class/devfreq/*mali*; do
        if [ -d "$mali_devfreq" ]; then
            echo "MALI"
            return 0
        fi
    done
    if [ -d "$SYSFS_GPU_PREFIX/module/pvrsrvkm" ] || [ -d "$SYSFS_GPU_PREFIX/kernel/debug/pvr" ]; then
        echo "POWERVR"
        return 0
    fi
    # PowerVR via isi compatible (fallback kalau path kanonis tidak ada).
    if devfreq_compat_match 'pvr\|powervr\|rogue'; then
        echo "POWERVR"
        return 0
    fi
    # Xclipse (Exynos RDNA: 1480/1580/2200/2400) - LAST resort sebelum
    # UNKNOWN. Syarat ganda supaya tidak misdetect:
    #  1. Chip WAJIB ada di allowlist Xclipse-only (bukan "exynos" umum -
    #     Exynos Mali seperti 2100/1380/1330/1280 TIDAK masuk list).
    #  2. Semua penanda kgsl/mali/pvr di atas sudah lewat (= tidak ada),
    #     DITAMBAH bukti positif: node devfreq gpu generik yang namanya
    #     TIDAK mengandung "mali" (node *mali* sudah dicek di atas dan
    #     selalu menang duluan). Tanpa bukti positif -> UNKNOWN (aman,
    #     sama seperti perilaku lama).
    # Batasan jujur: Xclipse yang drivernya expose penamaan mali
    # (mali0/devfreq *mali*) akan terdeteksi MALI - konservatif dan aman
    # (dapat ceiling path Mali), bukan Xclipse.
    if gpu_is_xclipse_chip && gpu_has_generic_devfreq_node; then
        echo "XCLIPSE"
        return 0
    fi
    echo "UNKNOWN"
    return 0
}

# Allowlist chip Xclipse-only (Exynos 1480=Xclipse 530, 1580=540,
# 2200=920, 2400=940). S5E IDs: s5e8535/1480, s5e8855/1580,
# s5e9925/2200, s5e9945/2400. Sengaja TIDAK pakai pola umum seperti
# *exynos*/*s5e* supaya Exynos Mali tidak ikut match.
gpu_is_xclipse_chip() {
    local chip_info=""
    local chip_prop
    for chip_prop in ro.board.platform ro.soc.model ro.hardware ro.chipname; do
        chip_info="$chip_info $(getprop "$chip_prop" 2>/dev/null)"
    done
    chip_info=$(printf '%s' "$chip_info" | tr '[:upper:]' '[:lower:]')
    case "$chip_info" in
        *exynos1480*|*exynos1580*|*exynos2200*|*exynos2400*|*s5e8535*|*s5e8855*|*s5e9925*|*s5e9945*)
            return 0
            ;;
    esac
    return 1
}

# Bukti positif node GPU generik: devfreq *gpu*/*g3d* yang BUKAN mali.
gpu_has_generic_devfreq_node() {
    local gpu_node
    for gpu_node in "$SYSFS_GPU_PREFIX"/class/devfreq/*gpu* "$SYSFS_GPU_PREFIX"/class/devfreq/*g3d*; do
        case "$gpu_node" in
            *mali*) continue ;;
        esac
        if [ -d "$gpu_node" ]; then
            return 0
        fi
    done
    return 1
}

resolve_gpu_devfreq_path() {
    local node candidate compat_file compat resolved
    case "$GPU_VENDOR" in
        MALI)
            for node in "$SYSFS_GPU_PREFIX"/class/devfreq/*; do
                [ -d "$node" ] || continue
                compat_file="$node/device/of_node/compatible"
                [ -r "$compat_file" ] || compat_file="$node/of_node/compatible"
                [ -r "$compat_file" ] || continue
                if tr '\0' '\n' < "$compat_file" 2>/dev/null | grep -qi 'mali'; then
                    resolved=$(readlink -f "$node" 2>/dev/null)
                    [ -d "$resolved" ] && { printf '%s' "$resolved"; return 0; }
                fi
            done
            for candidate in "$SYSFS_GPU_PREFIX"/class/devfreq/*mali*; do
                [ -d "$candidate" ] || continue
                resolved=$(readlink -f "$candidate" 2>/dev/null)
                [ -d "$resolved" ] && { printf '%s' "$resolved"; return 0; }
            done
            ;;
        XCLIPSE)
            for node in "$SYSFS_GPU_PREFIX"/class/devfreq/*; do
                [ -d "$node" ] || continue
                compat_file="$node/device/of_node/compatible"
                [ -r "$compat_file" ] || compat_file="$node/of_node/compatible"
                [ -r "$compat_file" ] || continue
                compat=$(tr '\0' '\n' < "$compat_file" 2>/dev/null | tr '[:upper:]' '[:lower:]')
                case "$compat" in *mali*) continue ;; esac
                case "$compat" in
                    *gpu*|*g3d*)
                        resolved=$(readlink -f "$node" 2>/dev/null)
                        [ -d "$resolved" ] && { printf '%s' "$resolved"; return 0; }
                        ;;
                esac
            done
            ;;
        ADRENO)
            [ -d "$SYSFS_GPU_PREFIX/class/kgsl/kgsl-3d0" ] && printf '%s' "$SYSFS_GPU_PREFIX/class/kgsl/kgsl-3d0"
            ;;
    esac
}

# Deteksi zona thermal yang valid via ISI file (type + temp numerik),
# bukan via nama folder. Prioritas: gpu > soc > tsens > cpu.
# Mengisi global: THERMAL_SUPPORTED (1/0), THERMAL_PATH (file temp),
# THERMAL_TYPE (isi type asli). Eksplisit 0 kalau tidak ada yang valid
# supaya consumer bisa skip jelas tanpa scan ulang.
detect_thermal() {
    THERMAL_SUPPORTED=0
    THERMAL_PATH=""
    THERMAL_TYPE=""
    local prio zone type temp
    for prio in gpu soc tsens cpu; do
        for zone in "$SYSFS_THERMAL_PREFIX"/thermal_zone*; do
            [ -r "$zone/type" ] && [ -r "$zone/temp" ] || continue
            type=$(tr '[:upper:]' '[:lower:]' < "$zone/type" 2>/dev/null)
            case "$type" in *"$prio"*) ;; *) continue ;; esac
            temp=$(tr -d '[:space:]' < "$zone/temp" 2>/dev/null)
            case "$temp" in ''|*[!0-9-]*) continue ;; esac
            THERMAL_SUPPORTED=1
            THERMAL_PATH="$zone/temp"
            THERMAL_TYPE=$(cat "$zone/type" 2>/dev/null | tr -d '\0')
            return 0
        done
    done
    return 0
}

# --- Main Flow ---
# Cache dipakai ulang HANYA kalau: sudah ada + versi cache >= versi
# script ini + tidak ada ALPHA_FORCE_DETECT=1. Selain itu (first-run,
# cache versi lama, atau tombol DETEKSI ULANG di app) → scan ulang.
if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ] && [ "${ALPHA_FORCE_DETECT:-0}" != "1" ]; then
    ALPHA_SCRIPT_DETECT_VERSION="$DETECT_VERSION"
    DETECT_VERSION=""
    . "$CACHE_FILE"
    # Cache lama (v1) tidak punya field DETECT_VERSION -> anggap 0,
    # jadi otomatis di-refresh ke versi script yang sekarang.
    case "${DETECT_VERSION:-0}" in ''|*[!0-9]*) DETECT_VERSION=0 ;; esac
    if [ "$DETECT_VERSION" -ge "$ALPHA_SCRIPT_DETECT_VERSION" ] 2>/dev/null; then
        return 0 2>/dev/null || exit 0
    fi
    DETECT_VERSION="$ALPHA_SCRIPT_DETECT_VERSION"
fi

mkdir -p "$CONF_DIR"

SOC_VENDOR=$(detect_soc)
CPU_POLICIES=$(detect_clusters)
STORAGE_DEVICES=$(detect_storage)
GPU_VENDOR=$(detect_gpu_vendor)
GPU_DEVFREQ_PATH=$(resolve_gpu_devfreq_path)
detect_thermal
DETECT_DATE=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date 2>/dev/null)

# Tulis ke cache file. Nilai UNKNOWN/kosong/0 di bawah EKSPLISIT
# (bukan silent-fail): consumer wajib skip fitur terkait TANPA scan ulang.
cat <<EOF > "$CACHE_FILE"
# Alpha v1 Auto-detected Hardware Profile
# DETECT_VERSION=$DETECT_VERSION DETECT_DATE="$DETECT_DATE"
DETECT_VERSION="$DETECT_VERSION"
DETECT_DATE="$DETECT_DATE"
SOC_VENDOR="$SOC_VENDOR"
CPU_POLICIES="$CPU_POLICIES"
STORAGE_DEVICES="$STORAGE_DEVICES"
GPU_VENDOR="$GPU_VENDOR"
GPU_DEVFREQ_PATH="$GPU_DEVFREQ_PATH"
THERMAL_SUPPORTED="$THERMAL_SUPPORTED"
THERMAL_PATH="$THERMAL_PATH"
THERMAL_TYPE="$THERMAL_TYPE"
# Arti nilai eksplisit:
# GPU_VENDOR=UNKNOWN -> tidak ada GPU yang dikenali; lewati tuning GPU.
# GPU_DEVFREQ_PATH kosong -> node devfreq GPU tidak ketemu; lewati baca/tulis devfreq GPU.
# THERMAL_SUPPORTED=0 -> tidak ada thermal zone valid; lewati cek suhu.
# Node GPU yang dicek saat GPU_VENDOR=UNKNOWN:
# $SYSFS_GPU_PREFIX/class/kgsl/kgsl-3d0 (Adreno),
# compatible 'mali' di class/devfreq/*/device/of_node (Mali, isi-file dulu),
# $SYSFS_GPU_PREFIX/class/misc/mali0 + devices/*mali* + class/devfreq/*mali* (Mali, fallback nama),
# $SYSFS_GPU_PREFIX/module/pvrsrvkm + kernel/debug/pvr + compatible 'pvr|powervr|rogue' (PowerVR),
# Xclipse = allowlist chip 1480/1580/2200/2400 + class/devfreq/*gpu*|*g3d* non-mali
EOF

chmod 0644 "$CACHE_FILE"
