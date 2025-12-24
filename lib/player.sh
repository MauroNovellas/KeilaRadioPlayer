#!/bin/bash

PAUSADO=0

MPV_SOCKET="/tmp/radio_mpv.sock"

PID_MPV=""
ACTUAL_NOMBRE="(ninguna)"
ACTUAL_URL=""
ESTADO="Detenido"
INFO_STREAM=""
START_TIME=0

NET_IF=""
LAST_RX=0
LAST_CHECK=0
KBPS=0

init_player() {
    command -v mpv >/dev/null || {
        echo "MPV no está instalado"
        exit 1
    }

    command -v socat >/dev/null || {
        echo "socat no está instalado"
        exit 1
    }

    rm -f "$MPV_SOCKET"
}

mpv_cmd() {
    [ -S "$MPV_SOCKET" ] || return
    printf '%s\n' "$1" | socat - "$MPV_SOCKET" >/dev/null 2>&1
}

get_iface() {
    ip route get 1 2>/dev/null | awk '{print $5; exit}'
}

get_rx_bytes() {
    awk -v iface="$NET_IF" '$1 ~ iface":" {print $2}' /proc/net/dev
}

reproducir() {
    stop_player

    PAUSADO=0
    ACTUAL_NOMBRE="$1"
    ACTUAL_URL="$2"
    ESTADO="Conectando"
    INFO_STREAM="Conectando"
    START_TIME=$(date +%s)
    NECESITA_REDIBUJAR=1

    NET_IF=$(get_iface)
    LAST_RX=$(get_rx_bytes)
    LAST_CHECK=$(date +%s)

    rm -f "$MPV_SOCKET"

    mpv --really-quiet \
        --no-video \
        --no-terminal \
        --input-ipc-server="$MPV_SOCKET" \
        "$ACTUAL_URL" >/dev/null 2>&1 &

    PID_MPV=$!

    # Esperar a que el socket exista
    for _ in {1..20}; do
        [ -S "$MPV_SOCKET" ] && break
        sleep 0.05
    done

    mpv_cmd '{ "command": ["set_property", "volume", '"$VOL_ACTUAL"'] }'

    save_state
}

check_player() {
    [ -z "$PID_MPV" ] && return

    now=$(date +%s)

    if [ $((now - LAST_CHECK)) -ge 1 ]; then
        rx=$(get_rx_bytes)
        diff=$((rx - LAST_RX))
        LAST_RX="$rx"
        LAST_CHECK="$now"

        KBPS=$((diff * 8 / 1024))

        if [ "$PAUSADO" = "1" ]; then
            ESTADO="Pausado"
            INFO_STREAM="Pausado"
        elif [ "$KBPS" -gt 0 ]; then
            ESTADO="Reproduciendo"
            INFO_STREAM="${KBPS} kbps"
        else
            ESTADO="Conectando"
        fi

        NECESITA_REDIBUJAR=1
    fi
}

toggle_pause() {
    mpv_cmd '{ "command": ["cycle", "pause"] }'

    if [ "$PAUSADO" = "0" ]; then
        PAUSADO=1
        ESTADO="Pausado"
    else
        PAUSADO=0
        ESTADO="Reproduciendo"
    fi

    NECESITA_REDIBUJAR=1
}

ajustar_volumen() {
    VOL_ACTUAL=$((VOL_ACTUAL + $1))
    ((VOL_ACTUAL < VOL_MIN)) && VOL_ACTUAL=$VOL_MIN
    ((VOL_ACTUAL > VOL_MAX)) && VOL_ACTUAL=$VOL_MAX

    mpv_cmd '{ "command": ["set_property", "volume", '"$VOL_ACTUAL"'] }'

    save_state
    NECESITA_REDIBUJAR=1
}

stop_player() {
    [ -n "$PID_MPV" ] && kill "$PID_MPV" 2>/dev/null
    PID_MPV=""
    rm -f "$MPV_SOCKET"
}
