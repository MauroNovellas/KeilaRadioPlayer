#!/bin/bash

VLC_SOCKET="/tmp/radio_vlc.sock"
VOLUMEN_FILE="$BASE_DIR/.volumen"
LAST_FILE="$BASE_DIR/.ultima"

VOLUMEN=$(cat "$VOLUMEN_FILE" 2>/dev/null || echo 50)
ESTADO="Parado"

start_vlc() {
    rm -f "$VLC_SOCKET"

    vlc -I dummy \
        --extraintf rc \
        --rc-unix "$VLC_SOCKET" \
        --rc-quiet \
        --no-video \
        --volume "$VOLUMEN" \
        "$1" >/dev/null 2>&1 &

    VLC_PID=$!
    sleep 0.3
}

reproducir() {
    ACTUAL_NOMBRE="$1"
    ACTUAL_URL="$2"

    echo "$ACTUAL_NOMBRE|$ACTUAL_URL" > "$LAST_FILE"

    if [ -S "$VLC_SOCKET" ]; then
        echo "stop" | socat - UNIX-CONNECT:"$VLC_SOCKET" >/dev/null
    fi

    start_vlc "$ACTUAL_URL"
    ESTADO="Reproduciendo"
}

toggle_pause() {
    [ ! -S "$VLC_SOCKET" ] && return
    echo "pause" | socat - UNIX-CONNECT:"$VLC_SOCKET" >/dev/null

    if [ "$ESTADO" = "Reproduciendo" ]; then
        ESTADO="Pausado"
    else
        ESTADO="Reproduciendo"
    fi
}

ajustar_volumen() {
    local delta="$1"
    VOLUMEN=$((VOLUMEN + delta))
    [ "$VOLUMEN" -lt 0 ] && VOLUMEN=0
    [ "$VOLUMEN" -gt 100 ] && VOLUMEN=100

    echo "$VOLUMEN" > "$VOLUMEN_FILE"

    if [ -S "$VLC_SOCKET" ]; then
        echo "volume $VOLUMEN" | socat - UNIX-CONNECT:"$VLC_SOCKET" >/dev/null
    fi

    NECESITA_REDIBUJAR=1
}