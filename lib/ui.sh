#!/bin/bash

UI_SELECTED=1
STATUS_MSG=""
STATUS_TIMER=0

draw_volume_bar() {
    local vol="$1"
    local max=10
    local filled=$((vol * max / 100))
    local empty=$((max - filled))

    printf "["
    printf "%0.s#" $(seq 1 "$filled")
    printf "%0.s-" $(seq 1 "$empty")
    printf "] %3s%%" "$vol"
}

status_line() {
    echo "──────────────────────────────────────────────"
    printf "Estas escuchando: %s\n" "${ACTUAL_NOMBRE:-Ninguna}"
    printf "Volumen: "
    draw_volume_bar "$VOLUMEN"
    echo
    printf "Estado: %s\n" "${ESTADO:-Parado}"
    echo "──────────────────────────────────────────────"
}

cabecera() {
    clear
    status_line
}

mensaje_estado() {
    STATUS_MSG="$1"
    STATUS_TIMER=2
    NECESITA_REDIBUJAR=1
}