#!/bin/bash

##############################################################################
# PLAYER (MPV IPC vía UNIX SOCKET)
##############################################################################

PAUSADO=0

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

##############################################################################
# ENTORNO
##############################################################################

# Detectar si estamos en Termux (Android)
ES_TERMUX=0
[ -n "$TERMUX_VERSION" ] && ES_TERMUX=1

##############################################################################
# SOCKET MPV
#
# En Linux de escritorio usamos /tmp (rápido y estándar).
# En Termux / Android, /tmp puede no existir o tener permisos
# inconsistentes. Usamos ~/.cache y creamos el directorio
# explícitamente antes de lanzar mpv.
##############################################################################

if [ "$ES_TERMUX" -eq 1 ]; then
    SOCKET="$HOME/.cache/radio_mpv.sock"
else
    SOCKET="/tmp/radio_mpv.sock"
fi

##############################################################################
# INIT
##############################################################################

init_player() {
    command -v mpv >/dev/null || {
        echo "MPV no está instalado"
        exit 1
    }
}

##############################################################################
# MPV IPC
##############################################################################

mpv_cmd() {
    [ -S "$SOCKET" ] || return

    local resp
    resp=$(printf '%s\n' "$1" | socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null)

    # Solo mostrar errores reales
    echo "$resp" | grep -q '"error":"success"' || echo "$resp" | grep -q '"error":"failure"' && echo "$resp"
}

##############################################################################
# RED / BITRATE (solo Linux PC)
##############################################################################

get_iface() {
    [ "$ES_TERMUX" -eq 1 ] && return
    ip route get 1 2>/dev/null | awk '{print $5; exit}'
}

get_rx_bytes() {
    [ "$ES_TERMUX" -eq 1 ] && echo 0 && return
    awk -v iface="$NET_IF" '$1 ~ iface":" {print $2}' /proc/net/dev
}

##############################################################################
# REPRODUCCIÓN
##############################################################################

reproducir() {
    stop_player
    rm -f "$SOCKET"

    PAUSADO=0
    ACTUAL_NOMBRE="$1"
    ACTUAL_URL="$2"
    ESTADO="Conectando"
    INFO_STREAM="Conectando"
    START_TIME=$(date +%s)
    NECESITA_REDIBUJAR=1

    if [ "$ES_TERMUX" -eq 0 ]; then
        NET_IF=$(get_iface)
        LAST_RX=$(get_rx_bytes)
        LAST_CHECK=$(date +%s)
    fi

    # Asegurar que el directorio del socket existe (crítico en Termux)
    mkdir -p "$(dirname "$SOCKET")"

    mpv --really-quiet \
        --no-video \
        --no-terminal \
        --input-ipc-server="$SOCKET" \
        "$ACTUAL_URL" >/dev/null 2>&1 &

    PID_MPV=$!

    # Esperar a que el socket IPC exista
    for _ in {1..40}; do
        [ -S "$SOCKET" ] && break
        sleep 0.05
    done

    mpv_cmd '{ "command": ["set_property", "volume", '"$VOL_ACTUAL"'] }'
    save_state
}

##############################################################################
# ESTADO
##############################################################################

check_player() {
    [ -z "$PID_MPV" ] && return

    if ! kill -0 "$PID_MPV" 2>/dev/null; then
        PID_MPV=""
        ESTADO="Detenido"
        INFO_STREAM=""
        NECESITA_REDIBUJAR=1
        return
    fi

    if [ "$PAUSADO" = "1" ]; then
        ESTADO="Pausado"
        INFO_STREAM="Pausado"
        return
    fi

    # En Termux no calculamos bitrate (Android bloquea /proc/net)
    if [ "$ES_TERMUX" -eq 1 ]; then
        ESTADO="Reproduciendo"
        INFO_STREAM=""
        NECESITA_REDIBUJAR=1
        return
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
            ESTADO="Conectando"
        fi

        NECESITA_REDIBUJAR=1
    fi
}

##############################################################################
# CONTROLES
##############################################################################

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

##############################################################################
# STOP
##############################################################################

stop_player() {
    [ -n "$PID_MPV" ] && kill "$PID_MPV" 2>/dev/null
    PID_MPV=""
    rm -f "$SOCKET"
}
