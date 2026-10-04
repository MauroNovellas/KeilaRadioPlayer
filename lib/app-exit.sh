#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

APP_EXIT_CLEANING=0
APP_EXIT_CONFIRM_ACTIVE=0
APP_EXIT_CANCEL_PENDING=0
APP_EXIT_INTERRUPT_PENDING=0

# Un único punto de confirmación para Q (también reasignada), las pantallas
# hijas que solicitan salir y Ctrl-C. Nunca detiene el audio antes de confirmar.
app_confirm_exit() {
    ((APP_EXIT_CONFIRM_ACTIVE == 0)) || return 1
    local APP_EXIT_CONFIRM_ACTIVE=1 APP_EXIT_CANCEL_PENDING=0
    local PREFERENCES_ACTIVE=1 SEARCH_ACTIVE=0
    local PANEL_PARENT_PATH='' PANEL_PATH='' PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    local PANEL_FORM=0 PANEL_FULL_WIDTH=0 PANEL_BADGE_MAX_WIDTH=0
    local -a PANEL_ROWS=()
    local selected=0 offset=0 redraw=1 notice=''

    panel_add_row N 'Seguir escuchando' 'Cancela el cierre y vuelve a la pantalla anterior.'
    panel_add_row S Salir 'Cierra la grabación en curso, libera el audio y deja la terminal limpia. Las alarmas y reservas temporales necesitan Keila abierto.'
    while true; do
        if ((redraw)); then
            notice='La opción inicial mantiene Keila abierto.'
            if ((${RECORDING_ACTIVE:-0})); then
                notice='Hay una grabación en curso: se cerrará y conservará al salir.'
            elif [[ ${RECORD_PLAN_STATE:-idle} == pending ]]; then
                notice='Hay una grabación programada: no se ejecutará si sales.'
            elif ((${ALARM_AT:-0})); then
                notice='La alarma temporal no sonará si sales.'
            fi
            panel_draw 'SALIR DE KEILA' "$selected" "$offset" 'Enter elige | S sale | N/Esc cancela' "$notice"
            selected=$PANEL_SELECTED offset=$PANEL_SCROLL
        fi
        input_read || return 1
        ((APP_EXIT_CANCEL_PENDING == 0)) || return 1
        redraw=1
        case "$INPUT_EVENT" in
            ESC|LEFT) return 1 ;;
            ENTER) return "$((selected != 1))" ;;
            KEY)
                case "$INPUT_KEY" in
                    s|S) return 0 ;;
                    n|N) return 1 ;;
                    *) redraw=0 ;;
                esac
                ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            RESIZE) ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$INPUT_EVENT" "$selected" 2 "$PANEL_VISIBLE"
                selected=$PANEL_SELECTED
                ;;
            *) redraw=0 ;;
        esac
    done
}

app_interrupt_exit() {
    # Una segunda interrupción cancela el cuadro; no confirma ni lo anida.
    ((APP_EXIT_CLEANING == 0)) || return 0
    if ((APP_EXIT_CONFIRM_ACTIVE)); then
        APP_EXIT_CANCEL_PENDING=1
        return 0
    fi
    # Una tubería, una ventana cerrada o una herramienta externa no tienen
    # una TUI en la que preguntar. Conservamos el cierre habitual de señales.
    if ((!${UI_ACTIVE:-0} || ${UI_SUSPENDED:-0})) || [[ ! -t 0 || ! -t 1 ]]; then
        exit 130
    fi
    # No leer teclado dentro del trap: Bash aplaza señales repetidas mientras
    # ejecuta un manejador. El próximo read atiende la solicitud fuera del trap.
    APP_EXIT_INTERRUPT_PENDING=1
}

app_process_interrupt_exit() {
    APP_EXIT_INTERRUPT_PENDING=0
    if app_confirm_exit; then exit 130; fi
    # El menú o editor interrumpido conserva sus locales y se vuelve a pintar.
    INPUT_RESIZE_PENDING=0
    INPUT_EVENT=RESIZE INPUT_KEY='' INPUT_REPEAT_COUNT=1
}
