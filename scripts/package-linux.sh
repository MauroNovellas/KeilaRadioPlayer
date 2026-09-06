#!/usr/bin/env bash

# Construye un paquete Linux portable con el runtime de Keila.
# El paquete no incluye .git, cachés, configuraciones ni grabaciones locales.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"

if [[ "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="$PWD/$OUTPUT_DIR"
fi

# shellcheck source=../lib/version.sh
source "$ROOT_DIR/lib/version.sh"

version="${KEILA_VERSION:-dev}"
[[ "$version" =~ ^[0-9A-Za-z._-]+$ ]] || version='dev'
package_name="keila-radio-${version}-linux"
archive="$OUTPUT_DIR/${package_name}.tar.gz"
staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT

mkdir -p "$OUTPUT_DIR" "$staging_dir/$package_name"
cp -- "$ROOT_DIR/keila-radio" "$staging_dir/$package_name/"
cp -- "$ROOT_DIR/README.md" "$ROOT_DIR/CHANGELOG.md" "$staging_dir/$package_name/"
cp -a -- "$ROOT_DIR/defaults" "$ROOT_DIR/lib" "$staging_dir/$package_name/"
chmod +x "$staging_dir/$package_name/keila-radio"

tar -C "$staging_dir" -czf "$archive" "$package_name"
sha256sum "$archive" > "${archive}.sha256"

printf 'Paquete Linux: %s\n' "$archive"
printf 'SHA-256: %s\n' "${archive}.sha256"
