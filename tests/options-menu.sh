#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT

DRAW_CALLS=0
VISUAL_CALLS=0
ALARM_CALLS=0
PENDING_CALLS=0
SESSION_CALLS=0

ui_draw() { ((DRAW_CALLS += 1)); }
ui_refresh_size() { UI_COLS=80 UI_LINES=24; }
tput() { :; }
app_poll_player() { return 1; }
catalog_poll() { return 1; }
ui_message_tick() { return 1; }
app_preferences_menu() {
    [[ "${1:-}" == settings ]] && ((VISUAL_CALLS += 1))
}
app_edit_alarm() { ((ALARM_CALLS += 1)); }
app_pending_menu() { ((PENDING_CALLS += 1)); }
app_session_history_screen() { ((SESSION_CALLS += 1)); }
app_status_screen() { :; }

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=G ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$PENDING_CALLS" 'G no abre grabaciones desde opciones'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=S ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$SESSION_CALLS" 'S no abre historial de sesión desde opciones'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=T ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$ALARM_CALLS" 'T no abre temporizador/alarma desde opciones'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
OPTIONS_SELECTED=0
app_options_menu >/dev/null
assert_eq 1 "$VISUAL_CALLS" 'Enter sobre Visualización no abre preferencias visuales'
assert_eq 0 "$OPTIONS_ACTIVE" 'opciones no libera foco al salir'
((DRAW_CALLS >= 3)) || fail 'opciones no repinta al volver'

printf 'ok   opciones: hub jerárquico para visualización, temporizador, sesión y grabaciones\n'
