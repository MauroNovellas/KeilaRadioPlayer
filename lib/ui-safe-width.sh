#!/usr/bin/env bash

# Evita dibujar hasta la última columna física del terminal. Muchos emuladores
# activan autowrap al escribir en esa celda y el siguiente salto de línea puede
# producir una fila fantasma durante los redibujados de la TUI.

ui_layout_width() {
    local terminal_cols="${1:-$UI_COLS}"
    local width

    [[ "$terminal_cols" =~ ^[0-9]+$ ]] || terminal_cols=80
    width=$terminal_cols

    case "${UI_LAYOUT_MODE:-standard}" in
        wide)
            ((width > 92)) && width=92
            ;;
        standard)
            ((width > 78)) && width=78
            ;;
    esac

    if ((width >= terminal_cols && terminal_cols > 1)); then
        width=$((terminal_cols - 1))
    fi

    printf '%s\n' "$width"
}
