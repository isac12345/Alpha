#!/bin/sh
# Buat MANIFEST.sha256 untuk isi modul (dijalankan di folder modul SEBELUM di-zip).
#   sh tools/make_manifest.sh <folder_modul>
# customize.sh memverifikasinya saat flash. File yang dikecualikan: manifest itu sendiri, META-INF, tools, docs.
set -e
D="${1:?folder modul}"
cd "$D"
rm -f MANIFEST.sha256
find . -type f ! -path './META-INF/*' ! -path './tools/*' ! -path './docs/*' ! -name MANIFEST.sha256 \
    | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do
    printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"
done > MANIFEST.sha256
echo "manifest: $(wc -l < MANIFEST.sha256) file"
