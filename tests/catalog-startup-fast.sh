#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
trap 'catalog_stop; rm -rf "$task_tmp"' EXIT

export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'catalog_stop; rm -rf "$task_tmp"' EXIT
config_load "$task_tmp/recordings" || fail config

cat > "$KEILA_STATIONS_JSON" <<'JSON'
[{"name":"Rock FM","url_resolved":"https://radio.invalid/rock","country":"Spain","countrycode":"ES","state":"Madrid","tags":"rock","codec":"AAC","bitrate":128}]
JSON

catalog_start || fail start
[[ -n "$CATALOG_PID" && "$CATALOG_STATUS" == 'Preparando índice local…' ]] || fail 'arranque no preparó índice en segundo plano'

for ((i = 0; i < 100; i++)); do
    catalog_poll && break
    sleep .01
done

[[ -z "$CATALOG_PID" && -s "$KEILA_STATIONS_TSV" ]] || fail 'índice no quedó listo'
[[ ${#SEARCH_MATCHES[@]} == 1 && "$SEARCH_ACTIVE" == 0 ]] || fail 'índice listo no precargó búsqueda sin foco'

printf 'ok   catálogo fresco no bloquea el primer pintado\n'
