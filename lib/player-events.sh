#!/usr/bin/env bash

# Cliente IPC persistente dedicado a eventos de mpv.
#
# El polling de player_refresh_info sigue siendo la fuente de verdad. Esta capa
# solo adelanta snapshots cuando mpv avisa de cambios discretos de estado. No
# observamos audio-pts/playback-time porque cambian continuamente y generarían
# un flujo de eventos innecesariamente alto.

PLAYER_EVENTS_PID="${PLAYER_EVENTS_PID:-}"
PLAYER_EVENTS_READ_FD="${PLAYER_EVENTS_READ_FD:-}"
PLAYER_EVENTS_WRITE_FD="${PLAYER_EVENTS_WRITE_FD:-}"
PLAYER_EVENTS_ACTIVE="${PLAYER_EVENTS_ACTIVE:-0}"
PLAYER_EVENTS_DIRTY="${PLAYER_EVENTS_DIRTY:-0}"
PLAYER_EVENTS_PROPERTY_CHANGES="${PLAYER_EVENTS_PROPERTY_CHANGES:-0}"
PLAYER_EVENTS_LAST_AT="${PLAYER_EVENTS_LAST_AT:-0}"
PLAYER_EVENTS_DRAIN_LIMIT="${KEILA_PLAYER_EVENT_DRAIN_LIMIT:-64}"

player_events_now() {
    printf '%s\n' "${EPOCHSECONDS:-$(date +%s)}"
}

player_events_configure() {
    [[ "$PLAYER_EVENTS_DRAIN_LIMIT" =~ ^[0-9]+$ ]] || PLAYER_EVENTS_DRAIN_LIMIT=64
    ((PLAYER_EVENTS_DRAIN_LIMIT < 8)) && PLAYER_EVENTS_DRAIN_LIMIT=8
    ((PLAYER_EVENTS_DRAIN_LIMIT > 256)) && PLAYER_EVENTS_DRAIN_LIMIT=256
}

player_events_reset_state() {
    PLAYER_EVENTS_ACTIVE=0
    PLAYER_EVENTS_DIRTY=0
    PLAYER_EVENTS_PROPERTY_CHANGES=0
    PLAYER_EVENTS_LAST_AT=0
}

player_events_close_fd() {
    local variable_name="$1"
    local fd="${!variable_name:-}"

    [[ "$fd" =~ ^[0-9]+$ ]] || {
        printf -v "$variable_name" '%s' ''
        return 0
    }

    case "$variable_name" in
        PLAYER_EVENTS_READ_FD)
            exec {PLAYER_EVENTS_READ_FD}<&- 2>/dev/null || true
            ;;
        PLAYER_EVENTS_WRITE_FD)
            exec {PLAYER_EVENTS_WRITE_FD}>&- 2>/dev/null || true
            ;;
    esac
    printf -v "$variable_name" '%s' ''
}

player_events_stop() {
    local pid="${PLAYER_EVENTS_PID:-}"
    local attempt

    player_events_close_fd PLAYER_EVENTS_WRITE_FD
    player_events_close_fd PLAYER_EVENTS_READ_FD

    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            for ((attempt = 0; attempt < 10; attempt++)); do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.02
            done
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        wait "$pid" 2>/dev/null || true
    fi

    PLAYER_EVENTS_PID=""
    player_events_reset_state
}

player_events_send_observers() {
    local fd="${PLAYER_EVENTS_WRITE_FD:-}"

    [[ "$fd" =~ ^[0-9]+$ ]] || return 1

    {
        printf '%s\n' '{"command":["observe_property",201,"paused-for-cache"]}'
        printf '%s\n' '{"command":["observe_property",202,"core-idle"]}'
        printf '%s\n' '{"command":["observe_property",203,"metadata"]}'
        printf '%s\n' '{"command":["observe_property",204,"media-title"]}'
        printf '%s\n' '{"command":["observe_property",205,"current-tracks/audio/codec"]}'
        printf '%s\n' '{"command":["observe_property",206,"audio-bitrate"]}'
        printf '%s\n' '{"command":["observe_property",207,"audio-params"]}'
    } >&"$fd"
}

player_events_start() {
    player_events_stop >/dev/null 2>&1 || true
    [[ -S "$PLAYER_SOCKET" ]] || return 1
    command -v socat >/dev/null 2>&1 || return 1

    coproc KEILA_MPV_EVENTS { socat - UNIX-CONNECT:"$PLAYER_SOCKET" 2>/dev/null; }

    PLAYER_EVENTS_READ_FD="${KEILA_MPV_EVENTS[0]:-}"
    PLAYER_EVENTS_WRITE_FD="${KEILA_MPV_EVENTS[1]:-}"
    PLAYER_EVENTS_PID="${KEILA_MPV_EVENTS_PID:-}"

    if [[ ! "$PLAYER_EVENTS_READ_FD" =~ ^[0-9]+$ ||
          ! "$PLAYER_EVENTS_WRITE_FD" =~ ^[0-9]+$ ||
          ! "$PLAYER_EVENTS_PID" =~ ^[0-9]+$ ]]; then
        player_events_stop >/dev/null 2>&1 || true
        return 1
    fi

    if ! kill -0 "$PLAYER_EVENTS_PID" 2>/dev/null || ! player_events_send_observers; then
        player_events_stop >/dev/null 2>&1 || true
        return 1
    fi

    PLAYER_EVENTS_ACTIVE=1
    PLAYER_EVENTS_DIRTY=1
    return 0
}

