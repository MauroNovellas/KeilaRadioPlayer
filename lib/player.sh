#!/bin/bash

PAUSADO=0

FIFO="/tmp/radio_fifo"

PID_CVLC=""
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
    command -v cvlc >/dev/null || {
        echo "VLC no está instalado"
        exit 1
    }

    [ -p "$FIFO" ] || mkfifo "$FIFO"
    exec 3<> "$FIFO"
}

vlc_vol() {
    echo $((VOL_ACTUAL * 256 / 100))
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

    cvlc --quiet --extraintf rc --rc-fake-tty "$ACTUAL_URL" \
        <"$FIFO" >/dev/null 2>&1 &

    PID_CVLC=$!
    echo "volume $(vlc_vol)" >&3
    save_state
}

check_player() {
    [ -z "$PID_CVLC" ] && return

    if [ "$PAUSADO" = "1" ]; then
        ESTADO="Pausado"
        INFO_STREAM="Pausado"
    else
        if [ "$KBPS" -gt 0 ]; then
            ESTADO="Reproduciendo"
            INFO_STREAM="${KBPS} kbps"
        else
            INFO_STREAM="Conectando"
        fi
    fi


    now=$(date +%s)

    if [ $((now - LAST_CHECK)) -ge 1 ]; then
        rx=$(get_rx_bytes)
        diff=$((rx - LAST_RX))
        LAST_RX="$rx"
        LAST_CHECK="$now"

        KBPS=$((diff * 8 / 1024))

        if [ "$KBPS" -gt 0 ]; then
            ESTADO="Reproduciendo"
            INFO_STREAM="${KBPS} kbps"
        else
            INFO_STREAM="Conectando"
        fi

        NECESITA_REDIBUJAR=1
    fi
}

toggle_pause() {
    echo "pause" >&3

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
    echo "volume $(vlc_vol)" >&3
    save_state
    NECESITA_REDIBUJAR=1
}

stop_player() {
    [ -n "$PID_CVLC" ] && kill "$PID_CVLC" 2>/dev/null
    PID_CVLC=""
}
