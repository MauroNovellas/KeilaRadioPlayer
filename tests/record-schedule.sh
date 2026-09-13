#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Reloj y audio simulados: sin red, esperas, archivos personales ni altavoces.
# END lo asigna record_plan_arm en el módulo cargado.
# shellcheck disable=SC2153
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
export TZ=UTC
unset EPOCHSECONDS
EPOCHSECONDS=1800000000
FAVORITE_NAMES=() FAVORITE_URLS=()
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
state() { [[ "$RECORD_PLAN_STATE" == "$1" ]] || fail "$2: $RECORD_PLAN_STATE != $1"; }
app_message() { UI_MESSAGE=$1; }
player_is_running() { ((RUNNING)); }
player_stop() { STOPS=$((STOPS+1)); STOP_ACTIVE=$RECORDING_ACTIVE; RUNNING=0 PLAYER_PID=''; }
pending_preview_stop() { :; }
spectrum_stop() { :; }
app_play() {
    PLAYS=$((PLAYS+1))
    [[ ${PLAYER_PRESERVE_MUTE:-0} == 1 && ${RECORD_PLAN_LAUNCHING:-0} == 1 ]] || fail 'inicio sin protección de silencio'
    record_plan_manual_play
    ((PLAY_OK)) || return 1
    PLAYER_NAME=$1 PLAYER_URL=$2 PLAYER_PID=123 RUNNING=1 PLAYER_PAUSED=0 PLAYER_STREAM_READY=0
}
recording_start() {
    STARTS=$((STARTS+1))
    ((START_OK)) || return 1
    RECORDING_ACTIVE=1 RECORDING_FILE=/simulada/reserva.ts RECORDING_PHASE=preparing
    RECORDING_LAST_ERROR='' RECORDING_LAST_VERIFIED=0
}
recording_stop() {
    CLOSES=$((CLOSES+1))
    if [[ $CLOSE_MODE == pending || $CLOSE_MODE == force && $RUNNING == 1 ]]; then
        RECORDING_LAST_ERROR='Cierre pendiente'; return 2
    fi
    RECORDING_ACTIVE=0 RECORDING_PHASE=idle RECORDING_LAST_ERROR='' RECORDING_LAST_VERIFIED=1
    if [[ $CLOSE_MODE == failed ]]; then
        RECORDING_LAST_ERROR='No se verificó audio'; RECORDING_LAST_VERIFIED=0; return 1
    fi
    return 0
}
reset_case() {
    RECORD_PLAN_STATE=idle RECORD_PLAN_FILE='' RECORD_PLAN_PID='' RECORD_PLAN_NOTE=''
    RECORD_PLAN_CHECK_AT=0 RECORD_PLAN_RESULT='done'
    PLAYER_PID=123 PLAYER_URL=https://otra.invalid/ PLAYER_PAUSED=0 PLAYER_MUTED=1 PLAYER_VOLUME=37
    PLAYER_STREAM_READY=0 PLAYER_BUFFERING=0 RECORDING_ACTIVE=0 RECORDING_FILE='' RECORDING_PHASE=idle
    RECORDING_LAST_ERROR='' RECORDING_LAST_VERIFIED=0
    RUNNING=1 PLAY_OK=1 START_OK=1 CLOSE_MODE=ok
    PLAYS=0 STARTS=0 CLOSES=0 STOPS=0
    ALARM_AT=0 SLEEP_TIMER_AT=0 PENDING_PREVIEW_PID='' BACKUP_DATA_BUSY=0
    app_reconnect_reset
    record_plan_arm Radio https://radio.invalid/ "$((EPOCHSECONDS+60))" "$((EPOCHSECONDS+180))" "$EPOCHSECONDS" "${1:-0}" || fail armar
}
due() { EPOCHSECONDS=$RECORD_PLAN_AT; record_plan_tick || fail inicio; }
ready() { PLAYER_STREAM_READY=1; record_plan_tick || fail preparar; }

