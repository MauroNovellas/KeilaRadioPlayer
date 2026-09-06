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

set -- --version
# shellcheck source=../keila-radio
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT

LAST_MESSAGE=''
PLAYER_RUNNING=1
UI_SELECTED_INDEX=0
UI_SCROLL_OFFSET=0

# shellcheck disable=SC2317
app_message() {
    LAST_MESSAGE="$1"
}

# shellcheck disable=SC2317
player_is_running() {
    ((PLAYER_RUNNING))
}

# shellcheck disable=SC2317
ui_select_url() {
    local url="$1" index
    index=$(favorites_find_url "$url") || return 1
    UI_SELECTED_INDEX=$index
}

# shellcheck disable=SC2317
ui_sync_selection() {
    local count=${#FAVORITE_NAMES[@]}
    if ((count == 0)); then
        UI_SELECTED_INDEX=0
        UI_SCROLL_OFFSET=0
    elif ((UI_SELECTED_INDEX >= count)); then
        UI_SELECTED_INDEX=$((count - 1))
    fi
}

# shellcheck disable=SC2317
ui_move_selection() { return 0; }

app_init_data || fail 'no pudo inicializar datos temporales'
: > "$KEILA_FAVORITES_FILE"
favorites_load || fail 'no pudo cargar favoritos vacíos'

PLAYER_NAME='Radio A'
PLAYER_URL='https://example.invalid/a'

# Añadir sigue siendo inmediato.
app_toggle_favorite || fail 'F no añadió favorito'
favorites_load || fail 'no pudo recargar tras añadir'
assert_eq '1' "${#FAVORITE_NAMES[@]}" 'F añade con una sola pulsación'
assert_eq 'added' "${FAVORITES_TOGGLE_ACTION:-}" 'acción de alta inmediata'
[[ "$LAST_MESSAGE" == *'Añadida a favoritos: Radio A'* ]] || fail 'falta mensaje de alta'

# Primera F destructiva solo arma la confirmación.
app_toggle_favorite || fail 'primera F destructiva falló'
favorites_load || fail 'no pudo recargar tras confirmación'
assert_eq '1' "${#FAVORITE_NAMES[@]}" 'primera F destructiva conserva favorito'
assert_eq '' "${FAVORITES_TOGGLE_ACTION:-}" 'confirmación no se marca como baja'
assert_eq 'playing' "${FAVORITES_CONFIRM_ACTION:-}" 'confirmación ligada a emisora en reproducción'
[[ "$LAST_MESSAGE" == *'Pulsa F otra vez para eliminar de favoritos: Radio A'* ]] || fail 'falta mensaje de confirmación F'

# Segunda F confirma la baja.
app_toggle_favorite || fail 'segunda F destructiva no eliminó'
favorites_load || fail 'no pudo recargar tras eliminar'
assert_eq '0' "${#FAVORITE_NAMES[@]}" 'segunda F confirma eliminación'
assert_eq 'removed' "${FAVORITES_TOGGLE_ACTION:-}" 'acción de baja confirmada'
assert_eq '' "${FAVORITES_CONFIRM_ACTION:-}" 'confirmación se limpia tras borrar'

# X también exige confirmación sobre el favorito seleccionado.
favorites_add 'Radio A' 'https://example.invalid/a' || fail 'no pudo preparar Radio A'
favorites_add 'Radio B' 'https://example.invalid/b' || fail 'no pudo preparar Radio B'
favorites_load || fail 'no pudo cargar favoritos para X'
UI_SELECTED_INDEX=0
PLAYER_RUNNING=0
LAST_MESSAGE=''

app_remove_selected_favorite || fail 'primera X falló'
favorites_load || fail 'no pudo recargar tras primera X'
assert_eq '2' "${#FAVORITE_NAMES[@]}" 'primera X no elimina'
assert_eq 'selected' "${FAVORITES_CONFIRM_ACTION:-}" 'X arma confirmación seleccionada'
[[ "$LAST_MESSAGE" == *'Pulsa X otra vez para eliminar el favorito: Radio A'* ]] || fail 'falta mensaje de confirmación X'

app_remove_selected_favorite || fail 'segunda X no eliminó'
favorites_load || fail 'no pudo recargar tras segunda X'
assert_eq '1' "${#FAVORITE_NAMES[@]}" 'segunda X elimina el seleccionado'
assert_eq 'Radio B' "${FAVORITE_NAMES[0]}" 'X eliminó el favorito correcto'
assert_eq '' "${FAVORITES_CONFIRM_ACTION:-}" 'confirmación X se limpia tras borrar'

# Una acción diferente invalida la confirmación pendiente.
UI_SELECTED_INDEX=0
app_remove_selected_favorite || fail 'no pudo armar confirmación para cancelación'
assert_eq 'selected' "${FAVORITES_CONFIRM_ACTION:-}" 'confirmación armada antes de otra acción'
app_handle_key w || fail 'acción de navegación falló'
assert_eq '' "${FAVORITES_CONFIRM_ACTION:-}" 'otra acción cancela la confirmación'

# Una confirmación caducada tampoco permite borrar con una sola pulsación.
favorites_confirm_removal 'selected' 'https://example.invalid/b' >/dev/null 2>&1 || true
FAVORITES_CONFIRM_EXPIRES=1
favorites_confirm_expire >/dev/null 2>&1 || fail 'confirmación caducada no se limpió'
assert_eq '' "${FAVORITES_CONFIRM_ACTION:-}" 'caducidad limpia la confirmación'

printf 'ok   favoritos: añadir es inmediato y eliminar exige confirmación\n'
