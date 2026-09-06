#!/usr/bin/env bash
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
player_is_running() { return 1; }
tput() { :; }
ui_refresh_size() { UI_COLS=$TEST_COLS; UI_LINES=$TEST_LINES; }
UI_ACTIVE=1 UI_SUSPENDED=0 UI_COLOR=0 UI_UNICODE=1 UI_HELP_VISIBLE=0
ui_configure_glyphs
FAVORITE_NAMES=() FAVORITE_URLS=()
for ((i=0; i<30; i++)); do FAVORITE_NAMES+=("Favorito $i"); FAVORITE_URLS+=("https://fav.invalid/$i"); done
FAVORITE_LABELS[https://fav.invalid/0]='Heavy Metal'
HISTORY_NAMES=('Radio reciente') HISTORY_URLS=('https://recent.invalid/radio')
SEARCH_NAMES=('Emisora inicial') SEARCH_URLS=('https://search.invalid/radio')
SEARCH_AMBITS=(Nacional) SEARCH_COUNTRIES=(España) SEARCH_FORMATS=(AAC) SEARCH_MATCHES=(0)
SEARCH_ACTIVE=0 SEARCH_QUERY='' SEARCH_SCROLL_OFFSET=0
for size in '132 40' '112 20' '80 24' '55 15' '45 12' '45 11'; do
    read -r TEST_COLS TEST_LINES <<< "$size"
    for selection in 0 30; do
        UI_SELECTED_INDEX=$selection
        render=$(ui_draw)
        rows=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            ((rows+=1))
            ((${#line} < TEST_COLS)) || fail "autowrap $size"
        done <<< "$render"
        ((rows <= TEST_LINES)) || fail "scroll vertical $size: $rows"
        if ((selection == 30)); then
            [[ "$render" == *'Radio reciente'* ]] || fail "reciente invisible $size"
        fi
        if ((TEST_COLS >= 112)); then
            [[ "$render" == *'Emisora inicial'* ]] || fail 'catálogo inicial invisible'
            [[ "$render" != *'Pulsa B y escribe'* && "$render" != *'BUSCAR EMISORAS'* ]] || fail 'ayuda duplicada'
            if ((selection == 0)); then
                [[ "$render" == *'Heavy Metal'* ]] || fail 'etiqueta invisible'
            fi
        fi
    done
done
printf 'ok   favoritos etiquetados, recientes y catálogo en seis tamaños\n'
