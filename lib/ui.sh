#!/bin/bash

SPINNER=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
SPIN_IDX=0

barra_vol() {
    local v=$1 t=20 l=$((v*t/100))
    printf "["
    printf "█%.0s" $(seq 1 $l)
    printf "░%.0s" $(seq 1 $((t-l)))
    printf "] %d%%" "$v"
}

spinner_char() {
    c="${SPINNER[$SPIN_IDX]}"
    SPIN_IDX=$(( (SPIN_IDX + 1) % ${#SPINNER[@]} ))
    echo "$c"
}

cabecera() {
    clear
    echo "────────────────────────────────"
    echo " Radio.sh"
    echo " Emisora : $ACTUAL_NOMBRE"
    printf " Volumen : "; barra_vol "$VOL_ACTUAL"; echo

    if [ "$ESTADO" = "Conectando..." ]; then
        echo " Estado  : $(spinner_char) Conectando..."
    else
        echo " Estado  : $ESTADO"
    fi

    echo " Info    : ${INFO_STREAM:-N/A}"
    echo "────────────────────────────────"
    echo
}

menu() {
    cabecera
    echo "EMISORAS FAVORITAS"
    echo "------------------"

    for i in "${!fav_names[@]}"; do
        if [ "$i" -eq "$CURSOR_IDX" ]; then
            printf "> %d) %s\n" "$((i+1))" "${fav_names[$i]}"
        else
            printf "  %d) %s\n" "$((i+1))" "${fav_names[$i]}"
        fi
    done

    echo

    if [ "$MODO_MOVER" = "1" ]; then
        echo "MODO MOVER: ↑ ↓ desplazar | Enter confirmar | q cancelar"
    else
        echo "↑ ↓ navegar | ← → volumen | Enter reproducir"
        echo "1..9 seleccionar | m mover | f favorito | e explorar | q salir"
    fi
}
