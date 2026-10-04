#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'search_async_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
SEARCH_SOURCE_FILE=$task_tmp/catalog.tsv
printf '%s\n' \
    $'Rock FM\tMadrid\tEspaña\tMP3\thttps://radio.invalid/rock\tES\trock madrid españa\tMadrid\trock' \
    $'Jazz FM\t\tFrancia\tAAC\thttps://radio.invalid/jazz\tFR\tjazz francia\t\tjazz' \
    $'Radio Prueba\t\t\t\thttps://radio.invalid/empty\t\tradio prueba\t\t' \
    $'Radio \'literal\' $(touch SHOULD_NOT_EXIST)\tCataluña\tEspaña\tAAC\thttps://radio.invalid/data\tES\tliteral datos\tCataluña\trock,jazz' > "$SEARCH_SOURCE_FILE"
FAVORITE_LABELS=([https://radio.invalid/rock]='despertador personal')
real_worker=$SEARCH_WORKER
snapshot() { declare -p SEARCH_NAMES SEARCH_AMBITS SEARCH_COUNTRIES SEARCH_FORMATS SEARCH_URLS SEARCH_COUNTRYCODES SEARCH_INDEX_TEXTS SEARCH_REGIONS SEARCH_TAGS SEARCH_MATCHES SEARCH_URL_INDEX; }
wait_result() {
    local step
    for ((step=0; step<300; step++)); do
        search_async_tick && return 0
        sleep .01
    done
    fail 'snapshot no llega'
}
for query in rock jazz despertador literal inexistente ''; do
    SEARCH_QUERY=$query SEARCH_FILTER_DIRTY=1
    search_filter
    expected=$(snapshot)
    SEARCH_FILTER_DIRTY=1
    search_async_tick && fail 'publica mientras el escritor está activo'
    [[ $SEARCH_FILTER_DIRTY == 1 && $(snapshot) == "$expected" ]] || fail 'al lanzar modifica arrays visibles'
    wait_result
    [[ $(snapshot) == "$expected" && $SEARCH_ASYNC_FAILED == 0 && -z $SEARCH_WORK_DIR && -z $SEARCH_WORK_PID ]] || fail "semántica/cierre: $query"
done
SEARCH_COUNTRY_FILTER_ENABLED=1 SEARCH_REGION_FILTER=Madrid SEARCH_TAG_FILTER=rock
SEARCH_QUERY=despertador
search_filter; expected=$(snapshot)
SEARCH_FILTER_DIRTY=1
search_async_tick || true
wait_result
[[ $(snapshot) == "$expected" ]] || fail 'comentarios no respetan los tres filtros'
SEARCH_COUNTRY_FILTER_ENABLED=0 SEARCH_REGION_FILTER='' SEARCH_TAG_FILTER=''

# Enter aprovecha el resultado ya terminado, sin ejecutar el filtro otra vez.
SEARCH_QUERY=rock SEARCH_FILTER_DIRTY=1
search_async_tick || true
for ((i=0; i<300; i++)); do kill -0 "$SEARCH_WORK_PID" 2>/dev/null || break; sleep .01; done
kill -0 "$SEARCH_WORK_PID" 2>/dev/null && fail 'worker terminado no llega'
filter_definition=$(declare -f search_filter)
# Stub constante, instalado solo después de comparar el filtro original.
eval 'search_filter() { fail "Enter repite un filtro que ya terminó"; }'
search_prepare_results
[[ $SEARCH_FILTER_DIRTY == 0 && ${SEARCH_NAMES[0]} == 'Rock FM' && -z $SEARCH_WORK_PID ]] || fail 'no consume el snapshot terminado'
eval "$filter_definition"

# Los datos no se ejecutan y los snapshots truncados nunca se publican.
SEARCH_QUERY=literal SEARCH_FILTER_DIRTY=1
search_async_tick || true
for ((i=0; i<300; i++)); do [[ -f $SEARCH_WORK_DIR/result ]] && break; sleep .01; done
[[ -f $SEARCH_WORK_DIR/result ]] || fail fixture
cp "$SEARCH_WORK_DIR/result" "$task_tmp/snapshot"
wait_result
[[ ${SEARCH_NAMES[0]} == *'$(touch SHOULD_NOT_EXIST)'* && ! -e SHOULD_NOT_EXIST ]] || fail 'ejecuta datos'
before=$(snapshot)
truncate -s -1 "$task_tmp/snapshot"
search_async_read "$task_tmp/snapshot" && fail 'acepta snapshot truncado'
[[ $(snapshot) == "$before" ]] || fail 'archivo truncado deja arrays parciales'
printf 'keila-search-v1\0009999999\000keila-search-end\000' > "$task_tmp/snapshot"
search_async_read "$task_tmp/snapshot" && fail 'acepta count fuera de límite'
[[ $(snapshot) == "$before" ]] || fail 'count corrupto muta resultados'
ln -s "$task_tmp/snapshot" "$task_tmp/link"
search_async_read "$task_tmp/link" && fail 'sigue enlace de snapshot'

start_slow() {
    SEARCH_WORKER=$ROOT_DIR/tests/fixtures/search-slow-worker.sh
    SEARCH_QUERY=old SEARCH_FILTER_DIRTY=1
    search_async_tick || true
    old_pid=$SEARCH_WORK_PID old_dir=$SEARCH_WORK_DIR
    for ((i=0; i<300; i++)); do [[ -f $old_dir/child ]] && return 0; sleep .01; done
    fail 'worker lento no arranca'
}
check_stopped() {
    [[ ! -e $old_dir ]] || fail 'deja directorio anterior'
    if kill -0 -- "-$old_pid" 2>/dev/null; then fail 'deja grupo/hijo huérfano'; fi
}
start_slow
SEARCH_QUERY=jazz SEARCH_WORKER=$real_worker
search_async_tick || true
check_stopped
wait_result
[[ ${SEARCH_NAMES[0]} == 'Jazz FM' ]] || fail 'publica una consulta obsoleta'

start_slow
SEARCH_QUERY=rock SEARCH_WORKER=$real_worker
search_prepare_results
check_stopped
search_selected_load || fail 'selección no disponible'
[[ $SELECTED_NAME == 'Rock FM' && -z $SEARCH_WORK_PID && $SEARCH_FILTER_DIRTY == 0 ]] || fail 'Enter/cursores usan la consulta anterior'

start_slow
search_close
check_stopped
[[ $SEARCH_FILTER_DIRTY == 0 ]] || fail 'Esc conserva filtro pendiente'

start_slow
cleanup
check_stopped

start_slow
KEILA_STATIONS_TSV=$SEARCH_SOURCE_FILE
stations_tsv_valid() { return 0; }
search_load_catalog || fail recargar
check_stopped

# Un error tiene fallback de sesión y no crea un bucle de procesos fallidos.
SEARCH_WORKER=/usr/bin/false SEARCH_QUERY=rock SEARCH_FILTER_DIRTY=1
search_async_tick || true
wait_result
[[ $SEARCH_ASYNC_FAILED == 1 && -z $SEARCH_WORK_PID && ${SEARCH_NAMES[0]} == 'Rock FM' ]] || fail 'sin fallback tras fallo'
SEARCH_QUERY=jazz SEARCH_FILTER_DIRTY=1
search_async_tick || fail 'fallback no aplica la siguiente consulta'
[[ -z $SEARCH_WORK_PID && ${SEARCH_NAMES[0]} == 'Jazz FM' ]] || fail 'relanza worker fallido'

# Edición masiva con Unicode y metacaracteres: una sola mutación, sin pérdida.
SEARCH_QUERY='' INPUT_REPEAT_COUNT=12
search_handle_key á || fail unicode
[[ $SEARCH_QUERY == 'áááááááááááá' ]] || fail 'repetición Unicode'
INPUT_REPEAT_COUNT=5
search_handle_key $'\177' || fail borrar
[[ $SEARCH_QUERY == 'ááááááá' ]] || fail 'borra bytes en lugar de caracteres'
for char in '&' $'\\' '$' '`' '*'; do
    SEARCH_QUERY='' INPUT_REPEAT_COUNT=3
    search_handle_key "$char" || fail metacaracter
    [[ $SEARCH_QUERY == "$char$char$char" ]] || fail 'interpreta replacement o metacaracteres'
done
SEARCH_QUERY='' INPUT_REPEAT_COUNT=500
search_handle_key x || fail limite
[[ ${#SEARCH_QUERY} == 80 ]] || fail 'supera 80 caracteres'
search_handle_key $'\x08' || fail limpiar
[[ -z $SEARCH_QUERY ]] || fail 'borrado masivo incompleto'
printf 'ok   filtro asíncrono: snapshots íntegros, filtros/comentarios, última consulta, fallback y cancelación sin huérfanos\n'
