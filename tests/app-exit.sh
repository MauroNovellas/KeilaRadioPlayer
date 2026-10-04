#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
export KEILA_NO_UPDATE_CHECK=1
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

panel_draw() {
    [[ ${PANEL_ROWS[0]} == 'N|Seguir escuchando|'* && ${PANEL_ROWS[1]} == 'S|Salir|'* ]] || fail 'orden inseguro de opciones'
    [[ $PREFERENCES_ACTIVE == 1 && $SEARCH_ACTIVE == 0 ]] || fail 'foco de confirmación'
    [[ $PANEL_FORM == 0 && $PANEL_FULL_WIDTH == 0 ]] || fail 'hereda formato del editor'
    printf 'DRAW:%s:%s\n' "$2" "$5"
    PANEL_SELECTED=$2 PANEL_SCROLL=$3 PANEL_VISIBLE=1
    ((draws+=1))
}
panel_poll() { ((polls+=1)); RECORDING_ACTIVE=1; return 0; }
input_read() {
    ((event_index < ${#events[@]})) || return 1
    local next=${events[event_index++]}
    INPUT_KEY='' INPUT_REPEAT_COUNT=1
    INPUT_EVENT=${next%%:*}
    [[ $next != KEY:* ]] || INPUT_KEY=${next#KEY:}
}
dialog() {
    events=("$@") event_index=0 draws=0 polls=0 RECORDING_ACTIVE=0
    local status=0
    app_confirm_exit > "$task_tmp/dialog" || status=$?
    [[ $PREFERENCES_ACTIVE == 1 && $SEARCH_ACTIVE == 1 ]] || fail 'se pierde foco del padre'
    [[ $PANEL_SELECTED == 7 && $PANEL_SCROLL == 4 && $PANEL_PARENT_PATH == PADRE ]] || fail 'se altera selección del padre'
    [[ $PANEL_FORM == 1 && $PANEL_FULL_WIDTH == 1 ]] || fail 'se pierde formato del editor padre'
    return "$status"
}
PREFERENCES_ACTIVE=1 SEARCH_ACTIVE=1 PANEL_SELECTED=7 PANEL_SCROLL=4 PANEL_PARENT_PATH=PADRE
PANEL_FORM=1 PANEL_FULL_WIDTH=1
dialog ENTER && fail 'Enter inicial cierra'
dialog ESC && fail 'Esc cierra'
dialog LEFT && fail 'izquierda cierra'
dialog KEY:n && fail 'N cierra'
dialog && fail 'EOF confirma'
dialog KEY:q KEY:Q ENTER && fail 'Q repetida cierra'
dialog KEY:s || fail 'S no confirma'
dialog DOWN RESIZE ENTER || fail 'resize pierde selección explícita'
dialog END UP ENTER && fail 'subir no vuelve a cancelar'
dialog TICK RESIZE KEY:n && fail 'tick cierra'
[[ $polls == 1 && $draws == 3 ]] || fail 'no se atiende audio/redibujado'
[[ $(< "$task_tmp/dialog") == *'grabación en curso'* ]] || fail 'no avisa de grabación iniciada mientras se decide'
RECORD_PLAN_STATE=pending
dialog KEY:n || true
[[ $(< "$task_tmp/dialog") == *'grabación programada'* ]] || fail 'falta aviso de reserva'
RECORD_PLAN_STATE=idle ALARM_AT=1
dialog KEY:n || true
[[ $(< "$task_tmp/dialog") == *'alarma temporal'* ]] || fail 'falta aviso de alarma'
ALARM_AT=0

# La salida normal y las solicitudes procedentes de pantallas hijas convergen
# en el mismo cuadro; cancelar vuelve a dibujar la TUI, sin otra despedida.
input_init() { :; }
ui_enter() { :; }
ui_startup_splash() { ((splashes+=1)); }
catalog_start() { :; }
pending_scan_start() { :; }
ui_draw() { ((main_draws+=1)); }
favorites_confirm_clear() { :; }
splashes=0 main_draws=0 event_index=0 draws=0
PREF_KEYS['q']=e
events=(KEY:e ENTER KEY:e KEY:s)
app_loop > "$task_tmp/loop" || fail 'bucle principal'
[[ $main_draws == 2 && $splashes == 1 && $event_index == 4 ]] || fail 'confirmación de tecla personalizada'
app_options_menu() { return 2; }
events=(KEY:o ENTER KEY:o KEY:s) event_index=0 main_draws=0
app_loop > "$task_tmp/loop" || fail 'salida desde submenú'
[[ $main_draws == 2 && $event_index == 4 ]] || fail 'submenú evita la confirmación'

# No convertir los escapes finales en salida silenciada. Dobles de limpieza:
# esta prueba no toca procesos, archivos ni sockets personales.
quality_cleanup() { :; }
search_async_cleanup() { :; }
logo_cleanup() { :; }
m3u_cleanup() { :; }
backup_manager_cleanup() { :; }
session_log_close() { :; }
pending_cleanup() { :; }
spectrum_stop() { :; }
catalog_stop() { :; }
recording_stop() { :; }
input_shutdown() { :; }
player_stop() { :; }
ui_leave() { printf 'TERMINAL-LIMPIO'; }
cleanup > "$task_tmp/cleanup"
[[ $(< "$task_tmp/cleanup") == TERMINAL-LIMPIO ]] || fail 'limpieza enviada a /dev/null'
[[ $("$ROOT_DIR/keila-radio" --version) == "Keila Radio Player $KEILA_VERSION" ]] || fail 'CLI muestra TUI/perro'
printf 'ok   salida: cancelación inicial, confirmación, resize, ticks, foco y limpieza visible\n'
