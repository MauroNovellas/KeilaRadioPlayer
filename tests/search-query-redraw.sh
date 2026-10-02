#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
# shellcheck disable=SC2317
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
task_tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ui_refresh_size() { :; }
tput() { if [[ $1 == cup ]]; then printf '<%s,%s>' "$2" "$3"; fi; }
player_is_running() { return 1; }
UI_ACTIVE=1 UI_SUSPENDED=0 UI_COLOR=0 UI_HELP_VISIBLE=0
SEARCH_ACTIVE=1 SEARCH_QUERY=rock SEARCH_FILTER_DIRTY=0
SEARCH_SELECTED_INDEX=0 SEARCH_SCROLL_OFFSET=0
FAVORITE_NAMES=() FAVORITE_URLS=() HISTORY_NAMES=() HISTORY_URLS=()
RECENT_NAMES=() RECENT_URLS=()
SEARCH_NAMES=('Rock FM') SEARCH_URLS=(https://radio.invalid/)
SEARCH_AMBITS=(Madrid) SEARCH_COUNTRIES=(España) SEARCH_COUNTRYCODES=(ES)
SEARCH_FORMATS=(MP3) SEARCH_MATCHES=(0)

for dimensions in '160 40' '112 20' '80 24' '62 16' '50 13' '42 11' '40 10' '20 8'; do
    read -r UI_COLS UI_LINES <<< "$dimensions"
    for UI_UNICODE in 0 1; do
        ui_configure_glyphs
        SEARCH_QUERY='un nombre de emisora largo' SEARCH_FILTER_DIRTY=0
        search_draw_view > "$task_tmp/old"
        [[ -n $UI_SEARCH_QUERY_FRAME_KEY ]] || fail "no prepara cursor $dimensions"
        cursor=$UI_SEARCH_QUERY_CURSOR
        [[ $cursor =~ ^\<([0-9]+),([0-9]+)\>$ ]] || fail 'cursor no reconocido'
        row=${BASH_REMATCH[1]} col=${BASH_REMATCH[2]}
        width=$UI_SEARCH_QUERY_WIDTH
        old_kind=$UI_SEARCH_QUERY_KIND
        SEARCH_QUERY='r' SEARCH_FILTER_DIRTY=1
        partial=$(ui_draw_search_query_only) || fail 'no repinta consulta'
        [[ $partial != *$'\n'* ]] || fail 'consulta mueve filas'
        [[ $partial == "$cursor"* ]] || fail 'no se limita al cursor preparado'
        content=${partial#"$cursor"}
        ((${#content} == width)) || fail 'no borra toda la consulta anterior'
        search_draw_view > "$task_tmp/new"
        mapfile -t full_lines < "$task_tmp/new"
        if [[ ${full_lines[row]:col:width} != "$content" ]]; then
            printf 'row=%s col=%s width=%s\nexpected=%q\nactual=%q\n' "$row" "$col" "$width" "$content" "${full_lines[row]:col:width}"
            printf 'previous=%q\nnext=%q\n' "${full_lines[row-1]}" "${full_lines[row+1]}"
            fail "dibujo parcial distinto del completo $dimensions"
        fi
        # Al desaparecer la consulta no deben quedar restos del texto anterior.
        SEARCH_QUERY=''
        partial=$(ui_draw_search_query_only) || fail 'no limpia consulta'
        [[ $partial != *'nombre de emisora'* ]] || fail 'restos de consulta'
        # Escribir no puede consultar terminal, analizar catálogo ni dibujar listas.
        tput() { fail 'tput durante pulsación'; }
        search_filter() { fail 'filtrado durante pulsación'; }
        ui_search_result_parts() { fail 'resultados durante pulsación'; }
        ui_draw_search_query_only > /dev/null || fail 'consulta depende de renderer completo'
        # Recuperar las funciones para la siguiente geometría.
        tput() { if [[ $1 == cup ]]; then printf '<%s,%s>' "$2" "$3"; fi; }
        source "$ROOT_DIR/lib/search.sh"
        source "$ROOT_DIR/lib/ui-search.sh"
        SEARCH_ACTIVE=1 SEARCH_QUERY=rock SEARCH_FILTER_DIRTY=0
        SEARCH_NAMES=('Rock FM') SEARCH_URLS=(https://radio.invalid/)
        SEARCH_AMBITS=(Madrid) SEARCH_COUNTRIES=(España) SEARCH_COUNTRYCODES=(ES)
        SEARCH_FORMATS=(MP3) SEARCH_MATCHES=(0)
    done
done

UI_COLS=132 UI_LINES=40
search_draw_view > /dev/null
for guard in UI_SUSPENDED INPUT_RESIZE_PENDING PREFERENCES_ACTIVE LABEL_EDITOR_ACTIVE; do
    printf -v "$guard" 1
    partial=$(ui_draw_search_query_only) && fail "dibujo durante $guard"
    [[ -z $partial ]] || fail "escribe antes de comprobar $guard"
    printf -v "$guard" 0
done
UI_COLS=80
partial=$(ui_draw_search_query_only) && fail 'cursor obsoleto tras resize'
[[ -z $partial ]] || fail 'resize toca la posición anterior'
search_draw_view > /dev/null
[[ $UI_SEARCH_QUERY_KIND == single ]] || fail 'resize no cambia composición'
ui_draw_search_query_only > /dev/null || fail 'no recupera dibujo tras resize'
SEARCH_ACTIVE=0
ui_draw_search_query_only > /dev/null && fail 'dibujo sin búsqueda activa'

printf 'ok   consulta parcial: mismo render, borrado, ASCII/Unicode, 8 tamaños y resize\n'
