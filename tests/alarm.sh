#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/alarm.sh"
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
app_message() { MESSAGE=$1; }
player_is_running() { return 0; }
player_ipc() { COMMAND=$1; return "${IPC_STATUS:-0}"; }
app_play() { PLAY_NAME=$1; PLAY_URL=$2; ((CALLS+=1)); return 0; }
export TZ=UTC
now=$(date -d '2026-09-08 10:00:00' +%s)
alarm_set 11:00 "$now" || fail programar
[[ "$ALARM_AT" == "$(date -d '2026-09-08 11:00:00' +%s)" ]] || fail hoy
alarm_set 09:00 "$now" || fail mañana
[[ "$ALARM_AT" == "$(date -d '2026-09-09 09:00:00' +%s)" ]] || fail mañana
saved=$ALARM_AT
alarm_set 25:99 "$now" && fail 'hora inválida aceptada'
[[ "$ALARM_AT" == "$saved" ]] || fail 'hora inválida destruye alarma'
alarm_set '' || fail cancelar
((ALARM_AT == 0)) || fail cancelar
PLAYER_VOLUME=35
app_toggle_mute || fail mute
((PLAYER_MUTED == 1 && PLAYER_VOLUME == 35)) || fail volumen
IPC_STATUS=1
app_toggle_mute && fail 'IPC fallido aceptado'
((PLAYER_MUTED == 1)) || fail 'estado falso tras fallo'
IPC_STATUS=0
app_toggle_mute || fail unmute
((PLAYER_MUTED == 0 && PLAYER_VOLUME == 35)) || fail restaurar
HISTORY_NAMES=('Última real') HISTORY_URLS=('https://example.invalid/last')
CALLS=0 ALARM_AT=$((EPOCHSECONDS-1))
alarm_tick || fail disparar
[[ "$PLAY_URL" == https://example.invalid/last ]] || fail emisora
alarm_tick && fail repetición
((CALLS == 1 && ALARM_AT == 0)) || fail 'alarma duplicada'
ui_draw() { :; }
ui_clear_message() { MESSAGE=''; }
alarm_set 23:59 || fail configurar
saved=$ALARM_AT
# Stub llamado indirectamente por el editor.
# shellcheck disable=SC2317
input_read() { INPUT_EVENT=ESC; }
app_edit_alarm || fail editor
[[ "$ALARM_AT" == "$saved" ]] || fail 'Esc cancela alarma existente'
# shellcheck disable=SC2317
input_read() { INPUT_EVENT=ENTER; }
app_edit_alarm || fail 'cancelar en editor'
((ALARM_AT == 0)) || fail 'Enter vacío no cancela'
# Dos puntos automáticos y borrado: 12: -> borrar -> 1 -> 13:45.
keys=(1 2 $'\x7f' 3 4 5)
idx=0
input_read() {
    if ((idx < ${#keys[@]})); then INPUT_EVENT=KEY; INPUT_KEY=${keys[idx]}; ((idx+=1)); else INPUT_EVENT=ENTER; fi
}
app_edit_alarm || fail 'edición HHMM con borrado'
[[ "$ALARM_LABEL" == *13:45 ]] || fail 'hora incorrecta después de borrar separador'
printf 'ok   alarma: horarios, cancelación, disparo único y mute con fallo IPC\n'
