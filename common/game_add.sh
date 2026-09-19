#!/system/bin/sh
# Alpha Fusion - Satu pintu masuk "tambah/ubah game": mode menentukan engine
# secara otomatis. UI (APK) HANYA perlu kirim package + profile (+ fps
# opsional untuk mode performance). Tidak ada lagi field "engine" di UI.
#
# Mapping (jangan diubah tanpa alasan kuat - lihat prompt_engine_unify.md):
#   performance -> fas-rs (games.toml)      -> WAJIB ada default fps kalau user
#                                               tidak isi manual.
#   balanced    -> uperf (default, no-op)   -> pastikan package DIHAPUS dari
#                                               games.toml kalau sebelumnya ada
#                                               di sana (biar ga nyangkut fas-rs).
#   battery     -> uperf (default, no-op)   -> sama seperti balanced.

MODDIR="$(dirname "$(readlink -f "$0")")"
DEFAULT_FPS="30,60,90"

game_add() {
    _pkg="$1"
    _profile="$2"
    _fps="${3:-$DEFAULT_FPS}"

    # 1. Selalu tulis mapping profile (dipakai monitor.sh utk Alpha tuning
    #    generik: VM/IO/network/GPU cap per profil, TIDAK berubah).
    sh "$MODDIR/game_manager.sh" add "$_pkg" "$_profile" || return 1

    # 2. Derive engine dari profile - INI YANG BARU.
    case "$_profile" in
        performance)
            sh "$MODDIR/engine_manager.sh" add "$_pkg" "$_fps" || return 1
            ;;
        balanced|battery)
            # Pastikan tidak nyangkut di fas-rs dari assignment sebelumnya -
            # remove ini aman dipanggil walau package memang belum pernah
            # ada di games.toml (engine_manager.sh remove no-op kalau tidak
            # ketemu, lihat baris grep -v di dalamnya).
            sh "$MODDIR/engine_manager.sh" remove "$_pkg" >/dev/null 2>&1
            ;;
    esac
    echo "OK: $_pkg -> profile=$_profile engine=$(_resolve_engine_name "$_profile")"
}

_resolve_engine_name() {
    case "$1" in
        performance) echo "fas-rs" ;;
        *) echo "uperf" ;;
    esac
}

game_remove() {
    _pkg="$1"
    sh "$MODDIR/game_manager.sh" remove "$_pkg"
    sh "$MODDIR/engine_manager.sh" remove "$_pkg" >/dev/null 2>&1
}

case "$1" in
    add)    game_add "$2" "$3" "$4" ;;
    remove) game_remove "$2" ;;
    *) echo "Usage: game_add.sh [add <pkg> <profile> [fps_csv]|remove <pkg>]" ;;
esac
