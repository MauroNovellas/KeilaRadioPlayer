#!/bin/bash

SPINNER=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
SPIN_IDX=0
UI_INIT=0

##############################################################################
# DIBUJOS
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

spinner() {
    printf "%s" "${SPINNER[$SPIN_IDX]}"
    SPIN_IDX=$(( (SPIN_IDX + 1) % ${#SPINNER[@]} ))
}

##############################################################################
# UI
##############################################################################

ui_init() {
    clear
    tput civis

    echo "────────────────────────────────"
    echo " Radio.sh"
    echo " Emisora :"
    echo " Volumen :"
    echo " Estado  :"
    echo " Info    :"
    echo "────────────────────────────────"
    echo

    UI_INIT=1
}

menu() {
    [ "$UI_INIT" -eq 0 ] && ui_init

    # Emisora
    tput cup 2 10
    printf "\033[K%s" "$ACTUAL_NOMBRE"

    # Volumen (BORRADO REAL)
    tput cup 3 10
    printf "\033[K"
    barra_vol "$VOL_ACTUAL"

    # Estado + spinner
    tput cup 4 10
    printf "\033[K"
    if [ "$ESTADO" = "Conectando" ]; then
        spinner
        printf " Conectando"
    else
        printf "%s" "$ESTADO"
    fi

    # Info
    tput cup 5 10
    printf "\033[K%s" "${INFO_STREAM:-}"

    # Lista
    tput cup 7 0
    printf "\033[J"

    echo "EMISORAS FAVORITAS"
    echo "------------------"

    for i in "${!fav_names[@]}"; do
        if [ "$i" -eq "$CURSOR_IDX" ]; then
            printf "> %d) %s\n" "$((i+1))" "${fav_names[$i]}"
        else
            printf "  %d) %s\n" "$((i+1))" "${fav_names[$i]}"
        fi
    done
}
