#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Una programación en memoria; no cron, tareas del sistema ni fichero ejecutable.
RECORD_PLAN_STATE=idle RECORD_PLAN_AT=0 RECORD_PLAN_END=0
RECORD_PLAN_NAME='' RECORD_PLAN_URL='' RECORD_PLAN_FILE='' RECORD_PLAN_PID=''
RECORD_PLAN_LABEL='' RECORD_PLAN_NOTE='' RECORD_PLAN_ERROR=''
RECORD_PLAN_CONNECT_UNTIL=0 RECORD_PLAN_CLOSE_UNTIL=0 RECORD_PLAN_CHECK_AT=0
RECORD_PLAN_RESULT='done'
RECORD_PLAN_END_REASON=''
RECORD_PLAN_STOP_AFTER=0 RECORD_PLAN_END_REACHED=0

record_plan_after_label() {
    RECORD_PLAN_AFTER_LABEL='Seguir escuchando'
    [[ $1 != 1 ]] || RECORD_PLAN_AFTER_LABEL='Parar reproducción'
}

record_plan_busy() {
    case "$RECORD_PLAN_STATE" in connecting|preparing|recording|closing) return 0 ;; *) return 1 ;; esac
}

record_plan_owns_file() {
    [[ -n "$RECORD_PLAN_FILE" && "$RECORD_PLAN_FILE" == "${RECORDING_FILE:-}" &&
        "$RECORD_PLAN_PID" == "${PLAYER_PID:-}" && "$RECORD_PLAN_URL" == "${PLAYER_URL:-}" ]] &&
        ((${RECORDING_ACTIVE:-0}))
}

record_plan_status() {
    case "$RECORD_PLAN_STATE" in
        pending) RECORD_PLAN_STATUS='Programada' ;;
        connecting) RECORD_PLAN_STATUS='Esperando audio' ;;
        preparing) RECORD_PLAN_STATUS='Preparando archivo' ;;
        recording) RECORD_PLAN_STATUS='Grabando' ;;
        closing) RECORD_PLAN_STATUS='Cierre pendiente' ;;
        done) RECORD_PLAN_STATUS='Finalizada' ;;
        skipped) RECORD_PLAN_STATUS='Omitida' ;;
        failed) RECORD_PLAN_STATUS='Requiere revisión' ;;
        cancelled) RECORD_PLAN_STATUS='Cancelada / interrumpida' ;;
        *) RECORD_PLAN_STATUS='Sin programar' ;;
    esac
    record_plan_after_label "$RECORD_PLAN_STOP_AFTER"
    RECORD_PLAN_DETAIL="Emisora: ${RECORD_PLAN_NAME:-sin elegir}. ${RECORD_PLAN_LABEL:-Sin horario}. Al finalizar: $RECORD_PLAN_AFTER_LABEL. Archivo: ${RECORD_PLAN_FILE:-se reservará al iniciar}. ${RECORD_PLAN_NOTE}"
}

