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

# La escritura debe actualizar el texto inmediatamente, sin esperar a recorrer
# el catálogo. El filtrado queda pendiente hasta el siguiente TICK/pausa.
search_append R
search_append o
search_append c
search_append k
assert_eq 'Rock' "$SEARCH_QUERY" 'texto escrito inmediatamente'
assert_eq 1 "$SEARCH_FILTER_DIRTY" 'filtro queda pendiente mientras se escribe'
assert_eq 4 "${#SEARCH_MATCHES[@]}" 'escribir no bloquea recalculando resultados'
search_apply_pending_filter || fail 'no aplicó filtro pendiente'
assert_eq 0 "$SEARCH_FILTER_DIRTY" 'filtro pendiente queda resuelto'
assert_eq 2 "${#SEARCH_MATCHES[@]}" 'filtrado por nombre'

search_move 1
search_selected_load || fail 'no cargó segundo resultado'
assert_eq 'Classic Rock' "$SELECTED_NAME" 'navegación al segundo resultado'

search_move 1
assert_eq 0 "$SEARCH_SELECTED_INDEX" 'navegación circular'

search_backspace
assert_eq 'Roc' "$SEARCH_QUERY" 'backspace elimina carácter inmediatamente'
assert_eq 1 "$SEARCH_FILTER_DIRTY" 'backspace deja filtro pendiente'
search_apply_pending_filter || fail 'no aplicó filtro tras backspace'

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
assert_eq 'Barcelona' "$SEARCH_QUERY" 'consulta por ámbito escrita completa'
assert_eq 1 "$SEARCH_FILTER_DIRTY" 'consulta por ámbito se difiere'
search_apply_pending_filter || fail 'no filtró por ámbito'
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
search_apply_pending_filter || fail 'no filtró por país'
assert_eq 1 "${#SEARCH_MATCHES[@]}" 'filtrado por país sin distinguir mayúsculas'
search_selected_load || fail 'no seleccionó resultado por país'
assert_eq 'Jazz World' "$SELECTED_NAME" 'resultado por país correcto'

search_clear
search_apply_pending_filter || fail 'no restauró catálogo completo'
SEARCH_SELECTED_INDEX=3
search_sync_scroll 2
assert_eq 2 "$SEARCH_SCROLL_OFFSET" 'scroll sigue la selección'

# Estabilización: Esc deja la consulta visible como "B editar". Reabrir debe
# conservarla de verdad y recalcular resultados con el catálogo recién cargado.
search_clear || true
search_append z
search_append z
search_append z
search_apply_pending_filter || fail 'no aplicó consulta sin resultados'
assert_eq 0 "${#SEARCH_MATCHES[@]}" 'consulta inexistente produce cero resultados'
search_close
assert_eq 0 "$SEARCH_ACTIVE" 'cerrar búsqueda desactiva el foco'
assert_eq 'zzz' "$SEARCH_QUERY" 'cerrar conserva la consulta visible'
assert_eq 0 "$SEARCH_SCROLL_OFFSET" 'cerrar normaliza scroll'

search_open || fail 'no pudo reabrir búsqueda conservada'
assert_eq 1 "$SEARCH_ACTIVE" 'reabrir recupera foco'
assert_eq 'zzz' "$SEARCH_QUERY" 'B editar conserva la consulta anterior'
assert_eq 0 "${#SEARCH_MATCHES[@]}" 'reabrir recalcula la consulta conservada'
assert_eq 0 "$SEARCH_SELECTED_INDEX" 'sin resultados mantiene selección segura'

search_clear || fail 'no pudo limpiar consulta reabierta'
search_apply_pending_filter || fail 'no restauró catálogo tras reabrir'
assert_eq 4 "${#SEARCH_MATCHES[@]}" 'limpiar tras reabrir restaura catálogo'

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
SEARCH_FILTER_DIRTY=0
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
declare -F search_prepare_results >/dev/null || fail 'falta sincronización antes de navegar/reproducir'

printf 'ok   búsqueda integrada: input, reapertura, filtrado, navegación y TUI\n'
