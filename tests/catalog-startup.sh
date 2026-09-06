#!/usr/bin/env bash
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'catalog_stop; rm -rf "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
config_load "$task_tmp/recordings" || fail config
cat > "$task_tmp/fixture" <<'JSON'
{"countries":[{"name":"España","ambits":[{"name":"Nacional","channels":[{"name":"Rock FM","options":[{"format":"AAC","url":"https://radio.invalid/rock"}]}]}]}]}
JSON
cp "$task_tmp/fixture" "$KEILA_STATIONS_JSON"
catalog_start || fail cached
[[ -z "$CATALOG_PID" && ${#SEARCH_MATCHES[@]} == 1 && "$SEARCH_ACTIVE" == 0 ]] || fail 'carga inicial caché'

# Descarga controlada, sin acceder a emisoras reales. Un archivo libera al proceso.
mkdir "$task_tmp/bin"
cat > "$task_tmp/bin/curl" <<'PY'
#!/usr/bin/env python3
import os, sys, time, pathlib
root = pathlib.Path(os.environ['CATALOG_TEST_DIR'])
(root / 'pid').write_text(str(os.getpid()))
while not (root / 'release').exists():
    time.sleep(.01)
if (root / 'fail').exists():
    sys.exit(1)
pathlib.Path(sys.argv[sys.argv.index('--output') + 1]).write_bytes((root / 'fixture').read_bytes())
PY
chmod +x "$task_tmp/bin/curl"
export PATH="$task_tmp/bin:$PATH" CATALOG_TEST_DIR="$task_tmp"
wait_marker() {
    local n
    for ((n=0; n<200; n++)); do [[ -f "$task_tmp/pid" ]] && return 0; sleep .01; done
    return 1
}
finish_download() {
    local n
    for ((n=0; n<200; n++)); do catalog_poll && return 0; sleep .01; done
    return 1
}
catalog_start force || fail start
wait_marker || fail worker
[[ -n "$CATALOG_PID" && ! -f "$CATALOG_JOB_DIR/done" && ${#SEARCH_MATCHES[@]} == 1 ]] || fail 'descarga no bloqueante'
SEARCH_QUERY=rock SEARCH_ACTIVE=1
touch "$task_tmp/release"
finish_download || fail finish
[[ "$SEARCH_QUERY" == rock && "$SEARCH_ACTIVE" == 1 && ${#SEARCH_MATCHES[@]} == 1 ]] || fail 'actualización conserva búsqueda'

touch "$task_tmp/fail"
catalog_start force || fail start
finish_download || fail 'fallo descarga'
[[ ${#SEARCH_MATCHES[@]} == 1 && -s "$KEILA_STATIONS_JSON" ]] || fail 'fallo perdió caché'
rm "$KEILA_STATIONS_JSON"
SEARCH_NAMES=() SEARCH_MATCHES=()
catalog_start || fail 'primera ejecución'
finish_download || fail finish
[[ "$CATALOG_STATUS" == 'Sin catálogo disponible; U reintentar' ]] || fail 'sin conexión'

rm "$task_tmp/release" "$task_tmp/pid"
catalog_start force || fail start
wait_marker || fail worker
read -r download_pid < "$task_tmp/pid"
catalog_stop
for ((i=0; i<100; i++)); do kill -0 "$download_pid" 2>/dev/null || break; sleep .01; done
kill -0 "$download_pid" 2>/dev/null && fail 'descarga huérfana'
[[ -z "$CATALOG_PID" && -z "$CATALOG_JOB_DIR" ]] || fail cleanup
printf 'ok   catálogo al inicio, segundo plano, fallo de red y limpieza\n'
