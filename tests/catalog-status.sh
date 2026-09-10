#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
config_load "$task_tmp/recordings" || fail config

cat > "$KEILA_STATIONS_JSON" <<'JSON'
[
  {"name":"Radio Test","url_resolved":"https://radio.invalid/test","country":"Spain","countrycode":"ES","state":"Madrid","tags":"test","codec":"MP3","bitrate":128},
  {"name":"Jazz Test","url_resolved":"https://radio.invalid/jazz","country":"France","countrycode":"FR","state":"Paris","tags":"jazz","codec":"AAC","bitrate":96}
]
JSON
stations_rebuild_tsv || fail catalogo

status_output=$(stations_catalog_status)

[[ "$status_output" == *'Catálogo Radio Browser'* ]] || fail 'falta título'
[[ "$status_output" == *'Estado: fresco'* ]] || fail 'falta estado fresco'
[[ "$status_output" == *'Emisoras indexadas: 2'* ]] || fail 'falta recuento'
[[ "$status_output" == *'Última actualización local:'* ]] || fail 'falta última actualización'
[[ "$status_output" == *'Próxima actualización automática:'* ]] || fail 'falta próxima actualización'
[[ "$status_output" == *'Filtro rápido de país: ES'* ]] || fail 'falta filtro país'
[[ "$status_output" == *'JSON: sí'* ]] || fail 'falta estado JSON'
[[ "$status_output" == *'Índice TUI: sí'* ]] || fail 'falta estado TSV'
[[ "$status_output" == *'Límite configurado:'* ]] || fail 'falta configuración'

mkdir -p "$KEILA_FAVORITES_FILE.lock"
launcher_output=$(main --catalog-status) || fail 'launcher --catalog-status no debe depender del lock de favoritos'
[[ "$launcher_output" == *'Estado: fresco'* ]] || fail 'launcher no informa estado del catálogo'

printf 'ok   catálogo: estado humano, recuento, edad, rutas y configuración\n'
