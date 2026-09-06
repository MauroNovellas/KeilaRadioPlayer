#!/usr/bin/env bash

# Editor en la pantalla actual: Enter guarda, Esc cancela, Ctrl-U vacía.
app_edit_label() {
    local url='' name='' recent
    if ((${SEARCH_ACTIVE:-0})); then
        search_prepare_results
        if ! search_selected_load; then
            app_message 'No hay ninguna emisora seleccionada para etiquetar.' 5
            return 1
        fi
        url="$SELECTED_URL" name="$SELECTED_NAME"
    else
        favorites_load || return 1
        ui_sync_selection
        if ((UI_NAV_COUNT == 0)); then
            app_message 'Selecciona una emisora para editar su etiqueta.' 5
            return 1
        fi
        if ((UI_SELECTED_INDEX < ${#FAVORITE_URLS[@]})); then
            url="${FAVORITE_URLS[UI_SELECTED_INDEX]}" name="${FAVORITE_NAMES[UI_SELECTED_INDEX]}"
        else
            recent=$((UI_SELECTED_INDEX - ${#FAVORITE_URLS[@]}))
            url="${RECENT_URLS[recent]}" name="${RECENT_NAMES[recent]}"
        fi
    fi
    local text="${FAVORITE_LABELS[$url]:-}" previous_help=$UI_HELP_VISIBLE
    UI_HELP_VISIBLE=0
    LABEL_EDITOR_ACTIVE=1
    while true; do
        local visible=$((UI_COLS - 15))
        ((visible < 1)) && visible=1
        local preview="$text"
        ((${#preview} > visible)) && preview="${preview: -visible}"
        app_message "Etiqueta: ${preview}_" 0
        if ((${SEARCH_ACTIVE:-0})); then search_draw_view; else ui_draw; fi
        if ! input_read; then LABEL_EDITOR_ACTIVE=0; UI_HELP_VISIBLE=$previous_help; ui_clear_message; return 1; fi
        case "$INPUT_EVENT" in
            ENTER)
                LABEL_EDITOR_ACTIVE=0
                UI_HELP_VISIBLE=$previous_help
                if labels_set "$url" "$text"; then
                    # Aplicar el filtro de nuevo: la etiqueta puede ser la consulta.
                    search_filter
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
