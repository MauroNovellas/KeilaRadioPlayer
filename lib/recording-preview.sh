#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Escucha local aislada: ni el socket, ni el historial ni el estado de la radio.
PENDING_PREVIEW_PID='' PENDING_PREVIEW_DIR='' PENDING_PREVIEW_SOCKET=''
PENDING_PREVIEW_FILE='' PENDING_PREVIEW_STATE='' PENDING_PREVIEW_PAUSED=0
PENDING_PREVIEW_READY=0 PENDING_PREVIEW_DEADLINE=0 PENDING_PREVIEW_CHECK_AT=0
PENDING_RADIO_PID='' PENDING_RADIO_URL='' PENDING_RADIO_RESUME=0
PENDING_PREVIEW_RETURN_NOTICE='' PENDING_PREVIEW_RESPONSE='' PENDING_PREVIEW_REQUEST=0

pending_preview_exchange() {
    [[ -S "$PENDING_PREVIEW_SOCKET" ]] || return 1
    # Solo acciones del usuario y la preparación inicial; no consultas por tick
    # durante una escucha normal. Timeout también si mpv no responde.
    printf '%s\n' "$1" | timeout --kill-after=.1s .4s socat -t .1 - UNIX-CONNECT:"$PENDING_PREVIEW_SOCKET" 2>/dev/null
}

