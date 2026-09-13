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
[{"name":"Radio Test","url_resolved":"https://radio.invalid/test","country":"Spain","countrycode":"ES","state":"Madrid","tags":"test","codec":"MP3","bitrate":128}]
JSON
stations_rebuild_tsv || fail catalogo
catalog_start || fail prime

PLAYER_PID=''
PLAYER_NAME='Radio Test'
PLAYER_VOLUME=64
PLAYER_STREAM_TITLE='Canción de prueba'
PLAYER_STREAM_TITLE_UPDATED_AT=$((${EPOCHSECONDS:-$(date +%s)} - 7))
PENDING_FILES=("$task_tmp/recordings/a.ts")
FAVORITE_NAMES=('Radio Test')
FAVORITE_URLS=('https://radio.invalid/test')
FAVORITE_LABELS['https://radio.invalid/test']='Comentario'

status_build_rows
status_text=$(printf '%s\n' "${STATUS_ROWS[@]}")

[[ "$status_text" == *'Versión|Keila'* ]] || fail 'falta versión'
[[ "$status_text" == *'Catálogo|fresco'* ]] || fail 'falta estado de catálogo'
[[ "$status_text" == *'Emisoras indexadas|1'* ]] || fail 'falta recuento de emisoras'
[[ "$status_text" == *'Resultados precargados|1'* ]] || fail 'falta búsqueda precargada'
[[ "$status_text" == *'Reproductor|detenido'* ]] || fail 'falta reproductor'
[[ "$status_text" == *'Volumen|64%'* ]] || fail 'falta volumen'
[[ "$status_text" == *'Pendientes|1'* ]] || fail 'falta pendientes'
[[ "$status_text" == *"Config|$KEILA_CONFIG_FILE"* ]] || fail 'falta ruta config'

printf 'ok   diagnóstico TUI: estado, catálogo, rutas y contadores\n'
