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
            if ((TEST_COLS >= 132)); then
                [[ "$render" == *'ETIQUETAS PERSONALES'* ]] || fail 'cabecera larga invisible'
            else
                [[ "$render" == *'ETIQUETAS'* && "$render" != *'ETIQUETAS PERSONALES'* ]] || fail 'cabecera no se abrevia'
            fi
            [[ "$render" == *'BUSQUEDA EMISORAS'* ]] || fail 'título de búsqueda invisible'
            [[ "$render" == *'Emisora inicial'* ]] || fail 'catálogo inicial invisible'
            [[ "$render" != *'Pulsa B y escribe'* && "$render" != *'BUSCAR EMISORAS'* ]] || fail 'ayuda duplicada'
            if ((selection == 0)); then
                [[ "$render" == *'Heavy Metal'* ]] || fail 'etiqueta invisible'
            fi
        else
            [[ "$render" == *'EQ ▄▄▄▄▄'* ]] || fail "ecualizador permanente invisible $size"
        fi
    done
done

# El editor gráfico y el espectro conservan la geometría del panel de escritorio.
TEST_COLS=132 TEST_LINES=40 UI_SELECTED_INDEX=0
EQUALIZER_EDITOR_ACTIVE=1
EQUALIZER_GAINS=(12 6 0 -6 -12)
render=$(ui_draw)
[[ "$render" == *'EQ'* && "$render" == *'60'* && "$render" == *'250'* && "$render" == *'12k'* && "$render" == *'+12'* && "$render" == *'╋'* ]] || fail 'editor gráfico integrado invisible'
while IFS= read -r line || [[ -n "$line" ]]; do
    ((${#line} < TEST_COLS)) || fail 'autowrap del editor gráfico'
done <<< "$render"
EQUALIZER_EDITOR_ACTIVE=0
SPECTRUM_ENABLED=1
SPECTRUM_LEVELS=(0 1 2 3 4 5 6 7 8 7 6 5 4 3 2 1)
render=$(ui_draw)
[[ "$render" == *'ESPECTRO'* && "$render" == *'V ocultar'* ]] || fail 'analizador invisible'
[[ "$render" == *'EQ'* && "$render" == *'60'* && "$render" == *'12k'* ]] || fail 'ecualizador permanente invisible en desktop'

# Ambos gráficos comparten el ancho completo del panel Ahora suena y el
# espectro empieza después del bloque de ocho filas del ecualizador.
ui_desktop_pane_widths "$((TEST_COLS - 1))"
wide_eq=$(ui_equalizer_wide_row 4 "$UI_DESKTOP_LEFT_WIDTH")
wide_spectrum=$(ui_spectrum_editor_row_wide 7 "$UI_DESKTOP_LEFT_WIDTH")
assert_width=${#wide_eq}
((assert_width == UI_DESKTOP_LEFT_WIDTH)) || fail 'ecualizador no ocupa el ancho del panel'
assert_width=${#wide_spectrum}
((assert_width == UI_DESKTOP_LEFT_WIDTH)) || fail 'espectro no ocupa el ancho del panel'
eq_line=$(printf '%s\n' "$render" | awk '/│ EQ/{print NR; exit}')
spectrum_line=$(printf '%s\n' "$render" | awk '/ESPECTRO/{print NR; exit}')
((eq_line > 0 && spectrum_line > eq_line)) || fail 'espectro no aparece debajo del ecualizador'
while IFS= read -r line || [[ -n "$line" ]]; do
    ((${#line} < TEST_COLS)) || fail 'autowrap del analizador'
done <<< "$render"
printf 'ok   favoritos etiquetados, recientes y catálogo en seis tamaños\n'