pending_preview_command() {
    local command=$1 payload response
    [[ -n "$PENDING_PREVIEW_PID" ]] || return 1
    ((PENDING_PREVIEW_REQUEST+=1))
    payload=$(jq -cn --argjson command "$command" --argjson id "$PENDING_PREVIEW_REQUEST" '{command:$command,request_id:$id}') || return 1
    response=$(pending_preview_exchange "$payload") || return 1
    PENDING_PREVIEW_RESPONSE=$(jq -cse --argjson id "$PENDING_PREVIEW_REQUEST" '
        map(select(type == "object" and .request_id == $id and .error == "success")) | last // empty
    ' <<< "$response") || return 1
}

pending_preview_stop() {
    local pid=$PENDING_PREVIEW_PID
    if [[ -n "$pid" ]]; then
        player_terminate_group_bounded "$pid" "$pid" || true
        wait "$pid" 2>/dev/null || true
    fi
    PENDING_PREVIEW_PID='' PENDING_PREVIEW_READY=0 PENDING_PREVIEW_PAUSED=0
    [[ -z "$PENDING_PREVIEW_DIR" ]] || rm -rf -- "$PENDING_PREVIEW_DIR"
    PENDING_PREVIEW_DIR='' PENDING_PREVIEW_SOCKET=''
    # No despausar otra emisora, una radio que ya estaba pausada ni una alarma.
    if ((PENDING_RADIO_RESUME)) && [[ "$PENDING_RADIO_PID" == "${PLAYER_PID:-}" && "$PENDING_RADIO_URL" == "${PLAYER_URL:-}" ]] && ((${PLAYER_PAUSED:-0})); then
        if player_toggle_pause; then PENDING_PREVIEW_RETURN_NOTICE='Radio anterior reanudada.'
        else PENDING_PREVIEW_RETURN_NOTICE='No se pudo reanudar la radio; vuelve al reproductor y pulsa pausa.'; fi
    fi
    PENDING_RADIO_PID='' PENDING_RADIO_URL='' PENDING_RADIO_RESUME=0
}

pending_preview_start() {
    local file=$1 mute=no
    PENDING_NOTICE='No se puede escuchar: archivo vacío, ocupado o no disponible.'
    pending_signature "$file" >/dev/null && [[ -s "$file" && -r "$file" ]] && ! pending_busy "$file" || return 1
    ((${RECORDING_ACTIVE:-0} == 0)) || { PENDING_NOTICE='Detén la grabación antes de escuchar.'; return 1; }
    pending_preview_stop
    PENDING_PREVIEW_RETURN_NOTICE='La radio conserva su estado anterior.'
    PENDING_PREVIEW_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keila-listen.XXXXXX") || return 1
    PENDING_PREVIEW_SOCKET="$PENDING_PREVIEW_DIR/mpv.sock"
    PENDING_RADIO_PID=${PLAYER_PID:-} PENDING_RADIO_URL=${PLAYER_URL:-}
    if player_is_running && ((${PLAYER_PAUSED:-0} == 0)); then
        if ! player_toggle_pause; then
            pending_preview_stop
            PENDING_NOTICE='No se pudo pausar la radio; no se inicia otra escucha.'
            return 1
        fi
        PENDING_RADIO_RESUME=1
    fi
    PENDING_PREVIEW_FILE=$file PENDING_PREVIEW_STATE=Preparando
    PENDING_PREVIEW_READY=0 PENDING_PREVIEW_PAUSED=0
    PENDING_PREVIEW_DEADLINE=$((EPOCHSECONDS+8)) PENDING_PREVIEW_CHECK_AT=0
    ((${PLAYER_MUTED:-0})) && mute=yes
    local -a args=(--no-config --really-quiet --no-terminal --no-video --audio-display=no
        --no-resume-playback --save-position-on-quit=no --idle=no
        --input-ipc-server="$PENDING_PREVIEW_SOCKET" --volume="${PLAYER_VOLUME:-50}" --mute="$mute" -- "$file")
    if declare -F mpv >/dev/null 2>&1; then
        mpv "${args[@]}" </dev/null >/dev/null 2>&1 &
    else
        setsid -- mpv "${args[@]}" </dev/null >/dev/null 2>&1 &
    fi
    PENDING_PREVIEW_PID=$!
    PENDING_NOTICE='Preparando escucha… Esc cancela y vuelve a la radio.'
}

pending_preview_poll() {
    [[ -n "$PENDING_PREVIEW_PID" ]] || return 1
    if [[ "$PENDING_RADIO_PID" != "${PLAYER_PID:-}" || "$PENDING_RADIO_URL" != "${PLAYER_URL:-}" ]] || { [[ -n "${PLAYER_PID:-}" ]] && ((${PLAYER_PAUSED:-0} == 0)); }; then
        PENDING_RADIO_RESUME=0
        pending_preview_stop
        PENDING_PREVIEW_STATE=Interrumpida
        PENDING_NOTICE='Escucha detenida por cambio de radio o alarma. La reproducción actual se conserva.'
        return 0
    fi
    if ! kill -0 "$PENDING_PREVIEW_PID" 2>/dev/null; then
        local status=0
        wait "$PENDING_PREVIEW_PID" 2>/dev/null || status=$?
        pending_preview_stop
        PENDING_PREVIEW_STATE=Terminada
        PENDING_NOTICE='Escucha terminada.'
        if ((status)); then PENDING_PREVIEW_STATE=Error; PENDING_NOTICE='No se pudo reproducir el archivo. Se conserva sin cambios.'; fi
        PENDING_NOTICE+=" $PENDING_PREVIEW_RETURN_NOTICE"
        return 0
    fi
    ((PENDING_PREVIEW_READY == 0)) || return 1
    if ((EPOCHSECONDS >= PENDING_PREVIEW_DEADLINE)); then
        pending_preview_stop
        PENDING_PREVIEW_STATE=Error
        PENDING_NOTICE="La escucha no respondió a tiempo. $PENDING_PREVIEW_RETURN_NOTICE"
        return 0
    fi
    ((EPOCHSECONDS >= PENDING_PREVIEW_CHECK_AT)) || return 1
    PENDING_PREVIEW_CHECK_AT=$((EPOCHSECONDS+1))
    if pending_preview_command '["get_property","audio-params"]'; then
        PENDING_PREVIEW_READY=1 PENDING_PREVIEW_STATE=Escuchando
        PENDING_NOTICE='P pausa | Izquierda / derecha: saltos de 10 s | Esc vuelve'
        return 0
    fi
    return 1
}

pending_preview_action() {
    local action=$1 pause=true command
    ((PENDING_PREVIEW_READY)) || { PENDING_NOTICE='La escucha no está preparada. Esc vuelve a la lista.'; return 1; }
    if [[ "$action" == pause ]]; then
        ((PENDING_PREVIEW_PAUSED == 0)) || pause=false
        if ! pending_preview_command "[\"set_property\",\"pause\",$pause]"; then
            PENDING_NOTICE='No se pudo cambiar la pausa de la grabación.'; return 1
        fi
        PENDING_PREVIEW_PAUSED=$((1-PENDING_PREVIEW_PAUSED))
        if ((PENDING_PREVIEW_PAUSED)); then PENDING_PREVIEW_STATE='En pausa'; else PENDING_PREVIEW_STATE=Escuchando; fi
        PENDING_NOTICE="$PENDING_PREVIEW_STATE · El estado de la radio no cambia."
        return 0
    fi
    case "$action" in
        back) command='["seek",-10,"relative+exact"]' ;;
        forward) command='["seek",10,"relative+exact"]' ;;
        start) command='["seek",0,"absolute+exact"]' ;;
        *) return 1 ;;
    esac
    if ! pending_preview_command '["get_property","seekable"]' || [[ "$PENDING_PREVIEW_RESPONSE" != *'"data":true'* ]]; then
        PENDING_NOTICE='Este archivo no permite saltos, o no se pudo consultar. Puedes seguir escuchándolo.'
        return 1
    fi
    if ! pending_preview_command "$command"; then PENDING_NOTICE='No se pudo cambiar la posición de la grabación.'; return 1; fi
    case "$action" in
        back) PENDING_NOTICE='Retroceso de 10 segundos solicitado.' ;;
        forward) PENDING_NOTICE='Avance de 10 segundos solicitado.' ;;
        start) PENDING_NOTICE='Vuelta al inicio solicitada.' ;;
    esac
}