now=$(date -d '2026-09-13 12:00:00' +%s)
record_plan_prepare Radio https://radio.invalid/ 12:01 003 "$now" || fail preparar
((RECORD_PLAN_DRAFT_AT == now+60 && RECORD_PLAN_DRAFT_END == now+240)) || fail cálculo
record_plan_prepare Radio https://radio.invalid/ 11:59 1440 "$now" || fail mañana
((RECORD_PLAN_DRAFT_AT == now+86340 && RECORD_PLAN_DRAFT_END-RECORD_PLAN_DRAFT_AT == 86400)) || fail 'fecha mañana'
for hour in '' 24:00 12:60 1:20 '$(id)' 1234; do
    record_plan_prepare Radio https://radio.invalid/ "$hour" 30 "$now" && fail "hora $hour"
done
for minutes in 0 1441 -1 10000 '1+1' '$(id)' ''; do
    record_plan_prepare Radio https://radio.invalid/ 13:00 "$minutes" "$now" && fail "minutos $minutes"
done
record_plan_prepare Radio 'file:///tmp/audio' 13:00 30 "$now" && fail 'URL local'
record_plan_prepare $'Radio\ncontrol' https://radio.invalid/ 13:00 30 "$now" && fail 'nombre con controles'

reset_case
saved=$RECORD_PLAN_AT
record_plan_arm Radio https://radio.invalid/ "$EPOCHSECONDS" "$((EPOCHSECONDS+60))" && fail 'confirmación caducada'
[[ $RECORD_PLAN_AT == "$saved" ]] || fail 'error destruye reserva'
record_plan_tick && fail prematuro
due; state connecting conectar
((PLAYS == 1 && STARTS == 0 && PLAYER_MUTED == 1 && PLAYER_VOLUME == 37)) || fail 'inicio anticipado o volumen'
record_plan_tick && fail 'sin audio crea fichero'
PLAYER_STREAM_READY=1 PLAYER_BUFFERING=1
record_plan_tick && fail 'buffering inicia fichero'
PLAYER_BUFFERING=0; ready; state preparing preparación
record_plan_arm Radio https://radio.invalid/ "$((EPOCHSECONDS+60))" "$((EPOCHSECONDS+120))" && fail 'sustituye grabación en curso'
record_plan_tick && fail 'declara grabando sin datos'
RECORDING_PHASE=recording
record_plan_tick || fail datos; state recording grabando
record_plan_tick && fail 'duplica inicio'
((STARTS == 1 && CLOSES == 0)) || fail repetición
EPOCHSECONDS=$RECORD_PLAN_END
record_plan_tick || fail finalizar; state 'done' finalizada
((CLOSES == 1 && STOPS == 0 && RUNNING == 1)) || fail 'fin apaga radio'
record_plan_tick && fail 'repite cierre'

# Reusar la misma emisora no la interrumpe; una pausada sí necesita arranque.
reset_case; PLAYER_URL=$RECORD_PLAN_URL PLAYER_STREAM_READY=1; due; ready
((PLAYS == 0 && STARTS == 1)) || fail 'reinicia emisora sana'
reset_case; PLAYER_URL=$RECORD_PLAN_URL PLAYER_PAUSED=1; due
((PLAYS == 1 && PLAYER_PAUSED == 0)) || fail 'no reanuda'
reset_case; RECORDING_ACTIVE=1; due; state skipped 'grabación manual prioritaria'
((PLAYS == 0 && STARTS == 0 && CLOSES == 0)) || fail 'toca manual'
reset_case; PENDING_PREVIEW_PID=999; due; state skipped escucha
reset_case; BACKUP_DATA_BUSY=1; due; state skipped restauración
reset_case; EPOCHSECONDS=$((RECORD_PLAN_AT+61)); record_plan_tick; state skipped suspensión
((PLAYS == 0)) || fail 'arranca tras suspensión tardía'
reset_case; EPOCHSECONDS=$((RECORD_PLAN_AT+60)); record_plan_tick; state connecting 'límite de tolerancia'
reset_case; PLAY_OK=0; due; state failed conexión
reset_case; due; EPOCHSECONDS=$RECORD_PLAN_CONNECT_UNTIL; record_plan_tick; state failed 'audio no llega'
((STARTS == 0 && APP_RECONNECT_ELIGIBLE == 0)) || fail 'graba sin audio'
reset_case; due; START_OK=0; ready; state failed 'no se reserva archivo'
reset_case; due; RECORDING_ACTIVE=1 RECORDING_FILE=/simulada/manual.ts
record_plan_tick; state skipped 'manual durante conexión'
((STARTS == 0 && CLOSES == 0)) || fail 'toca archivo manual'
reset_case; due; record_plan_manual_play; state cancelled 'selección manual durante conexión'
reset_case; due; PLAYER_URL=https://distinta.invalid/; record_plan_tick; state cancelled 'cambio de URL'

