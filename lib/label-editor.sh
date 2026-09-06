#!/usr/bin/env bash

# Editor en la pantalla actual: Enter guarda, Esc cancela, Ctrl-U vacía.
app_edit_label() {
    favorites_load || return 1
    ui_sync_selection
    if ((UI_SELECTED_INDEX >= ${#FAVORITE_URLS[@]} || ${#FAVORITE_URLS[@]} == 0)); then
        app_message 'Selecciona un favorito para editar su etiqueta.' 5
        return 1
    fi
    local url="${FAVORITE_URLS[UI_SELECTED_INDEX]}" name="${FAVORITE_NAMES[UI_SELECTED_INDEX]}"
    local text="${FAVORITE_LABELS[$url]:-}" previous_help=$UI_HELP_VISIBLE
    UI_HELP_VISIBLE=0
    LABEL_EDITOR_ACTIVE=1
    while true; do
        local visible=$((UI_COLS - 15))
        ((visible < 1)) && visible=1
        local preview="$text"
        ((${#preview} > visible)) && preview="${preview: -visible}"
        app_message "Etiqueta: ${preview}_" 0
        ui_draw
        if ! input_read; then LABEL_EDITOR_ACTIVE=0; UI_HELP_VISIBLE=$previous_help; ui_clear_message; return 1; fi
        case "$INPUT_EVENT" in
            ENTER)
                LABEL_EDITOR_ACTIVE=0
                UI_HELP_VISIBLE=$previous_help
                if labels_set "$url" "$text"; then
                    app_message "Etiqueta guardada: $name" 4
                    return 0
                fi
                app_message 'No se pudo guardar la etiqueta.' 6
                return 1
                ;;
            ESC) LABEL_EDITOR_ACTIVE=0; UI_HELP_VISIBLE=$previous_help; ui_clear_message; return 0 ;;
            TICK) app_poll_player || true; catalog_poll || true; ui_message_tick || true ;;
            KEY)
                case "$INPUT_KEY" in
                    $'\x7f'|$'\x08') text="${text%?}" ;;
                    $'\x15') text='' ;;
                    *)
                        if [[ "$INPUT_KEY" == [[:print:]] ]] && ((${#text} < 80)); then text+="$INPUT_KEY"; fi
                        ;;
                esac
                ;;
        esac
    done
}