pending_preview_build_rows() {
    local pause=Pausar reason=''
    ((PENDING_PREVIEW_PAUSED == 0)) || pause=Reanudar
    ((PENDING_PREVIEW_READY)) || reason='Disponible cuando el audio esté preparado.'
    PANEL_ROWS=()
    local sound="Volumen heredado: ${PLAYER_VOLUME:-50}%."
    ((${PLAYER_MUTED:-0} == 0)) || sound+=' Silencio activado en la radio.'
    panel_add_row P "$pause grabación" "Archivo: $PENDING_PREVIEW_FILE. $sound Solo pausa este archivo; no cambia la radio, su volumen ni su silencio." "$PENDING_PREVIEW_STATE" "$reason"
    panel_add_row A 'Retroceder 10 segundos' 'También flecha izquierda. Solo si el formato permite buscar una posición.' '' "$reason"
    panel_add_row D 'Avanzar 10 segundos' 'También flecha derecha. Llegar al final termina la escucha y retoma la radio si corresponde.' '' "$reason"
    panel_add_row I 'Volver al inicio' 'Empieza desde el principio del archivo, conservando la pausa.' '' "$reason"
    panel_add_row R 'Cerrar escucha y volver' 'Detiene este archivo y vuelve a la lista. Retoma la misma radio solo si esta pantalla la pausó; no modifica una nueva emisora ni una alarma.'
}

pending_preview_draw() {
    local -a PANEL_ROWS=()
    pending_preview_build_rows
    panel_draw 'ESCUCHAR GRABACIÓN' "$1" "$2" 'P pausa | A/D saltar | Esc volver' "$PENDING_NOTICE" "${PENDING_PREVIEW_FILE##*/} | $PENDING_PREVIEW_STATE"
}

app_recording_preview() {
    local file=$1 selected=0 offset=0 redraw=1 event key action
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    pending_preview_start "$file" || return 1
    while true; do
        if ((redraw)); then
            pending_preview_draw "$selected" "$offset"
            selected=$PANEL_SELECTED offset=$PANEL_SCROLL
        fi
        input_read || break
        event=$INPUT_EVENT key=${INPUT_KEY,,} redraw=1 action=''
        case "$event" in
            ESC) break ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            RESIZE) ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$event" "$selected" 5 "$PANEL_VISIBLE"; selected=$PANEL_SELECTED ;;
            LEFT) action=back ;;
            RIGHT) action=forward ;;
            ENTER) case "$selected" in 0) action=pause ;; 1) action=back ;; 2) action=forward ;; 3) action=start ;; 4) break ;; esac ;;
            KEY)
                case "$key" in
                    p|' ') action=pause ;; a) action=back ;; d) action=forward ;; i) action=start ;; r|e) break ;;
                    '?') local -a PANEL_ROWS=(); pending_preview_build_rows; panel_detail 'ESCUCHAR GRABACIÓN' "$selected" ;;
                esac ;;
        esac
        [[ -z "$action" ]] || pending_preview_action "$action" || true
    done
    if [[ -n "$PENDING_PREVIEW_PID" ]]; then
        pending_preview_stop
        PENDING_PREVIEW_STATE=Detenida
        PENDING_NOTICE="Escucha detenida. $PENDING_PREVIEW_RETURN_NOTICE"
    fi
    return 0
}
