#!/usr/bin/env bash

# Evita dibujar hasta la última columna física del terminal. Muchos emuladores
# activan autowrap al escribir en esa celda y el siguiente salto de línea puede
# producir una fila fantasma durante los redibujados de la TUI.
#
# En modo wide (PC) usamos todo el ancho útil del terminal: solo reservamos una
# columna física de seguridad. Los demás modos conservan sus límites actuales.
ui_layout_width() {
    local terminal_cols="${1:-$UI_COLS}"
    local width

    [[ "$terminal_cols" =~ ^[0-9]+$ ]] || terminal_cols=80
    width=$terminal_cols

    case "${UI_LAYOUT_MODE:-standard}" in
        wide)
            # Desktop: aprovechar todo el ancho disponible sin tocar la última
            # celda física, que es la que puede disparar autowrap.
            ((terminal_cols > 1)) && width=$((terminal_cols - 1))
            ;;
        standard)
            ((width > 78)) && width=78
            if ((width >= terminal_cols && terminal_cols > 1)); then
                width=$((terminal_cols - 1))
            fi
            ;;
        *)
            if ((width >= terminal_cols && terminal_cols > 1)); then
                width=$((terminal_cols - 1))
            fi
            ;;
    esac

    printf '%s\n' "$width"
}

# En el layout ancho hacemos crecer también la barra de volumen para que el
# espacio adicional sea útil y no solo un marco más largo. En el resto de modos
# conservamos la geometría anterior.
ui_volume_bar_width() {
    local width="$1"
    local bar

    if [[ "${UI_LAYOUT_MODE:-standard}" == 'wide' ]]; then
        bar=$((width - 48))
        ((bar < 20)) && bar=20
        ((bar > 48)) && bar=48
    else
        bar=$((width - 42))
        ((bar < 12)) && bar=12
        ((bar > 28)) && bar=28
    fi

    printf '%s\n' "$bar"
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

# La capa desktop se carga aquí porque este módulo ya es el último refinamiento
# visual que importa el launcher después del responsive base.
# shellcheck source=lib/ui-desktop.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui-desktop.sh"
# shellcheck source=lib/ui-desktop-primary.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui-desktop-primary.sh"
# shellcheck source=lib/ui-desktop-balance.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui-desktop-balance.sh"
