#!/usr/bin/env bash

# Editor en la pantalla actual: Enter guarda, Esc cancela, Ctrl-U vacía.
app_edit_label() {
    local url='' name='' recent
    if ((${SEARCH_ACTIVE:-0})); then
        search_prepare_results
        if ! search_selected_load; then
            app_message 'No hay ninguna emisora seleccionada para comentar.' 5
            return 1
        fi
        url="$SELECTED_URL" name="$SELECTED_NAME"
    else
        favorites_load || return 1
        ui_sync_selection
        if ((UI_NAV_COUNT == 0)); then
            app_message 'Selecciona una emisora para editar su comentario.' 5
            return 1
        fi
        if ((UI_SELECTED_INDEX < ${#FAVORITE_URLS[@]})); then
            url="${FAVORITE_URLS[UI_SELECTED_INDEX]}" name="${FAVORITE_NAMES[UI_SELECTED_INDEX]}"
        else
            recent=$((UI_SELECTED_INDEX - ${#FAVORITE_URLS[@]}))
            url="${RECENT_URLS[recent]}" name="${RECENT_NAMES[recent]}"
        fi
    fi
    local text="${FAVORITE_LABELS[$url]:-}" previous_help=$UI_HELP_VISIBLE previous_preferences=$PREFERENCES_ACTIVE
    local redraw=1 result=0 notice=''
    UI_HELP_VISIBLE=0 LABEL_EDITOR_ACTIVE=1 PREFERENCES_ACTIVE=1
    while true; do
        ((redraw)) && label_editor_draw "$name" "$text" "$notice"
        input_read || { result=1; break; }
        redraw=1
        case "$INPUT_EVENT" in
            ENTER)
                if labels_set "$url" "$text"; then
                    search_filter
                    app_message "Comentario guardado: $name" 4
                    break
                fi
                notice='No se pudo guardar. El texto sigue aquí; reintenta o Esc cancela.'
                ;;
            ESC) break ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            RESIZE) ;;
            DELETE) text='' notice='' ;;
            KEY)
                notice=''
                case "$INPUT_KEY" in
                    $'\x7f'|$'\x08') text="${text%?}" ;;
                    $'\x15') text='' ;;
                    *)
                        if [[ "$INPUT_KEY" == [[:print:]] ]] && ((${#text} < 80)); then text+="$INPUT_KEY"; fi ;;
                esac ;;
        esac
    done
    LABEL_EDITOR_ACTIVE=0 UI_HELP_VISIBLE=$previous_help PREFERENCES_ACTIVE=$previous_preferences
    if ((!previous_preferences)); then
        if ((${SEARCH_ACTIVE:-0})); then search_draw_view; else ui_draw; fi
    fi
    return "$result"
}

label_editor_draw() {
    local name=$1 text=$2 notice=${3:-} visible preview
    local PANEL_FORM=1
    local -a PANEL_ROWS=()
    ui_refresh_size
    visible=$((UI_COLS - 1))
    if ((visible >= 96 && UI_LINES >= 16)); then
        visible=$((visible * 48 / 100)); ((visible <= 60)) || visible=60
    fi
    if ((visible >= 46)); then visible=$((visible - 13)); else visible=$((visible - 6)); fi
    ((visible < 1)) && visible=1
    preview="$text"
    options_fit_text "${preview}_" "$visible"
    while [[ "$OPTIONS_FITTED" != "${preview}_" && -n "$preview" ]]; do
        preview=${preview:1}
        options_fit_text "${preview}_" "$visible"
    done
    panel_add_row '' "${preview}_" "Emisora: $name. Comentario completo: ${text:-vacío}. Escribe hasta 80 caracteres; Retroceso borra, Supr o Ctrl+U vacían. Enter guarda y Esc cancela." "${#text}/80"
    panel_draw COMENTARIOS 0 0 'Enter guardar | Esc cancelar' "$notice" "Emisora: $name"
}
