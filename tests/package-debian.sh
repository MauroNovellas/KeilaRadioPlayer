#!/usr/bin/env bash

set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

bash "$ROOT_DIR/scripts/package-debian.sh" "$task_tmp/output" >/dev/null || fail 'construcción del paquete Debian'
archive="$task_tmp/output/keila-radio_2.1.1_all.deb"
[[ -f "$archive" ]] || fail 'no se creó el .deb'

listing=$(dpkg-deb -c "$archive") || fail 'no se pudo leer el .deb'
[[ "$listing" == *'/usr/bin/keila-radio'* ]] || fail 'falta el ejecutable'
[[ "$listing" == *'/usr/lib/keila-radio/lib/player.sh'* ]] || fail 'falta el runtime'
[[ "$listing" == *'/usr/share/doc/keila-radio/README.md'* ]] || fail 'falta la documentación'
[[ "$listing" == *'/usr/share/doc/keila-radio/LICENSE'* ]] || fail 'falta la licencia'
[[ "$listing" != *'/grabaciones/'* && "$listing" != *'/.git/'* ]] || fail 'entraron datos personales'

package_version=$(dpkg-deb -f "$archive" Version)
[[ "$package_version" == '2.1.1-1' ]] || fail 'versión Debian incorrecta'

printf 'ok   paquete Debian: .deb, rutas, dependencias y documentación verificados\n'
