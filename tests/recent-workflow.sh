#!/usr/bin/env bash
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'catalog_stop; rm -rf "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
config_load "$task_tmp/recordings"
favorites_init ''
favorites_load
favorites_add Base https://radio.invalid/base
for ((i=1; i<=12; i++)); do history_record "Radio $i" "https://radio.invalid/$i"; done
ui_select_recientes
app_handle_key X
favorites_find_url https://radio.invalid/12 >/dev/null || fail 'X no añade reciente'
((UI_SELECTED_INDEX == ${#FAVORITE_NAMES[@]})) || fail 'alta desplaza sección'
app_handle_key X
favorites_find_url https://radio.invalid/12 >/dev/null || fail 'borrado sin confirmar'
app_handle_key X
if favorites_find_url https://radio.invalid/12 >/dev/null; then fail 'borrado confirmado falla'; fi
((UI_SELECTED_INDEX == ${#FAVORITE_NAMES[@]})) || fail 'baja desplaza sección'
app_play() { PLAYED_URL="$2"; }
app_handle_key 0
[[ "$PLAYED_URL" == https://radio.invalid/3 ]] || fail '0 no reproduce décimo reciente'
ui_move_selection 1
app_play_selected
[[ "$PLAYED_URL" == https://radio.invalid/2 ]] || fail 'cursor no alcanza undécimo reciente'
favorites_add Segunda https://radio.invalid/2
ui_select_recientes
UI_SELECTED_INDEX=$((${#FAVORITE_NAMES[@]} + 10))
PLAYER_URL=https://radio.invalid/2 PLAYER_NAME=Segunda PLAYER_STREAM_READY=1 HISTORY_PENDING_URL=$PLAYER_URL
history_observe
((UI_SELECTED_INDEX == ${#FAVORITE_NAMES[@]})) || fail 'historial mueve foco a favoritas'
[[ "${RECENT_URLS[0]}" == https://radio.invalid/2 ]] || fail 'historial no se reordena'
printf 'ok   flujo de recientes, confirmación, presets y foco\n'
