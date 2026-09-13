#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
FAVORITE_NAMES=() FAVORITE_URLS=()
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
app_message() { UI_MESSAGE=$1; }
calls='' stops=0 closes=0 finalizes=0
player_stop() { calls+=P; stops=$((stops+1)); PLAYER_PID=''; }
pending_preview_stop() { [[ $PENDING_RADIO_RESUME == 0 ]] || fail 'reanuda radio al cerrar escucha'; calls+=E; }
spectrum_stop() { calls+=S; }
recording_stop() {
    calls+=R; closes=$((closes+1))
    if [[ -n $PLAYER_PID ]]; then RECORDING_LAST_ERROR='Cierre pendiente'; return 2; fi
    RECORDING_ACTIVE=0 RECORDING_LAST_ERROR=''; finalizes=$((finalizes+1))
}
now=$EPOCHSECONDS
sleep_timer_set 015 "$now" || fail programar
[[ $SLEEP_TIMER_AT == $((now+900)) ]] || fail minutos
saved=$SLEEP_TIMER_AT
for value in 0 -1 1441 10000 '1+1' '$(id)' '1.5' ' '; do
    sleep_timer_set "$value" && fail "acepta $value"
    [[ $SLEEP_TIMER_AT == "$saved" ]] || fail 'error destruye plazo anterior'
done
sleep_timer_tick && fail prematuro
sleep_timer_set '' || fail cancelar
((SLEEP_TIMER_AT == 0 && stops == 0)) || fail 'cancelar detiene audio'
sleep_timer_set 1440 "$now" || fail límite
SLEEP_TIMER_AT=$((EPOCHSECONDS-1)) ALARM_AT=$((EPOCHSECONDS+500)) ALARM_LABEL=futura
PLAYER_PID=123 PLAYER_VOLUME=43 PLAYER_MUTED=1 RECORDING_ACTIVE=1
APP_RECONNECT_ELIGIBLE=1 APP_RECONNECT_NEXT_AT=1
STATE_LAST_NAME=Guardada STATE_LAST_URL=https://radio.invalid
sleep_timer_tick || fail disparar
[[ $calls == ESRPR && $finalizes == 1 && $closes == 2 ]] || fail 'orden de cierre seguro'
[[ $ALARM_LABEL == futura && $PLAYER_VOLUME == 43 && $PLAYER_MUTED == 1 && $STATE_LAST_NAME == Guardada ]] || fail 'modifica preferencias o alarma futura'
((APP_RECONNECT_ELIGIBLE == 0 && APP_RECONNECT_NEXT_AT == 0 && SLEEP_TIMER_FINISHED == 1)) || fail 'reconexión sigue activa'
sleep_timer_tick && fail repetición
((stops == 1)) || fail duplicación
SLEEP_TIMER_AT=$((EPOCHSECONDS-1)) ALARM_AT=$((EPOCHSECONDS-1)) ALARM_LABEL=vencida
sleep_timer_tick || fail 'tras suspensión'
((ALARM_AT == 0)) || fail 'alarma vencida enciende después de parada'
# Verificación fallida no borra datos ni impide detener el audio.
recording_stop() { RECORDING_ACTIVE=0 RECORDING_LAST_ERROR='Requiere revisión'; return 1; }
SLEEP_TIMER_AT=$((EPOCHSECONDS-1)) RECORDING_ACTIVE=1
sleep_timer_tick || fail 'cierre dudoso'
[[ $UI_MESSAGE == *'conservada'* ]] || fail 'sin aviso de conservación'
# El punto de integración real despacha primero la parada, no la alarma.
alarm_tick() { calls+=A; return 0; }
calls='' SLEEP_TIMER_AT=$((EPOCHSECONDS-1)) RECORDING_ACTIVE=0
app_poll_player || fail 'integración del tick'
[[ $calls == ESP ]] || fail 'alarma se ejecuta antes de parada'
# Solo el menú del temporizador redibuja su cuenta atrás.
SLEEP_TIMER_AT=$((EPOCHSECONDS+3700)); sleep_timer_status
[[ $SLEEP_TIMER_STATUS == '01:01:'* ]] || fail 'formato de cuenta atrás'
options_build_rows sleep
[[ ${#OPTIONS_ROWS[@]} == 7 ]] || fail 'faltan opciones'
# Editor cancelable, con ticks atendidos y entrada numérica limitada.
ticks=0 event_i=0
station_field_draw() { :; }
panel_poll() { ticks=$((ticks+1)); return 1; }
input_read() {
    event_i=$((event_i+1)); INPUT_KEY=''
    case $event_i in 1) INPUT_EVENT=KEY; INPUT_KEY=9 ;; 2) INPUT_EVENT=TICK ;; 3) INPUT_EVENT=RESIZE ;; *) INPUT_EVENT=ESC ;; esac
}
saved=$SLEEP_TIMER_AT
app_edit_sleep_timer || fail editor
[[ $SLEEP_TIMER_AT == "$saved" && $ticks == 1 ]] || fail 'cancelación o polling'
input_read() { INPUT_EVENT=ENTER; INPUT_KEY=''; }
app_edit_sleep_timer
((SLEEP_TIMER_AT == 0)) || fail 'entrada vacía no cancela'
printf 'ok   parada: plazos, cancelación, disparo único, cierre, alarma y editor\n'
