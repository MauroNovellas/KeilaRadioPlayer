#!/usr/bin/env bash

app_edit_equalizer() {
    local previous_help=$UI_HELP_VISIBLE
    UI_HELP_VISIBLE=0
    EQUALIZER_EDITOR_ACTIVE=1

    while true; do
        local selected_gain
        printf -v selected_gain '%+d' "${EQUALIZER_GAINS[EQUALIZER_SELECTED]}"
        app_message "EQ ${EQUALIZER_LABELS[EQUALIZER_SELECTED]}: ${selected_gain} dB  ·  $(equalizer_summary)" 0
        ui_draw
        if ! input_read; then
            EQUALIZER_EDITOR_ACTIVE=0
            UI_HELP_VISIBLE=$previous_help
            ui_clear_message
            return 1
        fi

        case "$INPUT_EVENT" in
            UP) EQUALIZER_SELECTED=$(((EQUALIZER_SELECTED + 4) % 5)) ;;
            DOWN) EQUALIZER_SELECTED=$(((EQUALIZER_SELECTED + 1) % 5)) ;;
            LEFT) equalizer_change_selected -1 || app_message 'No se pudo aplicar el ecualizador.' 5 ;;
            RIGHT) equalizer_change_selected 1 || app_message 'No se pudo aplicar el ecualizador.' 5 ;;
            KEY)
                case "$INPUT_KEY" in
                    r|R) equalizer_reset || app_message 'No se pudo restablecer el ecualizador.' 5 ;;
                    c|C) equalizer_center_selected || app_message 'No se pudo centrar la banda.' 5 ;;
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
