#!/bin/bash

cleanup() {
    tput cnorm
    tput sgr0
    clear
}

tput civis
trap cleanup INT TERM EXIT

# Calcular ruta del proyecto y entrar en ella
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE_DIR"

LIB="$BASE_DIR/lib"
UI_C="$BASE_DIR/lib_c/ui_ncurses"

# Exportar BASE_DIR para que ui.c pueda usarlo si lo necesita
export BASE_DIR

# Cargar configuración
source "$LIB/config.sh"

# Exportar ruta de favoritos para ui.c
export KEILA_FAVORITAS="$FAVORITAS"

# Cargar módulos
source "$LIB/state.sh"
source "$LIB/deps.sh"
source "$LIB/player.sh"
source "$LIB/search.sh"

comprobar_dependencias
init_state
init_player
load_state

while true; do
    cmd=$("$UI_C" </dev/tty 2>/dev/tty)


    echo "DEBUG CMD = '$cmd'"
    sleep 1

    IFS="|" read -r action name url <<< "$cmd"

    case "$action" in
        PLAY)
            reproducir "$name" "$url"
            ;;
        EXIT)
            stop_player
            exit 0
            ;;
    esac
done