record_plan_prepare() {
    local name=$1 url=$2 hour=$3 minutes=$4 now=${5:-$EPOCHSECONDS} day target
    RECORD_PLAN_ERROR=''
    station_manual_valid "$name" "$url" || { RECORD_PLAN_ERROR='Elige una favorita con URL HTTP/HTTPS válida.'; return 1; }
    [[ "$hour" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || { RECORD_PLAN_ERROR='Hora inválida: usa HH:MM.'; return 1; }
    if [[ ! "$minutes" =~ ^[0-9]{1,4}$ ]] || ((10#$minutes < 1 || 10#$minutes > 1440)); then
        RECORD_PLAN_ERROR='La duración debe ser de 1 a 1440 minutos.'; return 1
    fi
    day=$(date -d "@$now" +%F) || return 1
    target=$(date -d "$day $hour" +%s 2>/dev/null) || { RECORD_PLAN_ERROR='Esa hora no existe en la fecha local.'; return 1; }
    if ((target <= now)); then
        day=$(date -d "$day +1 day" +%F) || return 1
        target=$(date -d "$day $hour" +%s 2>/dev/null) || return 1
    fi
    RECORD_PLAN_DRAFT_AT=$target RECORD_PLAN_DRAFT_END=$((target + 10#$minutes * 60))
    RECORD_PLAN_DRAFT_LABEL="Inicio: $(date -d "@$target" '+%d/%m/%Y %H:%M'). Fin: $(date -d "@$RECORD_PLAN_DRAFT_END" '+%d/%m/%Y %H:%M') (hora local)"
}

record_plan_arm() {
    local name=$1 url=$2 at=$3 end=$4 now=${5:-$EPOCHSECONDS} stop_after=${6:-0}
    RECORD_PLAN_ERROR=''
    record_plan_busy && { RECORD_PLAN_ERROR='Ya hay una programación en curso. Cancélala o espera su cierre.'; return 1; }
    station_manual_valid "$name" "$url" || { RECORD_PLAN_ERROR='Emisora no válida.'; return 1; }
    [[ "$stop_after" == 0 || "$stop_after" == 1 ]] || { RECORD_PLAN_ERROR='Elige Sí o No para parar al finalizar.'; return 1; }
    if [[ ! "$at" =~ ^[1-9][0-9]{0,10}$ || ! "$end" =~ ^[1-9][0-9]{0,10}$ ]] ||
        ((at <= now || at > now+172800 || end-at < 60 || end-at > 86400)); then
        RECORD_PLAN_ERROR='El horario ya pasó o no es válido. Vuelve y revisa la programación.'; return 1
    fi
    RECORD_PLAN_STATE=pending RECORD_PLAN_AT=$at RECORD_PLAN_END=$end
    RECORD_PLAN_NAME=$name RECORD_PLAN_URL=$url RECORD_PLAN_FILE='' RECORD_PLAN_PID=''
    RECORD_PLAN_LABEL="Inicio: $(date -d "@$at" '+%d/%m/%Y %H:%M'). Fin: $(date -d "@$end" '+%d/%m/%Y %H:%M') (hora local)"
    RECORD_PLAN_NOTE='Mantén Keila abierto y el equipo despierto.'
    RECORD_PLAN_CHECK_AT=0 RECORD_PLAN_RESULT='done' RECORD_PLAN_END_REASON=''
    RECORD_PLAN_STOP_AFTER=$stop_after RECORD_PLAN_END_REACHED=0
    app_message "Grabación programada: $name. $RECORD_PLAN_LABEL." 10
}

record_plan_finish() {
    RECORD_PLAN_STATE=$1 RECORD_PLAN_NOTE=$2
    app_message "Grabación programada: $2" 10
    return 0
}

record_plan_sleep_stop() {
    if record_plan_busy || { [[ "$RECORD_PLAN_STATE" == pending ]] && ((RECORD_PLAN_AT <= EPOCHSECONDS)); }; then
        record_plan_finish cancelled 'Interrumpida por el temporizador de parada; se conserva cualquier archivo.'
    fi
}

record_plan_blocks_alarm() {
    case "$RECORD_PLAN_STATE" in preparing|recording|closing) record_plan_owns_file ;; *) return 1 ;; esac
}

record_plan_cancel() {
    # Cancelar manualmente no activa la parada prevista para el final del horario.
    RECORD_PLAN_END_REACHED=0
    if record_plan_owns_file && record_plan_busy; then
        RECORD_PLAN_STATE=closing RECORD_PLAN_RESULT=cancelled
        RECORD_PLAN_CLOSE_UNTIL=$((EPOCHSECONDS+5)) RECORD_PLAN_CHECK_AT=0
        RECORD_PLAN_NOTE='Cancelación solicitada; cerrando el archivo.'
    else
        [[ "$RECORD_PLAN_STATE" != connecting ]] || app_reconnect_reset
        record_plan_finish cancelled 'Cancelada. No se inicia otra grabación; los archivos se conservan.'
    fi
}

record_plan_launch() {
    # Respeta el silencio desde el arranque de mpv, sin desmutear y corregir luego.
    local PLAYER_PRESERVE_MUTE=1 RECORD_PLAN_LAUNCHING=1
    app_play "$RECORD_PLAN_NAME" "$RECORD_PLAN_URL"
}

record_plan_manual_play() {
    if [[ "$RECORD_PLAN_STATE" == connecting && ${RECORD_PLAN_LAUNCHING:-0} != 1 ]]; then
        record_plan_finish cancelled 'Cancelada al elegir una reproducción manual.'
    fi
    return 0
}

record_plan_stop_after() {
    RECORD_PLAN_AFTER_NOTE=''
    ((RECORD_PLAN_STOP_AFTER && RECORD_PLAN_END_REACHED && !RECORDING_ACTIVE)) || return 0
    # Una reproducción o escucha nueva nunca pertenece a esta programación.
    [[ -n "$RECORD_PLAN_PID" && "$PLAYER_PID" == "$RECORD_PLAN_PID" &&
        "$PLAYER_URL" == "$RECORD_PLAN_URL" && "$RECORDING_FILE" == "$RECORD_PLAN_FILE" &&
        -z "${PENDING_PREVIEW_PID:-}" ]] || return 0
    app_reconnect_reset
    spectrum_stop
    player_stop
    app_reconnect_reset
    # Como en la parada por minutos: no reactivar por una alarma ya vencida,
    # pero conservar la que el usuario haya programado para más adelante.
    if ((${ALARM_AT:-0} > 0 && ALARM_AT <= EPOCHSECONDS)); then ALARM_AT=0 ALARM_LABEL=''; fi
    RECORD_PLAN_AFTER_NOTE=' Reproducción detenida al finalizar; Keila sigue abierto.'
}

record_plan_closed() {
    local status=${1:-0}
    record_plan_stop_after
    if ((status == 0 && ${RECORDING_LAST_VERIFIED:-0})) && [[ -z "${RECORDING_LAST_ERROR:-}" ]]; then
        record_plan_finish "$RECORD_PLAN_RESULT" "${RECORD_PLAN_END_REASON}Archivo cerrado y verificado: $RECORD_PLAN_FILE${RECORD_PLAN_AFTER_NOTE}"
    else
        record_plan_finish failed "Archivo conservado para revisión: $RECORD_PLAN_FILE. ${RECORDING_LAST_ERROR:-No se pudo verificar el audio.}${RECORD_PLAN_AFTER_NOTE}"
    fi
}

record_plan_tick() {
    local now=$EPOCHSECONDS status=0
    case "$RECORD_PLAN_STATE" in
        pending)
            ((now >= RECORD_PLAN_AT)) || return 1
            if ((now-RECORD_PLAN_AT > 60 || now >= RECORD_PLAN_END)); then
                record_plan_finish skipped 'El inicio pasó mientras Keila no estaba ejecutándose. No se graba fuera de horario.'; return 0
            fi
            if ((${RECORDING_ACTIVE:-0})); then
                record_plan_finish skipped 'Ya hay una grabación activa; no se interrumpe.'; return 0
            fi
            if [[ -n "${PENDING_PREVIEW_PID:-}" ]] || ((${BACKUP_DATA_BUSY:-0})); then
                record_plan_finish skipped 'Hay una escucha de archivo o restauración en curso; no se interrumpe.'; return 0
            fi
            if ((${ALARM_AT:-0} > 0 && ALARM_AT <= now)); then
                record_plan_finish skipped 'Coincide con una alarma vencida; se da prioridad a la alarma.'; return 0
            fi
            RECORD_PLAN_STATE=connecting RECORD_PLAN_CONNECT_UNTIL=$((now+30))
            RECORD_PLAN_NOTE='Conectando; todavía no se está grabando.'
            if [[ "$PLAYER_URL" != "$RECORD_PLAN_URL" ]] || ! player_is_running || ((PLAYER_PAUSED)); then
                if ! record_plan_launch; then
                    app_reconnect_reset
                    record_plan_finish failed 'No se pudo conectar con la emisora. No se inició la grabación.'; return 0
                fi
            fi
            return 0 ;;
        connecting)
            if ((RECORDING_ACTIVE)); then
                record_plan_finish skipped 'Se inició otra grabación; se conserva sin cambios.'; return 0
            fi
            if [[ "$PLAYER_URL" != "$RECORD_PLAN_URL" ]] || ((PLAYER_PAUSED)) || [[ -n "${PENDING_PREVIEW_PID:-}" ]]; then
                record_plan_finish cancelled 'La reproducción cambió antes de iniciar; no se graba.'; return 0
            fi
            if ((now >= RECORD_PLAN_CONNECT_UNTIL || now >= RECORD_PLAN_END)); then
                app_reconnect_reset
                record_plan_finish failed 'No llegó audio a tiempo (máximo 30 s). No se inició la grabación.'; return 0
            fi
            if ((${ALARM_AT:-0} > 0 && ALARM_AT <= now)); then
                app_reconnect_reset
                record_plan_finish skipped 'Se da prioridad a la alarma; no se inicia la grabación.'; return 0
            fi
            if player_is_running && ((PLAYER_STREAM_READY && !PLAYER_BUFFERING)); then
                if recording_start "$RECORD_PLAN_NAME"; then
                    RECORD_PLAN_FILE=$RECORDING_FILE RECORD_PLAN_PID=$PLAYER_PID
                    RECORD_PLAN_STATE=preparing RECORD_PLAN_NOTE='Preparando archivo; se espera a recibir datos.'
                    app_message "Preparando grabación programada: $(recording_filename)" 8
                else
                    record_plan_finish failed 'No se pudo crear o iniciar la grabación. Revisa permisos, espacio y conexión.'
                fi
                return 0
            fi
            return 1 ;;
        preparing|recording|closing)
            if ! record_plan_owns_file; then
                # El tick normal del grabador también puede completar un cierre.
                # Solo recoger su resultado si sigue siendo exactamente el nuestro.
                if [[ "$RECORD_PLAN_STATE" == closing && "$RECORD_PLAN_FILE" == "$RECORDING_FILE" &&
                    "$RECORD_PLAN_PID" == "$PLAYER_PID" && "$RECORD_PLAN_URL" == "$PLAYER_URL" ]] && ((!RECORDING_ACTIVE)); then
                    record_plan_closed; return 0
                fi
                record_plan_finish cancelled 'La grabación se cerró o cambió fuera de la programación; no se toca ningún otro archivo.'; return 0
            fi
            if [[ "$RECORD_PLAN_STATE" != closing ]] && { ((now >= RECORD_PLAN_END)) || ! player_is_running; }; then
                RECORD_PLAN_STATE=closing RECORD_PLAN_CLOSE_UNTIL=$((now+5)) RECORD_PLAN_CHECK_AT=0
                ((now < RECORD_PLAN_END)) || RECORD_PLAN_END_REACHED=1
                RECORD_PLAN_NOTE='Finalizando el archivo.'
                if ! player_is_running; then
                    RECORD_PLAN_RESULT=failed
                    RECORD_PLAN_END_REASON='La emisora se detuvo inesperadamente; la grabación puede estar incompleta. '
                fi
            fi
            if [[ "$RECORD_PLAN_STATE" == closing ]]; then
                ((now >= RECORD_PLAN_CHECK_AT)) || return 1
                RECORD_PLAN_CHECK_AT=$((now+1))
                recording_stop || status=$?
                if ((status == 2 && now >= RECORD_PLAN_CLOSE_UNTIL)); then
                    # Solo el reproductor/archivo que pertenecen a esta reserva.
                    app_reconnect_reset
                    player_stop
                    # El cierre forzado ya detuvo nuestra radio: aplicar también
                    # la prioridad frente a alarmas vencidas, sin volver a pararla.
                    if ((RECORD_PLAN_STOP_AFTER && RECORD_PLAN_END_REACHED && ${ALARM_AT:-0} > 0 && ALARM_AT <= EPOCHSECONDS)); then
                        ALARM_AT=0 ALARM_LABEL=''
                    fi
                    status=0; recording_stop || status=$?
                    if ((status == 2)); then
                        record_plan_finish failed "No se confirmó el cierre. Archivo y marcador conservados: $RECORD_PLAN_FILE"
                        return 0
                    fi
                fi
                if ((status != 2)); then
                    record_plan_closed "$status"
                fi
                return 0
            fi
            if [[ "$RECORD_PLAN_STATE" == preparing && "$RECORDING_PHASE" == recording ]]; then
                RECORD_PLAN_STATE=recording RECORD_PLAN_NOTE='Recibiendo datos. El final previsto no se retrasa.'
                return 0
            fi
            return 1 ;;
        *) return 1 ;;
    esac
}
