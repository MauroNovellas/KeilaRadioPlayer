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
SEARCH_CALLS=0
PAUSE_CALLS=0

ui_draw() { ((DRAW_CALLS += 1)); }
ui_refresh_size() { UI_COLS=80 UI_LINES=24; }
tput() { :; }
app_poll_player() { return 1; }
catalog_poll() { return 1; }
ui_message_tick() { return 1; }
pending_scan_poll() { return 1; }
app_preferences_menu() {
    [[ "${1:-}" == settings ]] && ((VISUAL_CALLS += 1))
}
app_edit_alarm() { ((ALARM_CALLS += 1)); }
app_pending_menu() { ((PENDING_CALLS += 1)); }
app_session_history_screen() { ((SESSION_CALLS += 1)); }
app_status_screen() { :; }
app_search_catalog() { ((SEARCH_CALLS += 1)); }
app_toggle_pause() { ((PAUSE_CALLS += 1)); }

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=G ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=R ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$PENDING_CALLS" 'G > R no abre el gestor de grabaciones desde opciones'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=S ;;
        2) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$SESSION_CALLS" 'S > Enter no abre historial de sesión desde opciones'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=T ;;
        2) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$ALARM_CALLS" 'T > Enter no abre temporizador/alarma desde opciones'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=V ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=A ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
OPTIONS_SELECTED=0
app_options_menu >/dev/null
assert_eq 1 "$VISUAL_CALLS" 'V > A no abre preferencias visuales'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=E ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=B ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$SEARCH_CALLS" 'E > B no abre búsqueda de emisoras'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=ENTER ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=P ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
OPTIONS_SELECTED=0
app_options_menu >/dev/null
assert_eq 1 "$PAUSE_CALLS" 'Enter > P no ejecuta pausa desde reproducción'

assert_eq 0 "$OPTIONS_ACTIVE" 'opciones no libera foco al salir'
((DRAW_CALLS >= 3)) || fail 'opciones no repinta al volver'

printf 'ok   opciones: árbol jerárquico con reproducción, emisoras, sesión y configuración\n'
