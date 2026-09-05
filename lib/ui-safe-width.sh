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

# El render responsive puede ocupar exactamente todas las filas del terminal.
# Si el borde inferior también termina en '\n', el terminal hace scroll una
# fila y el siguiente redibujado parece dibujar/desdibujar la primera línea.
# Redefinimos el helper base para omitir únicamente el salto final del marco.
ui_box_rule() {
    local width="$1"
    local left="$2"
    local right="$3"
    local label="${4:-}"
    local label_style="${5:-muted}"
    local inner=$((width - 2))

    ui_style_begin muted
    printf '%s' "$left"
    if [[ -z "$label" ]]; then
        ui_repeat_char "$UI_H" "$inner"
    else
        printf '%s ' "$UI_H"
        ui_style_end
        local label_max=$((inner - 3))
        ((label_max < 1)) && label_max=1
        label=$(ui_truncate "$label" "$label_max")
        ui_style_begin "$label_style"
        printf '%s' "$label"
        ui_style_end
        ui_style_begin muted
        printf ' '
        ui_repeat_char "$UI_H" "$((inner - ${#label} - 3))"
    fi
    printf '%s' "$right"
    ui_style_end

    # El borde inferior es la última línea del frame: no avanzamos a una fila
    # inexistente para evitar que el terminal desplace toda la pantalla.
    if [[ "$left" != "$UI_BL" || "$right" != "$UI_BR" ]]; then
        printf '\n'
    fi
}
