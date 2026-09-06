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

set -- --version
# shellcheck source=../keila-radio
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT

FAVORITE_NAMES=(F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11)
FAVORITE_URLS=(u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11)
UI_SELECTED_INDEX=0
UI_SCROLL_OFFSET=0
PLAY_CALLS=0
PLAY_NAME=''
PLAY_URL=''
LAST_MESSAGE=''

# Estas sustituciones se invocan indirectamente desde app_handle_key y
# app_play_favorite_preset, algo que ShellCheck no puede seguir estáticamente.
# shellcheck disable=SC2317
favorites_load() { return 0; }
# shellcheck disable=SC2317
ui_sync_selection() { return 0; }
# shellcheck disable=SC2317
app_play() {
    ((PLAY_CALLS += 1))
    PLAY_NAME="$1"
    PLAY_URL="$2"
    return 0
}
# shellcheck disable=SC2317
app_message() {
    LAST_MESSAGE="$1"
}

app_handle_key 1 || fail 'preset 1 no fue reconocido'
assert_eq 0 "$UI_SELECTED_INDEX" '1 selecciona el primer favorito'
assert_eq F1 "$PLAY_NAME" '1 reproduce el primer favorito'
assert_eq u1 "$PLAY_URL" '1 usa la URL del primer favorito'

app_handle_key 9 || fail 'preset 9 no fue reconocido'
assert_eq 8 "$UI_SELECTED_INDEX" '9 selecciona el noveno favorito'
assert_eq F9 "$PLAY_NAME" '9 reproduce el noveno favorito'

app_handle_key 0 || fail 'preset 0 no fue reconocido'
assert_eq 9 "$UI_SELECTED_INDEX" '0 selecciona la décima posición'
assert_eq F10 "$PLAY_NAME" '0 reproduce el décimo favorito'
assert_eq u10 "$PLAY_URL" '0 usa la URL del décimo favorito'

# Un preset que no exista debe quedarse vacío, nunca caer al último favorito
# por el clamp normal de ui_sync_selection.
FAVORITE_NAMES=(F1 F2 F3 F4 F5 F6 F7 F8 F9)
FAVORITE_URLS=(u1 u2 u3 u4 u5 u6 u7 u8 u9)
PLAY_CALLS=0
PLAY_NAME=''
PLAY_URL=''
LAST_MESSAGE=''
app_handle_key 0 || fail '0 con menos de diez favoritos dejó de ser una tecla válida'
assert_eq 0 "$PLAY_CALLS" '0 sin décimo favorito no reproduce otra emisora'
[[ "$LAST_MESSAGE" == *'No hay favorito asignado al preset 0.'* ]] || fail 'falta mensaje de preset sin asignar'

# Dentro de Buscar, los dígitos siguen siendo texto de consulta y no pasan por
# app_handle_key, por lo que buscar "101" continúa siendo posible.
SEARCH_QUERY=''
SEARCH_FILTER_DIRTY=0
search_handle_key 1 || fail '1 no se aceptó como texto de búsqueda'
search_handle_key 0 || fail '0 no se aceptó como texto de búsqueda'
search_handle_key 1 || fail 'segundo 1 no se aceptó como texto de búsqueda'
assert_eq 101 "$SEARCH_QUERY" 'los dígitos se conservan como texto dentro de Buscar'

printf 'ok   favoritos: presets 1-9 y 0→10 sin buffer ni conflicto con búsqueda\n'
