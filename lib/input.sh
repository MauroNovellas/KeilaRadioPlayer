#!/bin/bash

NECESITA_REDIBUJAR=1
MENU_INDEX=0

load_favorites() {
    fav_names=()
    fav_urls=()
    [ -f "$FAVORITAS" ] || return
    while IFS="|" read -r n u; do
        fav_names+=("$n")
        fav_urls+=("$u")
    done < "$FAVORITAS"
}

save_favorites() {
    : > "$FAVORITAS"
    for i in "${!fav_names[@]}"; do
        echo "${fav_names[$i]}|${fav_urls[$i]}" >> "$FAVORITAS"
    done
}

is_favorite() {
    for u in "${fav_urls[@]}"; do
        [ "$u" = "$1" ] && return 0
    done
    return 1
}

toggle_fav() {
    [ -z "$ACTUAL_URL" ] && return

    for i in "${!fav_urls[@]}"; do
        if [ "${fav_urls[$i]}" = "$ACTUAL_URL" ]; then
            echo
            echo "Quitar \"${ACTUAL_NOMBRE}\" de favoritos? (s = sí)"
            read -rsn1 key
            [[ "$key" =~ [sS] ]] || { NECESITA_REDIBUJAR=1; return; }

            unset fav_names[$i] fav_urls[$i]
            fav_names=("${fav_names[@]}")
            fav_urls=("${fav_urls[@]}")
            save_favorites

            mensaje_estado "Quitada de favoritos: ${ACTUAL_NOMBRE}"
            return
        fi
    done

    fav_names+=("$ACTUAL_NOMBRE")
    fav_urls+=("$ACTUAL_URL")
    save_favorites
    mensaje_estado "Añadida a favoritos: ${ACTUAL_NOMBRE}"
}

leer_tecla() {
    read -rsn1 key
    echo "$key"
}

menu() {
    cabecera
    echo
    echo "RADIO FAVORITAS"
    echo "---------------"

    for i in "${!fav_names[@]}"; do
        if [ "$i" -eq "$MENU_INDEX" ]; then
            echo "> $((i+1))) ${fav_names[$i]}"
        else
            echo "  $((i+1))) ${fav_names[$i]}"
        fi
    done

    echo
    echo "0) Explorar emisoras"
    echo "f) Favorito   p) Pausa   +/- Volumen   q) Salir"
    echo

    if [ -n "$STATUS_MSG" ]; then
        echo "$STATUS_MSG"
        STATUS_TIMER=$((STATUS_TIMER - 1))
        [ "$STATUS_TIMER" -le 0 ] && STATUS_MSG=""
    fi
}

handle_arrow_keys() {
    case "$1" in
        A) ((MENU_INDEX--)) ;;   # ↑
        B) ((MENU_INDEX++)) ;;   # ↓
        C) ajustar_volumen 5 ;;  # →
        D) ajustar_volumen -5 ;; # ←
    esac

    [ "$MENU_INDEX" -lt 0 ] && MENU_INDEX=0
    [ "$MENU_INDEX" -ge "${#fav_names[@]}" ] && MENU_INDEX=$((${#fav_names[@]} - 1))

    NECESITA_REDIBUJAR=1
}
