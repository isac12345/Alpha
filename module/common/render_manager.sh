#!/system/bin/sh
MODDIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
RENDER_CONF="${ALPHA_RENDER_CONF:-/data/adb/alpha/render_backend.conf}"

render_api_level() {
    render_api=$(getprop ro.build.version.sdk 2>/dev/null)
    case "$render_api" in
        ''|*[!0-9]*) render_api=0 ;;
    esac
    printf '%s' "$render_api"
}

render_vulkan_exposed() {
    [ "$(getprop ro.hwui.use_vulkan 2>/dev/null)" = "true" ]
}

render_available() {
    render_out='["default","skiagl"'
    if [ "$(render_api_level)" -ge 31 ] 2>/dev/null && render_vulkan_exposed; then
        render_out="$render_out,\"skiavk\""
    fi
    render_out="$render_out]"
    printf '%s' "$render_out"
}

render_current() {
    render_cur=""
    [ -f "$RENDER_CONF" ] && render_cur=$(tr -d '[:space:]' < "$RENDER_CONF" 2>/dev/null)
    [ -z "$render_cur" ] && render_cur="default"
    printf '%s' "$render_cur"
}

render_get() {
    printf '{"current":"%s","available":%s,"api":%s}\n' "$(render_current)" "$(render_available)" "$(render_api_level)"
}

render_set() {
    render_want="$1"
    case "$render_want" in
        default|skiagl|skiavk) ;;
        *)
            echo "ERROR: invalid backend: $render_want (pilih: default|skiagl|skiavk)"
            return 1
            ;;
    esac
    if [ "$render_want" = "skiavk" ]; then
        if [ "$(render_api_level)" -lt 31 ] 2>/dev/null; then
            echo "ERROR: skiavk butuh API 31+"
            return 1
        fi
        render_vulkan_exposed || {
            echo "ERROR: device tidak expose Vulkan renderer"
            return 1
        }
    fi
    printf '%s\n' "$render_want" > "$RENDER_CONF" 2>/dev/null || {
        echo "ERROR: gagal menulis $RENDER_CONF"
        return 1
    }
    . "$MODDIR/common/engine.sh" 2>/dev/null || {
        echo "ERROR: gagal load engine.sh"
        return 1
    }
    if tune_render; then
        echo "OK: render backend -> $render_want (efek setelah restart aplikasi)"
        return 0
    fi
    echo "ERROR: tune_render gagal, cek alpha.log kategori RENDER"
    return 1
}

render_apply() {
    . "$MODDIR/common/engine.sh" 2>/dev/null || {
        echo "ERROR: gagal load engine.sh"
        return 1
    }
    tune_render
}

case "$1" in
    get) render_get ;;
    set) render_set "$2" ;;
    apply) render_apply ;;
    *) echo "Usage: render_manager.sh [get|set <default|skiagl|skiavk>|apply]" ;;
esac
