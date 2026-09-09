#!/usr/bin/env bash

# Divide la columna de navegación desktop en dos zonas: Favoritos arriba y
# búsqueda integrada abajo. Se carga después de ui-update-status.sh y
# app-search.sh para reutilizar tanto el contador de filas desktop como SEARCH_*.

UI_DESKTOP_FAVORITES_HEIGHT=0
UI_DESKTOP_SEARCH_HEIGHT=0

ui_desktop_search_split_heights() {
    local body_height="$1"
    local usable=$((body_height - 1))

    ((usable < 2)) && usable=2
    UI_DESKTOP_FAVORITES_HEIGHT=$((usable / 2))
    UI_DESKTOP_SEARCH_HEIGHT=$((usable - UI_DESKTOP_FAVORITES_HEIGHT - 1))

    ((UI_DESKTOP_FAVORITES_HEIGHT < 1)) && UI_DESKTOP_FAVORITES_HEIGHT=1
    ((UI_DESKTOP_SEARCH_HEIGHT < 1)) && UI_DESKTOP_SEARCH_HEIGHT=1
}

# El renderer desktop original usa la altura del cuerpo completa para mantener
# visible la selección de Favoritos. Ahora esa lista solo ocupa la mitad superior.
ui_desktop_sync_selection() {
    local body_height="$1"
    ui_desktop_search_split_heights "$body_height"
    ui_navigation_refresh
    # Reservar la primera fila para los nombres de las dos columnas. En
    # pantalla completa ambas listas ocupan la misma altura y hacen scroll de
    # forma independiente.
    if ((UI_DESKTOP_RIGHT_WIDTH >= 60)); then
        ui_navigation_sync_columns "$((UI_DESKTOP_FAVORITES_HEIGHT - 1))"
    else
        ui_navigation_sync "$((UI_DESKTOP_FAVORITES_HEIGHT - 1))"
    fi

    # La búsqueda reserva una fila para títulos de columnas y otra para el
    # campo de consulta cuando está activo.
    local search_results_height=$UI_DESKTOP_SEARCH_HEIGHT
    ((search_results_height -= 1))
    if ((SEARCH_ACTIVE)) || [[ -n "$SEARCH_QUERY" ]]; then ((search_results_height -= 1)); fi
    ((search_results_height < 1)) && search_results_height=1
    if declare -F search_sync_scroll >/dev/null 2>&1; then
        search_sync_scroll "$search_results_height"
    fi
}

# El encabezado activo lleva el mismo glifo discreto que usamos para la selección.
# En modo sin color sigue siendo visible, y al entrar en búsqueda desaparece de
# Favoritos para que solo haya un indicador de foco principal en cada momento.
if ! declare -F ui_desktop_header_rule_without_search_focus >/dev/null 2>&1; then
    UI_DESKTOP_SEARCH_SPLIT_DEF=$(declare -f ui_desktop_header_rule)
    UI_DESKTOP_SEARCH_SPLIT_DEF=${UI_DESKTOP_SEARCH_SPLIT_DEF/ui_desktop_header_rule ()/ui_desktop_header_rule_without_search_focus ()}
    eval "$UI_DESKTOP_SEARCH_SPLIT_DEF"
    unset UI_DESKTOP_SEARCH_SPLIT_DEF
fi

ui_desktop_header_rule() {
    local width="$1"
    local left_label="$2"
    local right_label="$3"

    if ((!SEARCH_ACTIVE)) && [[ "$right_label" == FAVORITOS* ]]; then
        right_label="$UI_SELECT $right_label"
    fi

    ui_desktop_header_rule_without_search_focus "$width" "$left_label" "$right_label"
}

# Conservamos la fila desktop ya envuelta por ui-update-status.sh. Así el aviso
# de actualización sigue pudiendo ocupar su fila del panel izquierdo.
if ! declare -F ui_desktop_row_without_search_split >/dev/null 2>&1; then
    UI_DESKTOP_SEARCH_SPLIT_DEF=$(declare -f ui_desktop_row)
    UI_DESKTOP_SEARCH_SPLIT_DEF=${UI_DESKTOP_SEARCH_SPLIT_DEF/ui_desktop_row ()/ui_desktop_row_without_search_split ()}
    eval "$UI_DESKTOP_SEARCH_SPLIT_DEF"
    unset UI_DESKTOP_SEARCH_SPLIT_DEF
fi

