#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_STATE_HOME="$tmp/state"
export XDG_CACHE_HOME="$tmp/cache"
mkdir -p "$HOME"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/lock.sh"
source "$ROOT_DIR/lib/favorites.sh"

stations_emit_tsv() {
    cat <<'EOF'
Rock FM	Madrid	España	AAC	https://example.invalid/rock
Classic Rock	Barcelona	España	MP3	https://example.invalid/classic
Radio Nacional	Nacional	España	AAC	https://example.invalid/rne
EOF
}

source "$ROOT_DIR/lib/app-search.sh"

LAST_MESSAGE=''
UI_SELECTED_INDEX=0
UI_SCROLL_OFFSET=0

app_message() {
    LAST_MESSAGE="$1"
}

ui_select_url() {
    local url="$1" index
    index=$(favorites_find_url "$url") || return 1
    UI_SELECTED_INDEX=$index
}

ui_sync_selection() {
    local count=${#FAVORITE_NAMES[@]}
    if ((count == 0)); then
        UI_SELECTED_INDEX=0
        UI_SCROLL_OFFSET=0
    elif ((UI_SELECTED_INDEX >= count)); then
        UI_SELECTED_INDEX=$((count - 1))
    fi
}

favorites_init || fail 'no pudo crear favoritos temporales'
favorites_load || fail 'no pudo cargar favoritos temporales'
assert_eq 0 "${#FAVORITE_NAMES[@]}" 'favoritos empiezan vacíos'

search_open || fail 'no pudo abrir catálogo simulado'

# La f minúscula sigue siendo texto normal; solo F mayúscula se reserva en el
# bucle de búsqueda para gestionar el favorito activo.
search_handle_key f || fail 'f minúscula no fue aceptada como texto'
assert_eq 'f' "$SEARCH_QUERY" 'f minúscula se escribe en la consulta'
search_clear || fail 'no pudo limpiar consulta'
search_apply_pending_filter || fail 'no restauró catálogo tras limpiar'

search_append R
search_append o
search_append c
search_append k
search_apply_pending_filter || fail 'no filtró Rock'
assert_eq 2 "${#SEARCH_MATCHES[@]}" 'consulta Rock encuentra dos emisoras'
search_selected_load || fail 'no cargó resultado seleccionado'
assert_eq 'Rock FM' "$SELECTED_NAME" 'resultado activo antes de favorito'

search_toggle_selected_favorite || fail 'F no añadió el resultado a favoritos'
assert_eq 1 "${#FAVORITE_NAMES[@]}" 'lista superior recibe favorito nuevo'
assert_eq 'Rock FM' "${FAVORITE_NAMES[0]}" 'nombre favorito añadido'
assert_eq 'https://example.invalid/rock' "${FAVORITE_URLS[0]}" 'URL favorita añadida'
assert_eq 'added' "${FAVORITES_TOGGLE_ACTION:-}" 'acción de alta'
[[ "$LAST_MESSAGE" == *'Añadida a favoritos: Rock FM'* ]] || fail 'falta mensaje de alta'
assert_eq 1 "$SEARCH_ACTIVE" 'añadir favorito no cierra búsqueda'
assert_eq 0 "$SEARCH_SELECTED_INDEX" 'añadir favorito conserva resultado seleccionado'

UI_SEP='·'
UI_FAVORITE='★'
ui_search_result_parts 0
assert_eq 1 "$UI_SEARCH_IS_FAVORITE" 'renderer reconoce resultado favorito'
assert_eq '[★] Madrid · España' "$(ui_search_result_badge 0)" 'badge de favorito'
assert_eq '[PLAY] [★]' "$(ui_search_result_badge 1)" 'badge combinado play y favorito'

search_toggle_selected_favorite || fail 'segunda F no eliminó el favorito'
assert_eq 0 "${#FAVORITE_NAMES[@]}" 'segunda F elimina de la lista superior'
assert_eq 'removed' "${FAVORITES_TOGGLE_ACTION:-}" 'acción de baja'
[[ "$LAST_MESSAGE" == *'Eliminada de favoritos: Rock FM'* ]] || fail 'falta mensaje de baja'
assert_eq 1 "$SEARCH_ACTIVE" 'eliminar favorito no cierra búsqueda'
assert_eq 0 "$SEARCH_SELECTED_INDEX" 'eliminar favorito conserva resultado seleccionado'

ui_search_result_parts 0
assert_eq 0 "$UI_SEARCH_IS_FAVORITE" 'renderer retira marca tras eliminar'

printf 'ok   búsqueda integrada: F añade/quita favoritos sin salir ni reproducir\n'
