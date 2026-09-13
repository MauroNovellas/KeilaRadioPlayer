#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'catalog_stop; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
keila_init_paths
printf '%s\n' '[
{"name":"Uno","url":"https://test.invalid/1","state":"Madrid","tags":"rock,jazz","country":"Spain","countrycode":"ES"},
{"name":"Dos","url":"https://test.invalid/2","state":"Barcelona","tags":"rock","country":"Spain","countrycode":"ES"},
{"name":"Tres","url":"https://test.invalid/3","state":"Paris","tags":"rock","country":"France","countrycode":"FR"},
{"name":"Cuatro","url":"https://test.invalid/4","state":"Madrid","tags":" hard rock , news","country":"Spain","countrycode":"ES"},
{"name":"Sin región","url":"https://test.invalid/5","tags":"rock","country":"Spain","countrycode":"ES"},
{"name":"Raro","url":"https://test.invalid/6","state":"A\\B","tags":"a.b","country":"Spain","countrycode":"ES"}
]' > "$KEILA_STATIONS_JSON"
stations_rebuild_tsv || fail índice
stations_tsv_has_facets || fail columnas
awk -F '\t' 'NR==1 { exit !($2=="Madrid" && $8=="Madrid" && $9=="rock,jazz" && index($7,"rock")) }' "$KEILA_STATIONS_TSV" || fail 'pierde temática con región'
search_load_catalog || fail carga
SEARCH_QUERY=rock
search_filters_set country ES
[[ ${#SEARCH_MATCHES[@]} == 4 && $SEARCH_QUERY == rock ]] || fail 'país más consulta'
search_filters_set region Madrid
[[ ${#SEARCH_MATCHES[@]} == 2 ]] || fail región
search_filters_set tag rock
[[ ${#SEARCH_MATCHES[@]} == 1 && ${SEARCH_NAMES[0]} == Uno ]] || fail 'etiqueta exacta'
search_clear
search_apply_pending_filter || true
[[ $SEARCH_REGION_FILTER == Madrid && $SEARCH_TAG_FILTER == rock && ${#SEARCH_MATCHES[@]} == 1 ]] || fail 'Supr borra filtros'
search_close; search_open || fail reapertura
[[ $SEARCH_REGION_FILTER == Madrid && ${#SEARCH_MATCHES[@]} == 1 ]] || fail 'reapertura pierde filtros'
search_filters_set country FR
[[ -z $SEARCH_REGION_FILTER && $SEARCH_TAG_FILTER == rock && ${SEARCH_NAMES[0]} == Tres ]] || fail 'cambio de país'
search_filters_set country ES
[[ $(search_filter_choices region) != *Paris* ]] || fail 'regiones de otro país'
[[ $(search_filter_choices country) == *'España (ES)'* ]] || fail 'selector por nombre y código'
search_filters_set region Madrid
[[ $(search_filter_choices tag) == *jazz* && $(search_filter_choices tag) != *a.b* ]] || fail 'temáticas regionales'
declare -A FAVORITE_LABELS=([https://test.invalid/3]=especial [https://test.invalid/1]=especial)
SEARCH_QUERY=especial
search_filter
[[ ${#SEARCH_MATCHES[@]} == 1 && ${SEARCH_NAMES[0]} == Uno ]] || fail 'comentario salta filtros'
search_filters_set clear ''
[[ $SEARCH_QUERY == especial && ${#SEARCH_MATCHES[@]} == 2 ]] || fail 'quitar filtros borra consulta'
SEARCH_QUERY='a.b'
search_filter
[[ ${#SEARCH_MATCHES[@]} == 1 && ${SEARCH_NAMES[0]} == Raro ]] || fail 'consulta interpreta regex'
SEARCH_QUERY='\n'
search_filter
[[ ${#SEARCH_MATCHES[@]} == 0 ]] || fail 'consulta interpreta escape'
# Mismo comportamiento con índice en memoria y columnas separadas.
SEARCH_SOURCE_ROWS=$(cat "$KEILA_STATIONS_TSV") SEARCH_SOURCE_FILE='' SEARCH_QUERY=rock
SEARCH_COUNTRY_FILTER_ENABLED=1 KEILA_CATALOG_COUNTRY_FILTER=ES SEARCH_REGION_FILTER=Madrid SEARCH_TAG_FILTER=rock
search_filter
[[ ${#SEARCH_MATCHES[@]} == 1 ]] || fail 'fallback no respeta filtros'
# Migración local del índice antiguo, con la lista disponible desde el inicio.
cut -f1-7 "$KEILA_STATIONS_TSV" > "$task_tmp/legacy"
cp "$task_tmp/legacy" "$KEILA_STATIONS_TSV"
SEARCH_REGION_FILTER='' SEARCH_TAG_FILTER='' SEARCH_QUERY='' SEARCH_SOURCE_ROWS=''
search_load_catalog; search_filter
catalog_start || fail migración
[[ -n $CATALOG_PID && ${#SEARCH_MATCHES[@]} -gt 0 ]] || fail 'migración bloquea catálogo'
for ((i=0; i<150; i++)); do catalog_poll && break; sleep .01; done
[[ -z $CATALOG_PID ]] || fail 'migración no termina'
stations_tsv_has_facets || fail 'migración sin columnas nuevas'
SEARCH_QUERY=rock; search_filters_set region Madrid; search_filters_set tag rock
[[ ${#SEARCH_MATCHES[@]} == 1 ]] || fail 'migración no refresca búsqueda'
# El selector externo recibe los mismos filtros y no mezcla columnas nuevas
# con el código del país al devolver la selección.
stations_require_search_dependencies() { :; }
stations_ensure_catalog() { :; }
fzf() { sed -n '1p'; }
stations_select_fzf_external || fail 'fzf filtrado'
[[ $SELECTED_NAME == Uno && $SELECTED_COUNTRYCODE == ES ]] || fail 'fzf pierde filtros o campos'
# Aplicar un valor obtenido del selector siempre debe coincidir consigo mismo,
# también donde awk y Bash tengan distintas reglas de minúsculas Unicode.
printf 'Unicode\tCATALUÑA\tSpain\tMP3\thttps://test.invalid/unicode\tES\tunicode\tCATALUÑA\tMÚSICA\n' >> "$KEILA_STATIONS_TSV"
SEARCH_QUERY=''
search_filters_set region CATALUÑA
search_filters_set tag MÚSICA
[[ ${#SEARCH_MATCHES[@]} == 1 && ${SEARCH_NAMES[0]} == Unicode ]] || fail 'selección con acentos'
[[ $(search_filter_choices tag) == *MÚSICA* ]] || fail 'selector regional con acentos'
printf 'ok   filtros combinados, metadatos separados, comentarios, consulta y migración local\n'