ui_desktop_row() {
    local left_text="${1:-}"
    local left_badge="${2:-}"
    local left_style="${3:-}"
    local left_badge_style="${4:-}"
    local right_text="${5:-}"
    local right_badge="${6:-}"
    local right_style="${7:-}"
    local right_badge_style="${8:-}"
    local selected="${9:-0}"
    local row="${UI_UPDATE_DESKTOP_ROW:-0}"

    # En pantalla completa, Favoritos y Recientes comparten la mitad superior
    # del panel. El índice de selección sigue siendo único; cada lista ocupa
    # su columna visual y conserva su propio scroll.
    if ((UI_DESKTOP_RIGHT_WIDTH >= 60 && row < UI_DESKTOP_FAVORITES_HEIGHT)); then
        # La fila cero contiene encabezados; las listas empiezan en la uno.
        local column_index="$((UI_SCROLL_OFFSET + row - 1))"
        local recent_index="$((UI_RECENT_SCROLL + row - 1))"
        right_text=''
        right_badge=''
        right_style=''
        right_badge_style=''
        selected=0
        UI_DESKTOP_NAV_COLUMNS=1
        UI_DESKTOP_SEARCH_COLUMNS=0
        UI_DESKTOP_LEFT_COMMENT=''
        UI_DESKTOP_RIGHT_COMMENT=''
        UI_DESKTOP_LEFT_COMMENT_STYLE='comment'
        UI_DESKTOP_RIGHT_COMMENT_STYLE='comment'
        if ((row == 0)); then
            right_text="[$(ui_shortcut f)] FAVORITAS (${#FAVORITE_NAMES[@]})"
            right_badge="[$(ui_shortcut r)] RECIENTES (${#RECENT_NAMES[@]})"
            UI_DESKTOP_LEFT_COMMENT='COMENTARIOS'
            UI_DESKTOP_RIGHT_COMMENT='COMENTARIOS'
            right_style='favorite'
            right_badge_style='favorite'
            UI_DESKTOP_LEFT_COMMENT_STYLE='favorite'
            UI_DESKTOP_RIGHT_COMMENT_STYLE='favorite'
        else
            if ((column_index < ${#FAVORITE_NAMES[@]})); then
                local favorite_preset='   '
                case "$column_index" in
                    [0-8]) favorite_preset="$((column_index + 1)). " ;;
                    9) favorite_preset='0. ' ;;
                esac
                local favorite_comment=''
                if declare -p FAVORITE_LABELS >/dev/null 2>&1; then
                    favorite_comment="${FAVORITE_LABELS[${FAVORITE_URLS[column_index]}]:-}"
                fi
                right_text="  ${favorite_preset}${FAVORITE_NAMES[column_index]}"
                UI_DESKTOP_LEFT_COMMENT="$favorite_comment"
                if ((column_index == UI_SELECTED_INDEX && !${SEARCH_ACTIVE:-0})); then
                    right_text="$UI_SELECT ${favorite_preset}${FAVORITE_NAMES[column_index]}"
                    right_style='selected'
                fi
            fi
            if ((recent_index < ${#RECENT_NAMES[@]})); then
                local recent_preset='   '
                case "$recent_index" in
                    [0-8]) recent_preset="$((recent_index + 1)). " ;;
                    9) recent_preset='0. ' ;;
                esac
                right_badge="  ${recent_preset}${RECENT_NAMES[recent_index]}"
                local recent_comment=''
                if declare -p FAVORITE_LABELS >/dev/null 2>&1; then
                    recent_comment="${FAVORITE_LABELS[${RECENT_URLS[recent_index]}]:-}"
                fi
                UI_DESKTOP_RIGHT_COMMENT="$recent_comment"
                if ((recent_index + ${#FAVORITE_NAMES[@]} == UI_SELECTED_INDEX && !${SEARCH_ACTIVE:-0})); then
                    right_badge="$UI_SELECT ${recent_preset}${RECENT_NAMES[recent_index]}"
                    right_badge_style='selected'
                fi
                if favorites_find_url "${RECENT_URLS[recent_index]}" >/dev/null 2>&1; then
                    right_badge="${right_badge:0:2}[$UI_FAVORITE] ${right_badge:2}"
                else
                    # Reservar el mismo ancho que la marca de favorito alinea
                    # los números y nombres de ambas columnas.
                    right_badge="${right_badge:0:2}    ${right_badge:2}"
                fi
            fi
        fi
        ui_desktop_row_without_search_split \
            "$left_text" "$left_badge" "$left_style" "$left_badge_style" \
            "$right_text" "$right_badge" "$right_style" "$right_badge_style" "$selected"
        UI_DESKTOP_NAV_COLUMNS=0
        UI_DESKTOP_LEFT_COMMENT=''
        UI_DESKTOP_RIGHT_COMMENT=''
        UI_DESKTOP_LEFT_COMMENT_STYLE='comment'
        UI_DESKTOP_RIGHT_COMMENT_STYLE='comment'
        return 0
    fi

    UI_DESKTOP_NAV_COLUMNS=0
    UI_DESKTOP_SEARCH_COLUMNS=0
    UI_DESKTOP_LEFT_COMMENT=''
    UI_DESKTOP_RIGHT_COMMENT=''
    UI_DESKTOP_LEFT_COMMENT_STYLE='comment'
    UI_DESKTOP_RIGHT_COMMENT_STYLE='comment'

    # La mitad superior conserva Favoritos. Mientras la búsqueda tiene el foco,
    # quitamos únicamente el resaltado de selección para que el foco sea inequívoco.
    if ((row == 0)); then
        right_text='  EMISORAS'
        right_badge=$(ui_labels_header "$UI_DESKTOP_RIGHT_WIDTH")
        right_style='accent'
        right_badge_style='accent'
        selected=0
    elif ((row < UI_DESKTOP_FAVORITES_HEIGHT)); then
        ui_navigation_row "$((row - 1))"
        right_text="$UI_NAV_TEXT" right_badge="$UI_NAV_BADGE"
        right_style="$UI_NAV_STYLE" right_badge_style="$UI_NAV_BADGE_STYLE"
        selected=$UI_NAV_SELECTED
    elif ((row == UI_DESKTOP_FAVORITES_HEIGHT)); then
        # La cabecera de búsqueda comparte altura con la regla divisoria.
        right_text="[$(ui_shortcut b)] BUSQUEDA EMISORAS"
        right_badge=''
        ((SEARCH_ACTIVE)) && right_text="$UI_SELECT $right_text"
        right_style='separator_label'
        right_badge_style=''
        selected=0
    elif ((row == UI_DESKTOP_FAVORITES_HEIGHT + 1)); then
        right_text='EMISORA'
        UI_DESKTOP_SEARCH_AMBIT='ÁMBITO'
        UI_DESKTOP_SEARCH_COUNTRY='PAÍS'
        UI_DESKTOP_SEARCH_FORMAT='FORMATO'
        UI_DESKTOP_SEARCH_COMMENT='COMENTARIOS'
        UI_DESKTOP_SEARCH_COLUMNS=1
        right_style='accent'
        right_badge_style='accent'
        selected=0
    else
        local search_row=$((row - UI_DESKTOP_FAVORITES_HEIGHT - 2))
        right_text=''
        right_badge=''
        right_style=''
        right_badge_style=''
        selected=0

        local query_rows=0
        if ((search_row == -1)); then
            UI_DESKTOP_SEARCH_COLUMNS=1
            right_text='EMISORA'
            UI_DESKTOP_SEARCH_AMBIT='ÁMBITO'
            UI_DESKTOP_SEARCH_COUNTRY='PAÍS'
            UI_DESKTOP_SEARCH_FORMAT='FORMATO'
            right_style='accent'
        fi
        if ((SEARCH_ACTIVE)) || [[ -n "$SEARCH_QUERY" ]]; then query_rows=1; fi
        if ((search_row == -1)); then
            :
        elif ((search_row == 0 && query_rows)); then
            if ((SEARCH_ACTIVE)); then
                right_text="Buscar: ${SEARCH_QUERY}_"
                right_style='accent'
                selected=1
                if ((SEARCH_FILTER_DIRTY)); then
                    right_badge='filtrando'
                    right_badge_style='muted'
                else
                    right_badge="${#SEARCH_MATCHES[@]} resultados"
                    right_badge_style='muted'
                fi
            elif [[ -n "${SEARCH_QUERY:-}" ]]; then
                right_text="Buscar: $SEARCH_QUERY"
                right_badge='B editar'
                right_style='muted'
                right_badge_style='muted'
            else
                right_text=''
                right_style='muted'
            fi
        else
            local result_slot=$((search_row - query_rows))
            local match_position=$((SEARCH_SCROLL_OFFSET + result_slot))

            if ((${#SEARCH_MATCHES[@]} == 0)); then
                if ((result_slot == 0)); then
                    if ((SEARCH_FILTER_DIRTY == 0)) && { ((SEARCH_ACTIVE)) || [[ -n "$SEARCH_QUERY" ]]; }; then
                        right_text='  Sin resultados'
                        right_style='muted'
                    elif ((!SEARCH_ACTIVE)); then
                        right_text="  ${CATALOG_STATUS:-Sin catálogo disponible; U reintentar}"
                        right_style='muted'
                    fi
                fi
            elif ((match_position < ${#SEARCH_MATCHES[@]})); then
                local source_index=${SEARCH_MATCHES[$match_position]}
                local playing=0
                ui_search_result_parts "$source_index"
                right_text="  $UI_SEARCH_NAME"
                ((UI_SEARCH_IS_FAVORITE)) && right_text="  [$UI_FAVORITE] $UI_SEARCH_NAME"
                UI_DESKTOP_SEARCH_AMBIT="${SEARCH_AMBITS[$source_index]:-}"
            UI_DESKTOP_SEARCH_COUNTRY="${SEARCH_COUNTRIES[$source_index]:-}"
            UI_DESKTOP_SEARCH_FORMAT="${SEARCH_FORMATS[$source_index]:-}"
                UI_DESKTOP_SEARCH_COMMENT="${UI_SEARCH_LABEL:-}"
                UI_DESKTOP_SEARCH_COLUMNS=1

                if player_is_running && [[ "${SEARCH_URLS[$source_index]}" == "$PLAYER_URL" ]]; then
                    playing=1
                fi
                right_badge=$(ui_search_result_badge "$playing")
                ((UI_SEARCH_IS_FAVORITE)) && right_badge_style='favorite'

                if ((SEARCH_ACTIVE && match_position == SEARCH_SELECTED_INDEX)); then
                    right_text="$UI_SELECT "
                    ((UI_SEARCH_IS_FAVORITE)) && right_text+="[$UI_FAVORITE] "
                    right_text+="$UI_SEARCH_NAME"
                    right_style='selected'
                    selected=1
                elif ((playing)); then
                    right_text="$UI_PLAY $UI_SEARCH_NAME"
                    right_style='playing'
                    right_badge_style='playing'
                else
                    [[ -n "$right_badge_style" ]] || right_badge_style='muted'
                fi
            fi
        fi
    fi

    ui_desktop_row_without_search_split \
        "$left_text" "$left_badge" "$left_style" "$left_badge_style" \
        "$right_text" "$right_badge" "$right_style" "$right_badge_style" "$selected"
}

# El pie normal anuncia atajos como Q/R que durante la búsqueda son texto. F
# mayúscula es la única letra reservada para actuar sobre el resultado activo.
if ! declare -F ui_draw_responsive_controls_without_search_focus >/dev/null 2>&1; then
    UI_DESKTOP_SEARCH_SPLIT_DEF=$(declare -f ui_draw_responsive_controls)
    UI_DESKTOP_SEARCH_SPLIT_DEF=${UI_DESKTOP_SEARCH_SPLIT_DEF/ui_draw_responsive_controls ()/ui_draw_responsive_controls_without_search_focus ()}
    eval "$UI_DESKTOP_SEARCH_SPLIT_DEF"
    unset UI_DESKTOP_SEARCH_SPLIT_DEF
fi

ui_draw_responsive_controls() {
    local width="$1"
    if ! ((${SEARCH_ACTIVE:-0} || ${EQUALIZER_EDITOR_ACTIVE:-0})); then
        ui_box_line "$width" '↑↓ Enter reproducir · , Configuración · ? Ayuda y atajos' muted
        return 0
    fi

    if ((${EQUALIZER_EDITOR_ACTIVE:-0})); then
        ui_box_line "$width" '←→ frecuencia · ↑↓ ajustar · 1-5 presets · C centrar · R plano · Z cerrar' muted
        return 0
    fi
    if ((${LABEL_EDITOR_ACTIVE:-0})); then
        ui_box_line "$width" 'Enter guardar · Esc cancelar · Ctrl-U borrar' muted
        return 0
    fi
    if ((SEARCH_ACTIVE)); then
        ui_box_line "$width" "Escribe  $UI_SEP  ↑↓ mover  $UI_SEP  Enter reproducir  $UI_SEP  X favorito  $UI_SEP  C comentario  $UI_SEP  Esc favoritos" muted
        return 0
    fi

    ui_draw_responsive_controls_without_search_focus "$@"
}
