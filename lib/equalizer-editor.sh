#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

equalizer_editor_draw() {
    local i gain preset
    local -a PANEL_ROWS=() names=('Graves' 'Medios graves' 'Medios' 'Medios agudos' 'Agudos')
    preset=$(equalizer_current_preset)
    for i in "${!EQUALIZER_GAINS[@]}"; do
        printf -v gain '%+d dB' "${EQUALIZER_GAINS[i]}"
        panel_add_row '' "${names[i]}" "Banda ${EQUALIZER_LABELS[i]}: $gain. Izquierda/derecha seleccionan banda; arriba/abajo cambian su ganancia. Presets: 1 Plano, 2 Rock, 3 Pop, 4 Jazz, 5 Voz. C centra la banda; R deja todas planas. Se aplica y guarda al editar. Enter o Esc vuelve." "$gain"
    done
    panel_draw ECUALIZADOR "$EQUALIZER_SELECTED" "${EQUALIZER_SCROLL:-0}" 'Izq/Der banda | Arr/Ab ganancia | Esc volver' "${UI_MESSAGE:-}" "Preset: $preset | Cambios al editar"
    EQUALIZER_SCROLL=$PANEL_SCROLL
}

app_edit_equalizer() {
    local previous_help=$UI_HELP_VISIBLE previous_preferences=$PREFERENCES_ACTIVE result=0
    local EQUALIZER_SCROLL=0 redraw=1
    UI_HELP_VISIBLE=0 EQUALIZER_EDITOR_ACTIVE=1 PREFERENCES_ACTIVE=1
    ui_clear_message
    while true; do
        ((redraw)) && equalizer_editor_draw
        input_read || { result=1; break; }
        redraw=1
        case "$INPUT_EVENT" in
            LEFT) EQUALIZER_SELECTED=$(((EQUALIZER_SELECTED + 4) % 5)) ;;
            RIGHT) EQUALIZER_SELECTED=$(((EQUALIZER_SELECTED + 1) % 5)) ;;
            HOME) EQUALIZER_SELECTED=0 ;;
            END) EQUALIZER_SELECTED=4 ;;
            UP) equalizer_change_selected 1 || app_message 'No se pudo aplicar o guardar el ecualizador.' 5 ;;
            DOWN) equalizer_change_selected -1 || app_message 'No se pudo aplicar o guardar el ecualizador.' 5 ;;
            KEY)
                case "$INPUT_KEY" in
                    r|R) equalizer_reset || app_message 'No se pudo restablecer el ecualizador.' 5 ;;
                    c|C) equalizer_center_selected || app_message 'No se pudo centrar la banda.' 5 ;;
                    [1-5])
                        if equalizer_apply_preset "$INPUT_KEY"; then app_message "Preset: $(equalizer_preset_name "$INPUT_KEY")" 4
                        else app_message 'No se pudo aplicar el preset.' 5; fi ;;
                    '?')
                        local -a PANEL_ROWS=()
                        local i
                        for i in "${!EQUALIZER_GAINS[@]}"; do panel_add_row '' "${EQUALIZER_LABELS[i]}" 'Izquierda/derecha seleccionan banda; arriba/abajo ajustan. 1 Plano, 2 Rock, 3 Pop, 4 Jazz, 5 Voz. C centra; R plano. Los cambios se guardan al editar. Enter o Esc vuelve.'; done
                        panel_detail ECUALIZADOR "$EQUALIZER_SELECTED" ;;
                    z|Z) break ;;
                esac ;;
            ENTER|ESC) break ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            RESIZE) ;;
        esac
    done
    EQUALIZER_EDITOR_ACTIVE=0 UI_HELP_VISIBLE=$previous_help PREFERENCES_ACTIVE=$previous_preferences
    ((previous_preferences)) || ui_draw
    return "$result"
}
