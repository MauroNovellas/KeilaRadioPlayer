#!/usr/bin/env bash

app_edit_equalizer() {
    local previous_help=$UI_HELP_VISIBLE
    UI_HELP_VISIBLE=0
    EQUALIZER_EDITOR_ACTIVE=1
    ui_clear_message

    while true; do
        ui_draw
        if ! input_read; then
            EQUALIZER_EDITOR_ACTIVE=0
            UI_HELP_VISIBLE=$previous_help
            ui_clear_message
            return 1
        fi

        case "$INPUT_EVENT" in
            LEFT) EQUALIZER_SELECTED=$(((EQUALIZER_SELECTED + 4) % 5)) ;;
            RIGHT) EQUALIZER_SELECTED=$(((EQUALIZER_SELECTED + 1) % 5)) ;;
            UP) equalizer_change_selected 1 || app_message 'No se pudo aplicar el ecualizador.' 5 ;;
            DOWN) equalizer_change_selected -1 || app_message 'No se pudo aplicar el ecualizador.' 5 ;;
            KEY)
                case "$INPUT_KEY" in
                    r|R) equalizer_reset || app_message 'No se pudo restablecer el ecualizador.' 5 ;;
                    c|C) equalizer_center_selected || app_message 'No se pudo centrar la banda.' 5 ;;
                    z|Z)
                        EQUALIZER_EDITOR_ACTIVE=0
                        UI_HELP_VISIBLE=$previous_help
                        ui_clear_message
                        return 0
                        ;;
                esac
                ;;
            ENTER|ESC)
                EQUALIZER_EDITOR_ACTIVE=0
                UI_HELP_VISIBLE=$previous_help
                ui_clear_message
                return 0
                ;;
            TICK) app_poll_player || true; catalog_poll || true; ui_message_tick || true ;;
        esac
    done
}
