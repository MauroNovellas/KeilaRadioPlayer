#!/bin/bash

FIFO="/tmp/radio_fifo"
PID_CVLC=""
ACTUAL_NOMBRE="(ninguna)"
ACTUAL_URL=""
ESTADO="Detenido"

init_player() {
    command -v cvlc >/dev/null || {
        echo "VLC no está instalado"; exit 1;
    }
    [ -p "$FIFO" ] || mkfifo "$FIFO"
    exec 3<> "$FIFO"
}

vlc_vol() {
    echo $((VOL_ACTUAL * 256 / 100))
}

reproducir() {
    kill "$PID_CVLC" 2>/dev/null

    ACTUAL_NOMBRE="$1"
    ACTUAL_URL="$2"
    ESTADO="Reproduciendo"

    cvlc --quiet --extraintf rc --rc-fake-tty "$2" <"$FIFO" >/dev/null 2>&1 &
    PID_CVLC=$!

    echo "volume $(vlc_vol)" >&3
    save_state
}

toggle_pause() {
    echo "pause" >&3
    [ "$ESTADO" = "Reproduciendo" ] && ESTADO="Pausado" || ESTADO="Reproduciendo"
}

ajustar_volumen() {
    VOL_ACTUAL=$((VOL_ACTUAL + $1))
    ((VOL_ACTUAL < VOL_MIN)) && VOL_ACTUAL=$VOL_MIN
    ((VOL_ACTUAL > VOL_MAX)) && VOL_ACTUAL=$VOL_MAX
    echo "volume $(vlc_vol)" >&3
    save_state
}

stop_player() {
    kill "$PID_CVLC" 2>/dev/null
    rm -f "$FIFO"
}
