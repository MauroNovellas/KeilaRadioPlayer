#!/usr/bin/env bash

# Construye un .deb local sin necesitar debhelper. El contenido y las rutas
# coinciden con debian/rules para que la prueba sea útil antes del build oficial.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
[[ "$OUTPUT_DIR" == /* ]] || OUTPUT_DIR="$PWD/$OUTPUT_DIR"
source "$ROOT_DIR/lib/version.sh"

package_version="${KEILA_VERSION:-0.0.0}"
package_root="$OUTPUT_DIR/keila-radio_${package_version}_all"
archive="$OUTPUT_DIR/keila-radio_${package_version}_all.deb"
rm -rf -- "$package_root"
mkdir -p "$package_root/DEBIAN" "$package_root/usr/bin" \
    "$package_root/usr/lib/keila-radio" "$package_root/usr/share/doc/keila-radio"

install -m 0755 "$ROOT_DIR/keila-radio" "$package_root/usr/bin/keila-radio"
cp -a "$ROOT_DIR/lib" "$ROOT_DIR/defaults" "$package_root/usr/lib/keila-radio/"
install -m 0644 "$ROOT_DIR/README.md" "$ROOT_DIR/CHANGELOG.md" "$ROOT_DIR/PERFORMANCE.md" "$ROOT_DIR/LICENSE" \
    "$package_root/usr/share/doc/keila-radio/"

cat > "$package_root/DEBIAN/control" <<EOF
Package: keila-radio
Version: $package_version-1
Section: sound
Priority: optional
Architecture: all
Maintainer: Mauro Novellas <mauro@novellas.es>
Depends: bash, coreutils, curl, fzf, jq, mpv, ncurses-bin, socat
Description: reproductor de radio por Internet para terminal
 Keila Radio Player es un reproductor de emisoras de radio para terminales Linux.
EOF
mkdir -p "$OUTPUT_DIR"
dpkg-deb --build --root-owner-group "$package_root" "$archive" >/dev/null
rm -rf -- "$package_root"
printf 'Paquete Debian: %s\n' "$archive"