# Los conflictos tienen prioridad explícita, incluso después de suspensión.
reset_case; ALARM_AT=$RECORD_PLAN_AT; due; state skipped 'alarma simultánea'
((ALARM_AT > 0)) || fail 'pierde alarma'
reset_case; due; ALARM_AT=$EPOCHSECONDS; record_plan_tick; state skipped 'alarma al conectar'
reset_case; due; ready; ALARM_AT=$EPOCHSECONDS
alarm_tick || fail alarma; state preparing 'alarma interrumpe archivo'
((ALARM_AT == 0 && PLAYS == 1 && CLOSES == 0)) || fail 'alarma cambia emisora'
reset_case; record_plan_sleep_stop; state pending 'parada cancela reserva futura'
due; ready; SLEEP_TIMER_AT=$EPOCHSECONDS
sleep_timer_tick || fail parada; state cancelled 'parada gana'
((STOPS == 1 && CLOSES == 1)) || fail 'parada no cierra'

# Cancelación y cierres solo sobre la identidad exacta de nuestra grabación.
reset_case; record_plan_cancel; state cancelled 'cancelar pendiente'
((STOPS == 0 && CLOSES == 0)) || fail 'cancelar reserva detiene audio'
reset_case; due; ready; record_plan_cancel; state closing 'solicitar cancelación'
record_plan_tick; state cancelled 'cierre cancelado'
reset_case; due; ready; RECORDING_FILE=/simulada/otra.ts
EPOCHSECONDS=$RECORD_PLAN_END; record_plan_tick; state cancelled 'nuevo archivo'
((CLOSES == 0 && STOPS == 0)) || fail 'cierra otro archivo'
reset_case; due; ready; PLAYER_PID=999
record_plan_tick; state cancelled 'nuevo proceso'
((CLOSES == 0)) || fail 'cierra otro proceso'
reset_case; due; ready; CLOSE_MODE=pending; EPOCHSECONDS=$RECORD_PLAN_END
record_plan_tick; state closing 'cierre pendiente'
record_plan_tick && fail 'cierre no respeta cadencia'
((CLOSES == 1 && STOPS == 0)) || fail 'mata antes del plazo'
EPOCHSECONDS=$RECORD_PLAN_CLOSE_UNTIL; CLOSE_MODE=force
record_plan_tick; state 'done' 'cierre tras salida del reproductor'
((CLOSES == 3 && STOPS == 1)) || fail 'no verifica después de salir'
reset_case; due; ready; CLOSE_MODE=pending; EPOCHSECONDS=$RECORD_PLAN_END; record_plan_tick
EPOCHSECONDS=$RECORD_PLAN_CLOSE_UNTIL; record_plan_tick; state failed 'cierre no confirmado'
[[ $RECORD_PLAN_NOTE == *marcador* ]] || fail 'no avisa de archivo dudoso'
reset_case; due; ready; CLOSE_MODE=failed; EPOCHSECONDS=$RECORD_PLAN_END
record_plan_tick; state failed 'verificación fallida'
reset_case; due; ready; CLOSE_MODE=pending; EPOCHSECONDS=$RECORD_PLAN_END; record_plan_tick
# Otro tick del grabador termina el mismo cierre, no debe quedar cancelado.
CLOSE_MODE=ok; recording_stop; record_plan_tick; state 'done' 'cierre asíncrono'
reset_case; due; ready; RUNNING=0; record_plan_tick; state failed 'mpv terminó antes de tiempo'
[[ $RECORD_PLAN_NOTE == *incompleta* && $RECORD_PLAN_NOTE == *verificado* ]] || fail 'oculta interrupción de archivo reproducible'

# Parada optativa solo al final previsto y después del cierre del archivo.
reset_case
((RECORD_PLAN_STOP_AFTER == 0)) || fail 'parada activada por defecto'
for value in 2 -1 yes '1+1'; do
    record_plan_arm Radio https://radio.invalid/ "$RECORD_PLAN_AT" "$RECORD_PLAN_END" "$EPOCHSECONDS" "$value" && fail 'parada inválida'
    ((RECORD_PLAN_STOP_AFTER == 0)) || fail 'entrada inválida altera reserva'
