#!/bin/bash

##############################################################################
# ESTADO UI
##############################################################################

UI_INIT=0
SHOW_CONTROLS=0

##############################################################################
# COLORES (fallback seguro)
##############################################################################

if tput colors &>/dev/null && [ "$(tput colors)" -ge 8 ]; then
    C_RESET=$(tput sgr0)
    C_TITLE=$(tput setaf 6)
    C_LABEL=$(tput setaf 4)
    C_OK=$(tput setaf 2)
    C_WARN=$(tput setaf 3)
    C_SEL=$(tput rev)
else
    C_RESET=""
    C_TITLE=""
    C_LABEL=""
    C_OK=""
    C_WARN=""
    C_SEL=""
fi

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
            printf "${C_OK}█${C_RESET}"
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

    echo "${C_TITLE}┌──────────────────────────────────────┐${C_RESET}"
    echo "${C_TITLE}│${C_RESET} KEILA Radio Player                   ${C_TITLE}│${C_RESET}"
    echo "${C_TITLE}├──────────────────────────────────────┤${C_RESET}"
    echo "${C_TITLE}│${C_RESET} ${C_LABEL}Emisora :${C_RESET}"
    echo "${C_TITLE}│${C_RESET} ${C_LABEL}Volumen :${C_RESET}"
    echo "${C_TITLE}│${C_RESET} ${C_LABEL}Estado  :${C_RESET}"
    echo "${C_TITLE}└──────────────────────────────────────┘${C_RESET}"

    echo
    echo "${C_LABEL}[c]${C_RESET} Mostrar controles"
    echo
    echo "${C_TITLE}EMISORAS FAVORITAS${C_RESET}"
    echo "──────────────────"

    UI_INIT=1
}

##############################################################################
# CONTROLES
##############################################################################

draw_controls() {
    tput cup 9 0
    tput ed

    echo "${C_TITLE}┌ CONTROLES ────────────────────────────┐${C_RESET}"
    echo "  ↑ ↓     Seleccionar emisora"
    echo "  ← →     Volumen"
    echo "  ENTER   Reproducir"
    echo "  p       Pausa"
    echo "  f       Favorito"
    echo "  m       Mover favorito"
    echo "  e       Todas las emisoras"
    echo "  q       Salir"
    echo "${C_TITLE}└───────────────────────────────────────┘${C_RESET}"
    echo
    echo "${C_TITLE}EMISORAS FAVORITAS${C_RESET}"
    echo "──────────────────"
}

clear_controls() {
    tput cup 9 0
    tput ed
    echo "${C_TITLE}EMISORAS FAVORITAS${C_RESET}"
    echo "──────────────────"
}

##############################################################################
# DIBUJO DINÁMICO
##############################################################################

menu() {
    [ "$UI_INIT" -eq 0 ] && ui_init

    # Emisora
    tput cup 3 12
    tput el
    printf "%s" "$ACTUAL_NOMBRE"

    # Volumen
    tput cup 4 12
    tput el
    barra_vol "$VOL_ACTUAL"

    # Estado
    local linea_estado
    if [ "$ESTADO" = "Reproduciendo" ]; then
        linea_estado="${C_OK}${ESTADO} @ ${INFO_STREAM}${C_RESET}"
    else
        linea_estado="${C_WARN}${ESTADO}${C_RESET}"
    fi

    tput cup 5 12
    tput el
    printf "%s" "$linea_estado"

    # Lista de favoritos
    local start_line
    if [ "$SHOW_CONTROLS" = "1" ]; then
        start_line=19
    else
        start_line=11
    fi

    tput cup "$start_line" 0
    tput ed   # limpia desde aquí hasta el final de la pantalla

    for i in "${!fav_names[@]}"; do
        if [ "$i" -eq "$CURSOR_IDX" ]; then
            printf "${C_SEL} > %2d) %-30s ${C_RESET}\n" \
                "$((i+1))" "${fav_names[$i]}"
        else
            printf "   %2d) %-30s\n" \
                "$((i+1))" "${fav_names[$i]}"
        fi
    done
}
