#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

# shellcheck source=../lib/version.sh
source "$ROOT_DIR/lib/version.sh"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

bash "$ROOT_DIR/scripts/package-linux.sh" "$task_tmp/output" >/dev/null || fail 'construcción del paquete Linux'
archive=$(find "$task_tmp/output" -maxdepth 1 -type f -name '*.tar.gz' -print -quit)
checksum="${archive}.sha256"
[[ -n "$archive" && -f "$archive" ]] || fail 'no se creó el archivo comprimido'
[[ -f "$checksum" ]] || fail 'no se creó la suma SHA-256'
download_dir="$task_tmp/download"
mkdir -p "$download_dir"
cp -- "$archive" "$checksum" "$download_dir/" || fail 'descarga simulada'
# Trasladar, no validar junto al archivo original: una ruta absoluta en el
# manifiesto aparentaba funcionar en desarrollo y fallaba en otros equipos.
original_archive=$archive
archive="$download_dir/${archive##*/}" checksum="$download_dir/${checksum##*/}"
rm -- "$original_archive"
(cd "$download_dir" && sha256sum -c "${checksum##*/}") >/dev/null || fail 'la suma SHA-256 no funciona tras descargar'

tar_listing=$(tar -tzf "$archive") || fail 'no se pudo leer el paquete'
[[ "$tar_listing" == *'keila-radio'* ]] || fail 'falta el launcher en el paquete'
[[ "$tar_listing" == *'/lib/player.sh'* && "$tar_listing" == *'/lib/spectrum.sh'* ]] || fail 'faltan módulos del runtime'
[[ "$tar_listing" == *'/lib/data-safety.sh'* && "$tar_listing" == *'/TESTING.md'* ]] || fail 'falta protección de datos o guía de pruebas'
[[ "$tar_listing" == *"/docs/releases/$KEILA_VERSION.md"* ]] || fail 'faltan notas de la versión'
[[ "$tar_listing" != *'/.git/'* && "$tar_listing" != *'/grabaciones/'* ]] || fail 'el paquete contiene datos de desarrollo o grabaciones'

extract_dir="$task_tmp/extracted"
mkdir -p "$extract_dir"
tar -xzf "$archive" -C "$extract_dir" || fail 'extracción del paquete'
package_root=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)
[[ -n "$package_root" ]] || fail 'no se encontró la raíz extraída'
version_output=$(bash "$package_root/keila-radio" --version) || fail 'launcher extraído no arranca'
[[ "$version_output" == "Keila Radio Player $KEILA_VERSION" ]] || fail 'versión del launcher extraído incorrecta'
[[ ! -e "$package_root/grabaciones" ]] || fail 'las grabaciones entraron en el paquete'

printf 'ok   paquete Linux: runtime limpio, checksum portable, notas y launcher verificados\n'