done
reset_case 1; due; ready
APP_RECONNECT_ELIGIBLE=1 APP_RECONNECT_NEXT_AT=$((EPOCHSECONDS+30))
EPOCHSECONDS=$RECORD_PLAN_END; ALARM_AT=$((EPOCHSECONDS+60)) ALARM_LABEL=futura
record_plan_tick; state 'done' 'parada al final'
((STOPS == 1 && STOP_ACTIVE == 0 && CLOSES == 1 && RUNNING == 0)) || fail 'parada antes de cerrar o duplicada'
((APP_RECONNECT_ELIGIBLE == 0 && APP_RECONNECT_NEXT_AT == 0)) || fail 'reconexión tras parada'
[[ $ALARM_LABEL == futura && $PLAYER_MUTED == 1 && $PLAYER_VOLUME == 37 ]] || fail 'pierde alarma o volumen'
[[ $RECORD_PLAN_NOTE == *'Reproducción detenida'* ]] || fail 'falta aviso de parada'
record_plan_status
[[ $RECORD_PLAN_DETAIL == *'Al finalizar: Parar reproducción'* ]] || fail 'estado oculta opción'
record_plan_tick && fail 'repite parada'
reset_case 1; due; ready; EPOCHSECONDS=$RECORD_PLAN_END; ALARM_AT=$EPOCHSECONDS ALARM_LABEL=vencida
record_plan_tick
((ALARM_AT == 0)) || fail 'alarma vencida reactiva radio'
reset_case 1; due; ready; record_plan_cancel; record_plan_tick
state cancelled 'cancelación no activa parada'; ((STOPS == 0)) || fail 'cancelar apaga radio'
reset_case 1; record_plan_cancel; ((STOPS == 0)) || fail 'reserva cancelada apaga radio'
reset_case 1; due; ready; CLOSE_MODE=failed; EPOCHSECONDS=$RECORD_PLAN_END
record_plan_tick; state failed 'archivo dudoso con parada'
((STOPS == 1 && STOP_ACTIVE == 0)) || fail 'error de validación impide parada'
reset_case 1; due; ready; CLOSE_MODE=pending; EPOCHSECONDS=$RECORD_PLAN_END; record_plan_tick
((STOPS == 0)) || fail 'parada sin cerrar archivo'
CLOSE_MODE=ok; recording_stop; record_plan_tick
state 'done' 'cierre asíncrono con parada'; ((STOPS == 1)) || fail 'olvida parada asíncrona'
reset_case 1; due; ready; CLOSE_MODE=pending; EPOCHSECONDS=$RECORD_PLAN_END; record_plan_tick
EPOCHSECONDS=$RECORD_PLAN_CLOSE_UNTIL; ALARM_AT=$EPOCHSECONDS; CLOSE_MODE=force; record_plan_tick
((STOPS == 1)) || fail 'duplica parada forzada'
((ALARM_AT == 0)) || fail 'alarma vencida reactiva radio tras cierre forzado'
reset_case 1; due; ready; RECORDING_FILE=/simulada/manual.ts; EPOCHSECONDS=$RECORD_PLAN_END; record_plan_tick
((STOPS == 0 && CLOSES == 0)) || fail 'parada afecta otra grabación'
reset_case 1; due; ready; PLAYER_PID=999; EPOCHSECONDS=$RECORD_PLAN_END; record_plan_tick
((STOPS == 0)) || fail 'parada afecta otro proceso'
reset_case 1; due; ready; PENDING_PREVIEW_PID=999; EPOCHSECONDS=$RECORD_PLAN_END; record_plan_tick
((STOPS == 0)) || fail 'parada afecta otra escucha'
reset_case 1; RECORDING_ACTIVE=1; due; EPOCHSECONDS=$RECORD_PLAN_END; record_plan_tick || true
state skipped 'manual prioritaria con parada'; ((STOPS == 0)) || fail 'reserva omitida apaga radio'
reset_case 1; due; ready; RUNNING=0; record_plan_tick
((STOPS == 0 && RECORD_PLAN_END_REACHED == 0)) || fail 'fallo temprano dispara parada de fin'
printf 'ok   programación: reloj, conflictos, identidad, cierre y parada optativa simulados\n'
