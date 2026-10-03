#!/usr/bin/env bash
# Cek sintaks semua script shell modul + konsistensi versi. Dipakai CI dan bisa dijalankan lokal.
set -e
cd "$(dirname "$0")/.."
fail=0
for f in $(find module -name '*.sh' -not -path '*/fasrs/*' -not -path '*/uperf/*'); do
  sh -n "$f" 2>/dev/null || { echo "SYNTAX ERROR: $f"; fail=1; }
done
VER=$(tr -d '[:space:]' < version.txt)
MP=$(sed -n 's/^versionCode=//p' module/module.prop | head -n 1)
CV=$(sed -n 's/^ALPHA_COMPANION_VER=//p' module/common/companion_install.sh | head -n 1)
[ "$VER" = "$MP" ] || { echo "version.txt ($VER) != module.prop versionCode ($MP)"; fail=1; }
[ "$VER" = "$CV" ] || { echo "version.txt ($VER) != ALPHA_COMPANION_VER ($CV)"; fail=1; }
[ -f module/common/alphactl.sh ] || { echo "alphactl.sh hilang"; fail=1; }
[ -f module/common/autoctl.sh ] || { echo "autoctl.sh hilang"; fail=1; }
[ "$fail" = 0 ] && echo "check_module: OK (versionCode $VER)"
exit $fail
