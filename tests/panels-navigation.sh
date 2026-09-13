#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ui_refresh_size() { UI_COLS=40 UI_LINES=10; }
ui_draw() { :; }
tput() { :; }
app_poll_player() { ((polls+=1)); return 1; }
catalog_poll() { return 1; }
pending_scan_poll() { return 1; }
ui_message_tick() { return 1; }
FAVORITE_NAMES=() FAVORITE_URLS=()
polls=0

# Configuración: cambiar tamaño mientras se confirma no ejecuta ni cancela.
PREF_COLOR=0 PREF_AUTOPLAY=0
preferences_save || fail 'preparar ajustes'
events=0
input_read() {
    ((events+=1)); INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=END ;;
        2) INPUT_EVENT=ENTER ;;
        3) INPUT_EVENT=RESIZE ;;
        4) INPUT_EVENT=TICK ;;
        5) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_preferences_menu settings >/dev/null
[[ "$PREF_COLOR:$PREF_AUTOPLAY:$polls:$PREFERENCES_ACTIVE" == 1:1:1:0 ]] || fail 'resize rompe confirmación, sondeo o foco'

# Fallar al guardar desde el selector tampoco deja un estado engañoso.
preferences_save() { return 1; }
events=0
input_read() { ((events+=1)); INPUT_KEY=''; if ((events==1)); then INPUT_EVENT=ENTER; else INPUT_EVENT=ESC; fi; }
app_preferences_menu settings >/dev/null
[[ "$PREF_AUTOPLAY" == 1 ]] || fail 'guardado fallido altera ajuste'

# Reasignar teclas solo se hace desde configuración; Ayuda/Detalle son lectura.
events=0
input_read() {
    ((events+=1)); INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=ENTER ;;
        2) INPUT_EVENT=KEY INPUT_KEY=x ;;
        3) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_preferences_menu help >/dev/null
[[ "${PREF_KEYS[x]}:$PREF_AUTOPLAY" == x:1 ]] || fail 'la ayuda ejecuta o reasigna una acción'

# Una alarma inválida conserva la anterior y permite corregir el mismo campo.
alarm_set 23:59 || fail 'preparar alarma'
saved_alarm=$ALARM_AT
events=0
keys=(2 5 0 0)
input_read() {
    ((events+=1)); INPUT_KEY=''
    case "$events" in
        [1-4]) INPUT_EVENT=KEY INPUT_KEY=${keys[events-1]} ;;
        5) INPUT_EVENT=ENTER ;;
        6) [[ "$ALARM_AT" == "$saved_alarm" ]] || fail 'alarma inválida sustituye la anterior'; INPUT_EVENT=DELETE ;;
        7) INPUT_EVENT=KEY INPUT_KEY=0 ;;
        8) INPUT_EVENT=KEY INPUT_KEY=8 ;;
        9) INPUT_EVENT=RESIZE ;;
        10) INPUT_EVENT=KEY INPUT_KEY=4 ;;
        11) INPUT_EVENT=KEY INPUT_KEY=5 ;;
        *) INPUT_EVENT=ENTER ;;
    esac
}
app_edit_alarm >/dev/null
[[ "$ALARM_LABEL" == *08:45 && "$PREFERENCES_ACTIVE" == 0 ]] || fail 'se pierde edición de alarma o foco'

# Diagnóstico permite llegar a la última ruta en Termux y leerla completa.
STATUS_ROWS=()
for ((i=0;i<25;i++)); do STATUS_ROWS+=("Dato $i|Valor $i"); done
STATUS_ROWS+=('Ruta final|/ruta/completa/al/final')
status_build_rows() { :; }
events=0
input_read() {
    ((events+=1)); INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=END ;;
        2) [[ "$STATUS_SELECTED" == 25 ]] || fail 'no llega al final del diagnóstico'; INPUT_EVENT=ENTER ;;
        3) INPUT_EVENT=ESC ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
PREFERENCES_ACTIVE=1
app_status_screen >/dev/null
[[ "$STATUS_SELECTED:$PREFERENCES_ACTIVE" == 25:1 ]] || fail 'diagnóstico pierde selección o foco padre'

# El historial no relee el archivo en cada tick y sigue el final únicamente
# cuando el lector ya estaba allí.
SESSION_LOG_FILE="$task_tmp/session.txt"
printf '2026-09-12 10:00:00\tRadio\tUno\n' > "$SESSION_LOG_FILE"
SESSION_HISTORY_SIGNATURE='' SESSION_HISTORY_CHECK_AT=0 SESSION_HISTORY_ROWS=()
session_history_refresh || fail 'cargar sesión'
[[ "${#SESSION_HISTORY_ROWS[@]}" == 1 ]] || fail 'no carga sesión'
session_history_refresh && fail 'relee sesión sin cambios'
printf '2026-09-12 10:01:00\tRadio\tDos\n' >> "$SESSION_LOG_FILE"
SESSION_HISTORY_CHECK_AT=0
session_history_refresh || fail 'no detecta canción nueva'
[[ "$SESSION_HISTORY_SELECTED" == 1 ]] || fail 'no sigue al final'
SESSION_HISTORY_SELECTED=0
printf '2026-09-12 10:02:00\tRadio\tTres\n' >> "$SESSION_LOG_FILE"
SESSION_HISTORY_CHECK_AT=0
session_history_refresh || fail 'no detecta otra canción'
[[ "$SESSION_HISTORY_SELECTED" == 0 ]] || fail 'mueve al usuario que lee entradas antiguas'

printf 'ok   submenús: confirmaciones, lectura, guardado fallido, alarma, scroll y refresco de sesión\n'
