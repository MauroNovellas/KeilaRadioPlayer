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
    UI_DESKTOP_SEARCH_HEIGHT=$((usable - UI_DESKTOP_FAVORITES_HEIGHT))

    ((UI_DESKTOP_FAVORITES_HEIGHT < 1)) && UI_DESKTOP_FAVORITES_HEIGHT=1
    ((UI_DESKTOP_SEARCH_HEIGHT < 1)) && UI_DESKTOP_SEARCH_HEIGHT=1
}

# El renderer desktop original usa la altura del cuerpo completa para mantener
# visible la selección de Favoritos. Ahora esa lista solo ocupa la mitad superior.
ui_desktop_sync_selection() {
    local body_height="$1"
    local count=${#FAVORITE_NAMES[@]}

    ui_desktop_search_split_heights "$body_height"

    local height=$UI_DESKTOP_FAVORITES_HEIGHT
    if ((count == 0)); then
        UI_SELECTED_INDEX=0
        UI_SCROLL_OFFSET=0
    else
        ((UI_SELECTED_INDEX < 0)) && UI_SELECTED_INDEX=0
        ((UI_SELECTED_INDEX >= count)) && UI_SELECTED_INDEX=$((count - 1))

        if ((UI_SELECTED_INDEX < UI_SCROLL_OFFSET)); then
            UI_SCROLL_OFFSET=$UI_SELECTED_INDEX
        elif ((UI_SELECTED_INDEX >= UI_SCROLL_OFFSET + height)); then
            UI_SCROLL_OFFSET=$((UI_SELECTED_INDEX - height + 1))
        fi

        local max_scroll=$((count - height))
        ((max_scroll < 0)) && max_scroll=0
        ((UI_SCROLL_OFFSET > max_scroll)) && UI_SCROLL_OFFSET=$max_scroll
        ((UI_SCROLL_OFFSET < 0)) && UI_SCROLL_OFFSET=0
    fi

    # Una fila de la mitad inferior se reserva para el campo Buscar:.
    local search_results_height=$((UI_DESKTOP_SEARCH_HEIGHT - 1))
    ((search_results_height < 1)) && search_results_height=1
    if declare -F search_sync_scroll >/dev/null 2>&1; then
        search_sync_scroll "$search_results_height"
    fi
}

ui_desktop_search_separator_text() {
    local label='BUSCAR EMISORAS'
    local text="$UI_H $label "
    local remaining=$((UI_DESKTOP_RIGHT_WIDTH - ${#text}))

    if ((remaining > 0)); then
        text+="$(ui_repeat_char "$UI_H" "$remaining")"
    fi
    ui_truncate "$text" "$UI_DESKTOP_RIGHT_WIDTH"
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

    # La mitad superior conserva Favoritos. Mientras la búsqueda tiene el foco,
    # quitamos únicamente el resaltado de selección para que el foco sea inequívoco.
    if ((row < UI_DESKTOP_FAVORITES_HEIGHT)); then
        if ((SEARCH_ACTIVE && selected)); then
            selected=0
            if [[ "$right_text" == "$UI_SELECT "* ]]; then
                right_text="  ${right_text#"$UI_SELECT "}"
            fi
        fi
    elif ((row == UI_DESKTOP_FAVORITES_HEIGHT)); then
        # Fila divisoria entre Favoritos y búsqueda.
        right_text=$(ui_desktop_search_separator_text)
        right_badge=''
        right_style='accent'
        right_badge_style=''
        selected=0
        ((SEARCH_ACTIVE)) && right_style='selected'
    else
        local search_row=$((row - UI_DESKTOP_FAVORITES_HEIGHT - 1))
        right_text=''
        right_badge=''
        right_style=''
        right_badge_style=''
        selected=0

        if ((search_row == 0)); then
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
                right_text='B  Buscar emisoras'
                right_style='muted'
            fi
        else
            local result_slot=$((search_row - 1))
            local match_position=$((SEARCH_SCROLL_OFFSET + result_slot))

            if ((${#SEARCH_MATCHES[@]} == 0)); then
                if ((result_slot == 0)); then
                    if ((SEARCH_ACTIVE)) && ((SEARCH_FILTER_DIRTY == 0)); then
                        right_text='  Sin resultados'
                        right_style='muted'
                    elif ((!SEARCH_ACTIVE)); then
                        right_text='  Pulsa B y escribe para filtrar'
                        right_style='muted'
                    fi
                fi
            elif ((match_position < ${#SEARCH_MATCHES[@]})); then
                local source_index=${SEARCH_MATCHES[$match_position]}
                local playing=0
                ui_search_result_parts "$source_index"
                right_text="  $UI_SEARCH_NAME"

                if player_is_running && [[ "${SEARCH_URLS[$source_index]}" == "$PLAYER_URL" ]]; then
                    playing=1
                fi
                right_badge=$(ui_search_result_badge "$playing")
                ((UI_SEARCH_IS_FAVORITE)) && right_badge_style='favorite'

                if ((SEARCH_ACTIVE && match_position == SEARCH_SELECTED_INDEX)); then
                    right_text="$UI_SELECT $UI_SEARCH_NAME"
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

    if ((SEARCH_ACTIVE)); then
        ui_box_line "$width" "Escribe  $UI_SEP  ↑↓ mover  $UI_SEP  Enter reproducir  $UI_SEP  F favorito  $UI_SEP  Esc favoritos" muted
        return 0
    fi

    ui_draw_responsive_controls_without_search_focus "$@"
}
