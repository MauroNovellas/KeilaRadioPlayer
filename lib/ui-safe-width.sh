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

# Endurecimiento del auto-update: se carga después del motor base para que la
# validación completa del árbol candidato sustituya a la validación mínima.
# shellcheck source=lib/update-validation.sh
source "$(dirname "${BASH_SOURCE[0]}")/update-validation.sh"

# La capa desktop se carga aquí porque este módulo ya es el último refinamiento
# visual que importa el launcher después del responsive base.
# shellcheck source=lib/ui-desktop.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui-desktop.sh"
# shellcheck source=lib/ui-desktop-primary.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui-desktop-primary.sh"
# shellcheck source=lib/ui-desktop-balance.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui-desktop-balance.sh"
# shellcheck source=lib/ui-update-status.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui-update-status.sh"

# La búsqueda integrada sustituye únicamente el selector de emisoras que usa B.
# El launcher sigue utilizando el mismo app_search_catalog() y puede volver al
# selector fzf con KEILA_FZF_SEARCH=1 durante la transición.
# shellcheck source=lib/app-search.sh
source "$(dirname "${BASH_SOURCE[0]}")/app-search.sh"

# En desktop, Favoritos y búsqueda comparten la columna de navegación. Esta capa
# envuelve la fila ya refinada por el aviso de update.
# shellcheck source=lib/ui-desktop-search-pane.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui-desktop-search-pane.sh"

# Reconexión automática conservadora: se engancha al tick ya refinado por el
# chequeo de updates y envuelve player/recording sin bloquear el loop de input.
# Debe cargarse antes del guard final para conservar ui-terminal-guard como la
# última capa del runtime.
# shellcheck source=lib/app-reconnect.sh
source "$(dirname "${BASH_SOURCE[0]}")/app-reconnect.sh"

# Última protección del terminal: mantiene ECHO desactivado también durante los
# intervalos entre lecturas, IPC y redibujados, y restaura el estado al salir.
# Debe cargarse la última para envolver las versiones finales de enter/suspend/
# resume/leave, incluidos los hooks de actualización.
# shellcheck source=lib/ui-terminal-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui-terminal-guard.sh"
