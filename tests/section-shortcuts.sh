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
STATUS_CALLS=0
OPTIONS_CALLS=0
app_edit_label() { ((EDIT_CALLS += 1)); }
app_toggle_recording() { ((RECORDING_CALLS += 1)); }
app_status_screen() { ((STATUS_CALLS += 1)); }
app_options_menu() { ((OPTIONS_CALLS += 1)); }

app_handle_key F || fail 'F no se procesó'
((UI_SELECTED_INDEX == 0)) || fail 'F no selecciona la primera favorita'

app_handle_key R || fail 'R no se procesó'
((UI_SELECTED_INDEX == 2)) || fail 'R no selecciona el primer reciente'

app_handle_key C || fail 'C no se procesó'
((EDIT_CALLS == 1)) || fail 'C no abre el editor de comentarios'

app_handle_key G || fail 'G no se procesó'
((RECORDING_CALLS == 1)) || fail 'G no alterna la grabación'

app_handle_key D || fail 'D no se procesó'
((STATUS_CALLS == 1)) || fail 'D no abre diagnóstico'

app_handle_key O || fail 'O no se procesó'
((OPTIONS_CALLS == 1)) || fail 'O no abre opciones'

printf 'ok   atajos de emisoras, comentarios, recientes, grabación, diagnóstico y opciones\n'
