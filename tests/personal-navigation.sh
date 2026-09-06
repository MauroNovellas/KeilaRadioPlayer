#!/usr/bin/env bash
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'catalog_stop; rm -rf "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
config_load "$task_tmp/recordings" || fail config
favorites_init '' || fail init
favorites_load
favorites_add 'Rock FM' 'https://radio.invalid/rock' || fail add
labels_set 'https://radio.invalid/rock' 'Heavy Metal' || fail label
labels_load
[[ "${FAVORITE_LABELS[https://radio.invalid/rock]}" == 'Heavy Metal' ]] || fail roundtrip
[[ "$(cat "$KEILA_FAVORITES_FILE")" == 'Rock FM|https://radio.invalid/rock' ]] || fail 'compatibilidad favoritos'
favorites_add 'Otra' 'https://radio.invalid/other' || fail add
favorites_move 0 1 || fail move
[[ "${FAVORITE_LABELS[${FAVORITE_URLS[1]}]}" == 'Heavy Metal' ]] || fail 'etiqueta tras reordenar'
labels_set 'https://radio.invalid/rock' $'Metal\e[31m|prueba\n' || fail sanitize
[[ "${FAVORITE_LABELS[https://radio.invalid/rock]}" != *$'\e'* ]] || fail 'escape persistido'
labels_set 'https://radio.invalid/rock' 'Heavy Metal' || fail label
for ((i=1; i<=25; i++)); do history_record "Radio $i" "https://radio.invalid/$i" || fail history; done
history_load
[[ ${#HISTORY_URLS[@]} == 20 && "${HISTORY_NAMES[0]}" == 'Radio 25' ]] || fail 'limite y orden'
history_record 'Radio 10' 'https://radio.invalid/10' || fail dedup
[[ ${#HISTORY_URLS[@]} == 20 && "${HISTORY_NAMES[0]}" == 'Radio 10' ]] || fail 'reciente único'
favorites_add 'Radio 10' 'https://radio.invalid/10' || fail add
history_recent_refresh
[[ " ${RECENT_URLS[*]} " != *' https://radio.invalid/10 '* ]] || fail 'favorito en recientes'
favorites_remove_index 2 || fail remove
history_recent_refresh
[[ "${RECENT_URLS[0]}" == 'https://radio.invalid/10' ]] || fail 'historial reaparece'
HISTORY_PENDING_URL='https://radio.invalid/fail'
PLAYER_URL=$HISTORY_PENDING_URL PLAYER_NAME='Fallida' PLAYER_STREAM_READY=0
history_observe && fail 'guardó antes de audio'
[[ "${HISTORY_NAMES[0]}" == 'Radio 10' ]] || fail 'historial fallido'
PLAYER_STREAM_READY=1
history_observe || fail 'no guardó audio'
[[ "${HISTORY_NAMES[0]}" == Fallida && -z "$HISTORY_PENDING_URL" ]] || fail 'observación'
[[ "$(stat -c %a "$KEILA_STATE_DIR/history")" == 600 ]] || fail 'permisos historial'

# Escritura fallida debe conservar tanto memoria como archivo.
mv() {
    case "${*: -1}" in
        */labels|*/history) return 1 ;;
        *) command mv "$@" ;;
    esac
}
labels_set 'https://radio.invalid/rock' 'No guardada' && fail 'guardado falso'
[[ "${FAVORITE_LABELS[https://radio.invalid/rock]}" == 'Heavy Metal' ]] || fail 'rollback etiqueta'
history_record 'No guardada' 'https://radio.invalid/no' && fail 'historial falso'
[[ "${HISTORY_NAMES[0]}" == Fallida ]] || fail 'rollback historial'
unset -f mv

# Navegación compartida y selección de recientes sin modificar los presets.
player_is_running() { return 1; }
UI_UNICODE=1 UI_COLOR=0 UI_SELECTED_INDEX=2 UI_SCROLL_OFFSET=0
ui_configure_glyphs
ui_navigation_refresh
ui_navigation_sync 6
ui_navigation_row "$UI_NAV_FAVORITES_HEIGHT"
[[ "$UI_NAV_TEXT" == RECIENTES* ]] || fail 'cabecera recientes'
ui_navigation_row "$((UI_NAV_FAVORITES_HEIGHT + 1))"
[[ "$UI_NAV_TEXT" == *Fallida && "$UI_NAV_SELECTED" == 1 ]] || fail 'selección reciente'
ui_navigation_sync 1
ui_navigation_row 0
[[ "$UI_NAV_TEXT" == *Fallida && "$UI_NAV_SELECTED" == 1 ]] || fail 'reciente en una sola fila'
app_play() { TEST_PLAY_URL="$2"; }
app_play_selected || fail play
[[ "$TEST_PLAY_URL" == 'https://radio.invalid/fail' ]] || fail 'reproduce reciente'
app_remove_selected_favorite && fail 'borró favorito desde reciente'
[[ ${#FAVORITE_URLS[@]} == 2 ]] || fail 'favoritos alterados'

# Editor: texto literal, cancelar, guardar, borrar y teclas de comandos como texto.
ui_draw() { :; }
UI_SELECTED_INDEX=1
TEST_INPUT=0
input_read() {
    ((TEST_INPUT+=1))
    case "$TEST_INPUT" in
        1) INPUT_EVENT=KEY INPUT_KEY=$'\x15' ;;
        2) INPUT_EVENT=KEY INPUT_KEY=Q ;;
        3) INPUT_EVENT=ESC ;;
        *) return 1 ;;
    esac
}
app_edit_label || fail editor
[[ "${FAVORITE_LABELS[https://radio.invalid/rock]}" == 'Heavy Metal' ]] || fail 'cancelar etiqueta'
TEST_INPUT=0
input_read() {
    ((TEST_INPUT+=1))
    case "$TEST_INPUT" in
        1) INPUT_EVENT=KEY INPUT_KEY=$'\x15' ;;
        2) INPUT_EVENT=KEY INPUT_KEY=Q ;;
        3) INPUT_EVENT=ENTER ;;
        *) return 1 ;;
    esac
}
app_edit_label || fail 'guardar editor'
[[ "${FAVORITE_LABELS[https://radio.invalid/rock]}" == Q && "$LABEL_EDITOR_ACTIVE" == 0 ]] || fail 'Q texto'
labels_set 'https://radio.invalid/rock' '' || fail clear
[[ -z "${FAVORITE_LABELS[https://radio.invalid/rock]:-}" ]] || fail 'borrar etiqueta'
labels_set 'https://radio.invalid/rock' 'Heavy Metal' || fail label
SEARCH_URLS=('https://radio.invalid/rock') SEARCH_INDEX_TEXTS=('rock fm españa') SEARCH_QUERY='heavy metal'
search_filter
[[ ${#SEARCH_MATCHES[@]} == 1 ]] || fail 'buscar etiqueta'
printf 'ok   etiquetas, historial, navegación y editor\n'
