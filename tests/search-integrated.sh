#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

stations_emit_tsv() {
    cat <<'EOF'
Rock FM	Madrid	España	AAC	https://example.invalid/rock
Classic Rock	Barcelona	España	MP3	https://example.invalid/classic
Radio Nacional	Nacional	España	AAC	https://example.invalid/rne
Jazz World	Internacional	Francia	MP3	https://example.invalid/jazz
EOF
}

source "$ROOT_DIR/lib/search.sh"

search_open || fail 'no pudo cargar catálogo simulado'
assert_eq 1 "$SEARCH_ACTIVE" 'búsqueda activa'
assert_eq 4 "${#SEARCH_MATCHES[@]}" 'catálogo completo al abrir'

search_append R
search_append o
search_append c
search_append k
assert_eq 'Rock' "$SEARCH_QUERY" 'texto escrito'
assert_eq 2 "${#SEARCH_MATCHES[@]}" 'filtrado por nombre'

search_move 1
search_selected_load || fail 'no cargó segundo resultado'
assert_eq 'Classic Rock' "$SELECTED_NAME" 'navegación al segundo resultado'

search_move 1
assert_eq 0 "$SEARCH_SELECTED_INDEX" 'navegación circular'

search_backspace
assert_eq 'Roc' "$SEARCH_QUERY" 'backspace elimina carácter'

search_clear
search_append B
search_append a
search_append r
search_append c
search_append e
search_append l
search_append o
search_append n
search_append a
assert_eq 1 "${#SEARCH_MATCHES[@]}" 'filtrado por ámbito'
search_selected_load || fail 'no seleccionó resultado por ámbito'
assert_eq 'Classic Rock' "$SELECTED_NAME" 'resultado por ámbito correcto'

search_clear
search_append f
search_append r
search_append a
search_append n
search_append c
search_append i
search_append a
assert_eq 1 "${#SEARCH_MATCHES[@]}" 'filtrado por país sin distinguir mayúsculas'
search_selected_load || fail 'no seleccionó resultado por país'
assert_eq 'Jazz World' "$SELECTED_NAME" 'resultado por país correcto'

search_clear
SEARCH_SELECTED_INDEX=3
search_sync_scroll 2
assert_eq 2 "$SEARCH_SCROLL_OFFSET" 'scroll sigue la selección'

# Comprueba que la capa visual existe y mantiene geometría desktop exacta en el
# modo Unicode real. El fallback ASCII tiene todos los vértices como '+' y se
# prueba por separado de la protección de scroll del borde final.
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/ui-responsive.sh"
source "$ROOT_DIR/lib/ui-safe-width.sh"

player_is_running() { return 1; }
UI_UNICODE=1
UI_COLOR=0
UI_HELP_VISIBLE=0
UI_LINES=20
UI_LAYOUT_MODE=wide
ui_configure_glyphs

SEARCH_QUERY='rock'
SEARCH_NAMES=('Rock FM' 'Classic Rock')
SEARCH_AMBITS=('Madrid' 'Barcelona')
SEARCH_COUNTRIES=('España' 'España')
SEARCH_FORMATS=('AAC' 'MP3')
SEARCH_URLS=('https://example.invalid/rock' 'https://example.invalid/classic')
SEARCH_MATCHES=(0 1)
SEARCH_SELECTED_INDEX=0
SEARCH_SCROLL_OFFSET=0
PLAYER_URL='https://example.invalid/none'
PLAYER_NAME='Radio Test'

render=$(ui_search_desktop 119)
first_line=${render%%$'\n'*}
assert_eq 119 "${#first_line}" 'búsqueda desktop respeta ancho seguro'
[[ "$render" == *'BUSCAR EMISORAS'* ]] || fail 'falta cabecera de búsqueda'
[[ "$render" == *'RESULTADOS (2)'* ]] || fail 'falta contador de resultados'
[[ "$render" == *'Rock FM'* ]] || fail 'falta primer resultado'
[[ "$render" == *'Classic Rock'* ]] || fail 'falta segundo resultado'

declare -F stations_select_fzf_external >/dev/null || fail 'falta fallback fzf'
declare -F stations_select_fzf >/dev/null || fail 'falta selector integrado'

printf 'ok   búsqueda integrada: filtrado, navegación y TUI\n'
