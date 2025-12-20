#!/bin/bash

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

EMISORAS="$BASE_DIR/emisoras.txt"
FAVORITAS="$BASE_DIR/emisorasFavoritas.txt"

source "$BASE_DIR/lib/ui.sh"
source "$BASE_DIR/lib/input.sh"
source "$BASE_DIR/lib/player.sh"
source "$BASE_DIR/lib/explorar.sh"


load_favorites

while true; do
    if [ "$NECESITA_REDIBUJAR" = "1" ]; then
        menu
        NECESITA_REDIBUJAR=0
    fi

    key=$(leer_tecla)

    case "$key" in
        $'\e')
            read -rsn2 seq
            handle_arrow_keys "${seq:1:1}"
            ;;
        "")
            if [ -n "${fav_urls[$MENU_INDEX]}" ]; then
                reproducir "${fav_names[$MENU_INDEX]}" "${fav_urls[$MENU_INDEX]}"
                NECESITA_REDIBUJAR=1
            fi
            ;;
        q) exit 0 ;;
        f) toggle_fav ;;
        p) toggle_pause; NECESITA_REDIBUJAR=1 ;;
        +) ajustar_volumen 5; NECESITA_REDIBUJAR=1 ;;
        -) ajustar_volumen -5; NECESITA_REDIBUJAR=1 ;;
        0) explorar_emisoras ;;
    esac
done
