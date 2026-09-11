#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Menú jerárquico de opciones para usuarios que no quieren memorizar atajos.

OPTIONS_ACTIVE=0
OPTIONS_SELECTED=0
OPTIONS_SCROLL=0

options_draw() {
    ui_refresh_size
    local width=$((UI_COLS - 1)) height=$((UI_LINES - 6)) visible i row_index row label detail marker
    ((width < 1)) && width=1
    ((height < 1)) && height=1

    local -a rows=(
        'V|Visualización|Espectrograma, colores, Unicode y ajustes visuales'
        'T|Temporizador|Alarma temporal; base para apagado automático'
        'G|Grabaciones|Revisar, comprobar, escuchar y proteger grabaciones'
        'S|Sesión|Ver el TXT de canciones reproducidas en esta ejecución'
        'C|Configuración|Preferencias y atajos personalizables'
        'D|Diagnóstico|Estado del reproductor, catálogo, rutas y grabaciones'
        'H|Ayuda|Atajos completos y controles locales'
    )

    ((OPTIONS_SELECTED < 0)) && OPTIONS_SELECTED=0
    ((OPTIONS_SELECTED >= ${#rows[@]})) && OPTIONS_SELECTED=$((${#rows[@]} - 1))
    visible=$((height / 2))
    ((visible < 1)) && visible=1
    ((visible > ${#rows[@]})) && visible=${#rows[@]}
    ((OPTIONS_SELECTED < OPTIONS_SCROLL)) && OPTIONS_SCROLL=$OPTIONS_SELECTED
    ((OPTIONS_SELECTED >= OPTIONS_SCROLL + visible)) && OPTIONS_SCROLL=$((OPTIONS_SELECTED - visible + 1))

    tput cup 0 0 2>/dev/null || true
    ui_print_styled_padded "$width" 'KEILA · OPCIONES' title
    printf '\n'
    ui_print_padded "$width" 'Elige una categoría. Esc vuelve al reproductor.'
    printf '\n\n'

    for ((i = 0; i < visible; i++)); do
        row_index=$((OPTIONS_SCROLL + i))
        ((row_index < ${#rows[@]})) || break
        row=${rows[row_index]}
        label=${row%%|*}
        detail=${row#*|}
        label=${detail%%|*}
        detail=${detail#*|}
        marker='  '
        ((row_index == OPTIONS_SELECTED)) && marker='> '
        ui_print_styled_padded "$width" "${marker}[${row%%|*}] $label" accent
        printf '\n'
        ui_print_padded "$width" "    $detail"
        printf '\n'
    done

    ui_print_padded "$width" '↑↓ seleccionar · Enter abrir · V/T/G/S/C/D/H directo · Esc volver'
    printf '\n'
    ui_print_padded "$width" "${UI_MESSAGE:-}"
    tput ed 2>/dev/null || true
}

options_open_selected() {
    case "$OPTIONS_SELECTED" in
        0) app_preferences_menu settings ;;
        1) app_edit_alarm || true ;;
        2) app_pending_menu || true ;;
        3) app_session_history_screen || true ;;
        4) app_preferences_menu settings ;;
        5) app_status_screen || true ;;
        6) app_preferences_menu help ;;
    esac
    PREFERENCES_ACTIVE=1
    OPTIONS_ACTIVE=1
}

options_key_select() {
    case "${1,,}" in
        v) OPTIONS_SELECTED=0; return 0 ;;
        t) OPTIONS_SELECTED=1; return 0 ;;
        g) OPTIONS_SELECTED=2; return 0 ;;
        s) OPTIONS_SELECTED=3; return 0 ;;
        c) OPTIONS_SELECTED=4; return 0 ;;
        d) OPTIONS_SELECTED=5; return 0 ;;
        h) OPTIONS_SELECTED=6; return 0 ;;
    esac
    return 1
}

app_options_menu() {
    local event key redraw=1
    OPTIONS_ACTIVE=1
    OPTIONS_SELECTED=${OPTIONS_SELECTED:-0}
    PREFERENCES_ACTIVE=1

    while true; do
        ((redraw)) && options_draw
        input_read || break
        event=$INPUT_EVENT
        key=$INPUT_KEY
        redraw=1

        case "$event" in
            TICK)
                redraw=0
                app_poll_player && redraw=1
                catalog_poll && redraw=1
                ui_message_tick && redraw=1
                ;;
            ESC)
                break
                ;;
            UP)
                ((OPTIONS_SELECTED > 0)) && ((OPTIONS_SELECTED -= 1))
                ;;
            DOWN)
                ((OPTIONS_SELECTED < 6)) && ((OPTIONS_SELECTED += 1))
                ;;
            HOME)
                OPTIONS_SELECTED=0
                ;;
            END)
                OPTIONS_SELECTED=6
                ;;
            ENTER)
                options_open_selected
                redraw=1
                ;;
            KEY)
                if options_key_select "$key"; then
                    options_open_selected
                    redraw=1
                fi
                ;;
        esac
    done

    PREFERENCES_ACTIVE=0
    OPTIONS_ACTIVE=0
    ui_draw
}
