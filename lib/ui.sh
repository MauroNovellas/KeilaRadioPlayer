#!/bin/bash

UI_INIT=0
SHOW_CONTROLS=0

##############################################################################
# UTILIDADES DE DIBUJO
##############################################################################

barra_vol() {
    local v=$1
    local w=20
    local f=$((v * w / 100))

    printf "["
    for ((i=0;i<w;i++)); do
        if [ "$i" -lt "$f" ]; then
            printf "█"
        else
            printf "░"
        fi
    done
    printf "] %3d%%" "$v"
}

##############################################################################
# UI FIJA
##############################################################################

ui_init() {
    clear
    tput civis

    # Cabecera fija
    echo "────────────────────────────────"
    echo " Radio.sh"
    echo " Emisora :"
    echo " Volumen :"
    echo " Estado  :"
    echo " Info    :"
    echo "────────────────────────────────"
    echo " Controles: [c]"
    echo

    # Zona inferior inicial
    echo "EMISORAS FAVORITAS"
    echo "------------------"

    UI_INIT=1
}

##############################################################################
# CONTROLES (TOGGLE CON 'c')
##############################################################################

draw_controls() {
    # Limpiamos desde línea 7 hacia abajo
    tput cup 7 0
    printf "\033[J"

    echo " Controles"
    echo " ---------"
    echo " ↑ ↓   Seleccionar emisora"
    echo " ← →   Volumen"
    echo " ENTER Reproducir"
    echo " p     Pausa"
    echo " f     Favorito"
    echo " m     Mover favorito"
    echo " e     Todas las emisoras"
    echo " q     Salir"
    echo
    echo "EMISORAS FAVORITAS"
    echo "------------------"
}

clear_controls() {
    tput cup 7 0
    printf "\033[J"

    echo "EMISORAS FAVORITAS"
    echo "------------------"
}

##############################################################################
# DIBUJO DINÁMICO
##############################################################################

menu() {
    [ "$UI_INIT" -eq 0 ] && ui_init

    # Emisora
    tput cup 2 10
    printf "\033[K%s" "$ACTUAL_NOMBRE"

    # Volumen
    tput cup 3 10
    printf "\033[K"
    barra_vol "$VOL_ACTUAL"

    # Estado
    tput cup 4 10
    printf "\033[K%s" "$ESTADO"

    # Info
    tput cup 5 10
    printf "\033[K%s" "${INFO_STREAM:-}"

    # Lista de favoritos (empieza SIEMPRE en la misma línea)
    local start_line
    if [ "$SHOW_CONTROLS" = "1" ]; then
        start_line=17
    else
        start_line=9
    fi

    tput cup "$start_line" 0
    printf "\033[J"

    for i in "${!fav_names[@]}"; do
        if [ "$i" -eq "$CURSOR_IDX" ]; then
            printf "> %d) %s\n" "$((i+1))" "${fav_names[$i]}"
        else
            printf "  %d) %s\n" "$((i+1))" "${fav_names[$i]}"
        fi
    done
}
