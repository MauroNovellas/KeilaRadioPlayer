#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

FAVORITE_NAMES=('Emisora uno' 'Emisora dos')
FAVORITE_URLS=('https://radio.invalid/1' 'https://radio.invalid/2')
RECENT_NAMES=('Reciente uno')
RECENT_URLS=('https://radio.invalid/recent')
UI_SELECTED_INDEX=1
ui_sync_selection() { :; }
history_recent_refresh() { :; }

EDIT_CALLS=0
RECORDING_CALLS=0
app_edit_label() { ((EDIT_CALLS += 1)); }
app_toggle_recording() { ((RECORDING_CALLS += 1)); }

app_handle_key E || fail 'E no se procesó'
((UI_SELECTED_INDEX == 0)) || fail 'E no selecciona la primera emisora'

app_handle_key R || fail 'R no se procesó'
((UI_SELECTED_INDEX == 2)) || fail 'R no selecciona el primer reciente'

app_handle_key C || fail 'C no se procesó'
((EDIT_CALLS == 1)) || fail 'C no abre el editor de comentarios'

app_handle_key G || fail 'G no se procesó'
((RECORDING_CALLS == 1)) || fail 'G no alterna la grabación'

printf 'ok   atajos de emisoras, comentarios, recientes y grabación\n'
