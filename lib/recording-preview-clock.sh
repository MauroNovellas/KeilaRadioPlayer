#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Telemetría solo del archivo en escucha. Nunca sondear la biblioteca completa.
PENDING_CLOCK_PID='' PENDING_CLOCK_DIR='' PENDING_CLOCK_AT=0 PENDING_CLOCK_DEADLINE=0
PENDING_CLOCK_POSITION='-' PENDING_CLOCK_DURATION='-' PENDING_CLOCK_FORCE=1
PENDING_CLOCK_TIME='--:-- / --:--'

pending_clock_parse() {
    jq -rs '
        def value($id; $positive):
            map(select(type == "object" and .request_id == $id)) | last |
            if .error == "success" and (.data | type) == "number" then
                # mpv 0.34/0.37 puede devolver una fracción negativa al iniciar
                # o volver al inicio. Se representa como 00:00, no como ausencia.
                .data | if . <= 35999999 and (if $positive then . > 0 else . > -1 end)
                    then [0, floor] | max | tostring else "-" end
            else "-" end;
        [value(1; false), value(2; true)] | join(" ")
    '
}

pending_clock_worker() {
    local socket=$1 directory=$2 response=''
    # Un fallo de conexión invalida los datos; nunca mantener un reloj inventado.
    if [[ -S "$socket" ]]; then
        response=$(
            printf '%s\n' '{"command":["get_property","time-pos"],"request_id":1}' \
                '{"command":["get_property","duration"],"request_id":2}' |
                timeout --kill-after=.1s .5s socat -t .1 - UNIX-CONNECT:"$socket" 2>/dev/null
        ) || response=''
    fi
    pending_clock_parse <<< "$response" > "$directory/result.tmp" || printf '%s\n' '- -' > "$directory/result.tmp"
    mv -T -- "$directory/result.tmp" "$directory/result"
}

pending_clock_stop() {
    if [[ -n "$PENDING_CLOCK_PID" ]]; then
        player_terminate_group_bounded "$PENDING_CLOCK_PID" "$PENDING_CLOCK_PID" || true
        wait "$PENDING_CLOCK_PID" 2>/dev/null || true
    fi
    PENDING_CLOCK_PID=''
    [[ -z "$PENDING_CLOCK_DIR" ]] || rm -rf -- "$PENDING_CLOCK_DIR"
    PENDING_CLOCK_DIR=''
}

pending_clock_format() {
    local value=$1
    PENDING_CLOCK_FORMATTED='--:--'
    [[ "$value" =~ ^(0|[1-9][0-9]{0,7})$ ]] && ((value <= 35999999)) || return 0
    if ((value >= 3600)); then printf -v PENDING_CLOCK_FORMATTED '%02d:%02d:%02d' "$((value/3600))" "$((value/60%60))" "$((value%60))"
    else printf -v PENDING_CLOCK_FORMATTED '%02d:%02d' "$((value/60))" "$((value%60))"; fi
}

pending_clock_update_text() {
    pending_clock_format "$PENDING_CLOCK_POSITION"
    local position=$PENDING_CLOCK_FORMATTED
    pending_clock_format "$PENDING_CLOCK_DURATION"
    PENDING_CLOCK_TIME="$position / $PENDING_CLOCK_FORMATTED"
}

pending_clock_invalidate() {
    # Una respuesta iniciada antes de pausar/buscar no representa la nueva posición.
    pending_clock_stop
    PENDING_CLOCK_POSITION='-' PENDING_CLOCK_FORCE=1 PENDING_CLOCK_AT=0
    pending_clock_update_text
}

pending_clock_start() {
    [[ -z "$PENDING_CLOCK_PID" && -n "$PENDING_PREVIEW_DIR" ]] || return 1
    PENDING_CLOCK_DIR=$(mktemp -d "$PENDING_PREVIEW_DIR/clock.XXXXXX") || return 1
    PENDING_CLOCK_AT=$EPOCHSECONDS PENDING_CLOCK_DEADLINE=$((EPOCHSECONDS+2))
    PENDING_CLOCK_FORCE=0
    setsid -- bash "$BASE_DIR/lib/recording-preview-clock.sh" "$PENDING_PREVIEW_SOCKET" "$PENDING_CLOCK_DIR" </dev/null >/dev/null 2>&1 &
    PENDING_CLOCK_PID=$!
}

pending_clock_poll() {
    local before=$PENDING_CLOCK_TIME row='- -' position duration extra
    if [[ -n "$PENDING_CLOCK_PID" ]]; then
        if [[ -f "$PENDING_CLOCK_DIR/result" ]]; then
            IFS= read -r row < "$PENDING_CLOCK_DIR/result" || row='- -'
            wait "$PENDING_CLOCK_PID" 2>/dev/null || true
            PENDING_CLOCK_PID=''
        elif ((EPOCHSECONDS < PENDING_CLOCK_DEADLINE)) && kill -0 "$PENDING_CLOCK_PID" 2>/dev/null; then return 1
        fi
        pending_clock_stop
        read -r position duration extra <<< "$row"
        if [[ -n "$extra" || ! "$position" =~ ^(-|0|[1-9][0-9]{0,7})$ || ! "$duration" =~ ^(-|0|[1-9][0-9]{0,7})$ ]]; then position='-' duration='-'; fi
        PENDING_CLOCK_POSITION=$position PENDING_CLOCK_DURATION=$duration
        pending_clock_update_text
    fi
    if ((PENDING_PREVIEW_READY && EPOCHSECONDS > PENDING_CLOCK_AT)) && [[ -z "$PENDING_CLOCK_PID" ]]; then
        # En pausa basta la primera lectura confirmada. Si faltan datos se
        # reintenta despacio, sin activar un reloj que avance por su cuenta.
        if ((PENDING_CLOCK_FORCE || !PENDING_PREVIEW_PAUSED)) || { [[ "$PENDING_CLOCK_POSITION" == - || "$PENDING_CLOCK_DURATION" == - ]] && ((EPOCHSECONDS >= PENDING_CLOCK_AT+5)); }; then
            pending_clock_start || true
        fi
    fi
    [[ "$before" != "$PENDING_CLOCK_TIME" ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    pending_clock_worker "$@"
fi