player_events_handle_line() {
    local line="$1"
    local event_name event name

    [[ -n "$line" ]] || return 1

    # event y name salen del mismo documento; evitar dos procesos jq por cada
    # notificación reduce el trabajo cuando mpv cambia varios metadatos seguidos.
    event_name=$(jq -r 'if type == "object" then [(.event // ""),(.name // "")] | @tsv else empty end' <<< "$line" 2>/dev/null) || return 1
    [[ -n "$event_name" ]] || return 1
    IFS=$'\t' read -r event name <<< "$event_name"
    [[ "$event" == 'property-change' ]] || return 1

    case "$name" in
        paused-for-cache|core-idle|metadata|media-title|current-tracks/audio/codec|audio-bitrate|audio-params)
            PLAYER_EVENTS_DIRTY=1
            PLAYER_EVENTS_PROPERTY_CHANGES=$((PLAYER_EVENTS_PROPERTY_CHANGES + 1))
            PLAYER_EVENTS_LAST_AT=$(player_events_now)
            return 0
            ;;
    esac

    return 1
}

# Vacía solo lo que ya está disponible, con un límite por tick. Un cliente de
# eventos ruidoso nunca puede monopolizar el loop de teclado/redibujado.
player_events_drain() {
    local fd="${PLAYER_EVENTS_READ_FD:-}"
    local pid="${PLAYER_EVENTS_PID:-}"
    local line ready='' count=0 changed=1

    ((PLAYER_EVENTS_ACTIVE)) || return 1
    [[ "$fd" =~ ^[0-9]+$ && "$pid" =~ ^[0-9]+$ ]] || return 1

    if ! kill -0 "$pid" 2>/dev/null; then
        player_events_stop >/dev/null 2>&1 || true
        return 1
    fi

    while ((count < PLAYER_EVENTS_DRAIN_LIMIT)); do
        # Primero comprobamos disponibilidad sin ceder 1 ms en cada vuelta del
        # bucle principal. Cuando hay datos, la segunda lectura consume la línea
        # completa; los eventos de mpv se escriben siempre terminados en salto
        # de línea, por lo que esta lectura no puede dejar bloqueada la TUI.
        if ! IFS= read -r -t 0 -u "$fd" ready; then
            break
        fi
        if ! IFS= read -r -u "$fd" line; then
            break
        fi
        count=$((count + 1))
        if player_events_handle_line "$line"; then
            changed=0
        fi
    done

    return "$changed"
}

player_events_configure

# Se carga después de las capas de fallo/reconexión: envuelve las funciones
# finales del reproductor, pero ui-terminal-guard seguirá cargándose después.
if declare -F player_start >/dev/null 2>&1 && ! declare -F player_start_without_events >/dev/null 2>&1; then
    PLAYER_EVENTS_DEF=$(declare -f player_start)
    PLAYER_EVENTS_DEF=${PLAYER_EVENTS_DEF/player_start ()/player_start_without_events ()}
    eval "$PLAYER_EVENTS_DEF"

    player_start() {
        local name="$1" url="$2" status=0

        player_events_stop >/dev/null 2>&1 || true
        player_start_without_events "$name" "$url" || status=$?
        if ((status != 0)); then
            return "$status"
        fi

        # Los eventos son una optimización. Si el cliente persistente no puede
        # iniciarse, playback continúa con el polling que ya conocemos.
        player_events_start >/dev/null 2>&1 || true
        return 0
    }
fi

if declare -F player_stop >/dev/null 2>&1 && ! declare -F player_stop_without_events >/dev/null 2>&1; then
    PLAYER_EVENTS_DEF=$(declare -f player_stop)
    PLAYER_EVENTS_DEF=${PLAYER_EVENTS_DEF/player_stop ()/player_stop_without_events ()}
    eval "$PLAYER_EVENTS_DEF"

    player_stop() {
        local status=0

        player_events_stop >/dev/null 2>&1 || true
        player_stop_without_events || status=$?
        return "$status"
    }
fi

if declare -F player_refresh_info >/dev/null 2>&1 && ! declare -F player_refresh_info_without_events >/dev/null 2>&1; then
    PLAYER_EVENTS_DEF=$(declare -f player_refresh_info)
    PLAYER_EVENTS_DEF=${PLAYER_EVENTS_DEF/player_refresh_info ()/player_refresh_info_without_events ()}
    eval "$PLAYER_EVENTS_DEF"

    player_refresh_info() {
        player_events_drain >/dev/null 2>&1 || true

        # Un cambio discreto observado invalida el throttle de 1 s y fuerza un
        # snapshot inmediato. Después seguimos usando exactamente el parser y
        # las propiedades del polling existente como fuente de verdad.
        if ((PLAYER_EVENTS_DIRTY)); then
            PLAYER_EVENTS_DIRTY=0
            PLAYER_INFO_LAST_REFRESH=0
        fi

        player_refresh_info_without_events
    }
fi

unset PLAYER_EVENTS_DEF
