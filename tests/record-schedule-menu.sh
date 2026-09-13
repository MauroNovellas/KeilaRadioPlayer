#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
FAVORITE_NAMES=('Radio Uno' 'Radio Dos') FAVORITE_URLS=(https://uno.invalid/ https://dos.invalid/)
UI_COLS=80 UI_LINES=24 INPUT_KEY=''
events=() keys=() event_i=0 ticks=0 details=0
input_read() {
    ((event_i < ${#events[@]})) || fail 'bucle sin salida'
    INPUT_EVENT=${events[event_i]} INPUT_KEY=${keys[event_i]:-}
    event_i=$((event_i+1))
}
feed() { event_i=0; events=("$@"); keys=(); }
panel_poll() { ticks=$((ticks+1)); return 1; }
panel_draw() { PANEL_VISIBLE=3; }
station_field_draw() { :; }
app_message() { UI_MESSAGE=$1; }
app_play() { fail 'el selector reproduce sin programar'; }
panel_detail() { details=$((details+1)); [[ ${PANEL_ROWS[0]} == *Confirmar* ]] || fail 'detalle ajeno'; }

feed KEY KEY TICK RESIZE KEY KEY ENTER
keys=(1 2 '' '' 3 4 '')
record_plan_field_edit hour '' || fail hora
[[ $RECORD_PLAN_FIELD == 12:34 && $ticks == 1 ]] || fail 'auto dos puntos o polling'
feed KEY KEY ENTER; keys=($'\x7f' 3 '')
record_plan_field_edit hour '12:' || fail retroceso
[[ $RECORD_PLAN_FIELD == '13:' ]] || fail 'retroceso atasca dos puntos'
feed DELETE KEY KEY ENTER; keys=('' 0 9 '')
record_plan_field_edit hour '12:34'
[[ $RECORD_PLAN_FIELD == '09:' ]] || fail borrar
feed KEY KEY ENTER; keys=(9 9 '')
record_plan_field_edit minutes 1440
[[ $RECORD_PLAN_FIELD == 1440 ]] || fail 'duración sin límite de entrada'
feed ESC
record_plan_field_edit hour '12:34' && fail 'Esc acepta campo'

feed DOWN ENTER
app_record_plan_station || fail seleccionar
[[ $RECORD_PLAN_PICK_NAME == 'Radio Dos' && $RECORD_PLAN_PICK_URL == https://dos.invalid/ ]] || fail 'selector incorrecto'
feed ENTER ESC; UI_COLS=8
app_record_plan_station && fail 'confirma emisora en terminal ilegible'
UI_COLS=80
saved=$((EPOCHSECONDS+3600)) end=$((EPOCHSECONDS+7200))
record_plan_arm 'Radio Uno' https://uno.invalid/ "$saved" "$end" || fail armar
feed KEY ESC; keys=(h '')
# Escape del editor y luego del formulario.
events+=(ESC)
app_edit_record_plan && fail 'Escape guarda borrador'
[[ $RECORD_PLAN_AT == "$saved" && $RECORD_PLAN_NAME == 'Radio Uno' ]] || fail 'borrador modifica reserva'
feed ESC
app_record_plan_confirm arm 'Radio Dos' https://dos.invalid/ "$saved" "$end" 'Horario exacto' && fail 'revisión Esc'
[[ $RECORD_PLAN_NAME == 'Radio Uno' ]] || fail 'revisión guarda sin confirmar'
feed KEY ENTER; keys=('?' '')
app_record_plan_confirm arm 'Radio Dos' https://dos.invalid/ "$saved" "$end" 'Horario exacto' || fail confirmar
[[ $RECORD_PLAN_NAME == 'Radio Dos' && $details == 1 ]] || fail 'confirmación o detalle completo'
feed ENTER ESC
app_record_plan_confirm arm 'Radio Uno' https://uno.invalid/ "$((EPOCHSECONDS-60))" "$end" 'Caducado' && fail 'confirmación caducada'
[[ $RECORD_PLAN_NAME == 'Radio Dos' ]] || fail 'caducada cambia reserva'
feed ENTER ESC; UI_LINES=5
app_record_plan_confirm cancel && fail 'confirmación terminal ilegible'
[[ $RECORD_PLAN_STATE == pending ]] || fail 'cancela sin poder leer'
UI_LINES=24
feed TICK ENTER
panel_poll() { RECORD_PLAN_STATE=connecting; return 0; }
app_record_plan_confirm cancel && fail 'confirmación obsoleta detiene grabación iniciada'
[[ $RECORD_PLAN_STATE == connecting ]] || fail 'cancela estado distinto'
RECORD_PLAN_STATE=pending
feed ENTER
app_record_plan_confirm cancel || fail cancelar
[[ $RECORD_PLAN_STATE == cancelled ]] || fail 'no cancela'
# La opción se edita en borrador, queda en la revisión y admite cursores/Enter.
panel_poll() { return 1; }
record_plan_arm 'Radio Uno' https://uno.invalid/ "$saved" "$end" || fail armar
feed KEY ESC; keys=(p '')
app_edit_record_plan && fail 'borrador aceptado con Esc'
((RECORD_PLAN_STOP_AFTER == 0)) || fail 'toggle guarda antes de confirmar'
feed KEY KEY ENTER; keys=(p g '')
app_edit_record_plan || fail 'confirmar opción de parada'
((RECORD_PLAN_STOP_AFTER == 1)) || fail 'pierde parada al confirmar'
feed KEY ENTER; keys=(g '')
app_edit_record_plan || fail 'reeditar reserva'
((RECORD_PLAN_STOP_AFTER == 1)) || fail 'edición no precarga parada anterior'
feed DOWN DOWN DOWN ENTER END ENTER ENTER
app_edit_record_plan || fail 'navegación de nueva fila'
((RECORD_PLAN_STOP_AFTER == 0)) || fail 'Enter no alterna parada'
feed ESC
app_record_plan_confirm arm 'Radio Dos' https://dos.invalid/ "$saved" "$end" 'Horario exacto' 1 && fail 'Esc confirma parada'
((RECORD_PLAN_STOP_AFTER == 0)) || fail 'revisión cancelada altera parada'
RECORD_PLAN_STATE=cancelled
options_build_rows record_plan
[[ ${#OPTIONS_ROWS[@]} == 3 ]] || fail 'menú incompleto'
options_action_reason plan_cancel
[[ -n $OPTIONS_REASON ]] || fail 'cancelación habilitada sin reserva'
FAVORITE_NAMES=() FAVORITE_URLS=()
options_action_reason plan_edit
[[ -n $OPTIONS_REASON ]] || fail 'editor habilitado sin emisoras'
printf 'ok   programación UI: campos, selección, borrador, revisión, caducidad y terminal pequeña\n'
