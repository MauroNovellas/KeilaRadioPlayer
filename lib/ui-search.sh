#!/usr/bin/env bash

# Render de la búsqueda integrada. No modifica el estado del catálogo ni del
# reproductor: solo presenta SEARCH_* y reutiliza los helpers visuales actuales.

UI_SEARCH_QUERY_CURSOR=''
UI_SEARCH_QUERY_FRAME_KEY=''
UI_SEARCH_QUERY_CURSOR_KEY=''
UI_SEARCH_QUERY_KIND=''
UI_SEARCH_QUERY_WIDTH=0

ui_search_query_signature() {
    UI_SEARCH_QUERY_SIGNATURE="${TERM:-}|$UI_COLS|$UI_LINES|$UI_LAYOUT_MODE|$UI_COLOR|$UI_UNICODE|$UI_HELP_VISIBLE"
}

# Se llama al dibujar el campo completo. tput se utiliza solo al cambiar su
# posición; las pulsaciones posteriores reutilizan el cursor preparado.
ui_search_query_prepare() {
    local kind=$1 row=$2 col=$3 width=$4 cursor_key
    UI_SEARCH_QUERY_FRAME_KEY=''
    ((${SEARCH_ACTIVE:-0} && !${LABEL_EDITOR_ACTIVE:-0} && !${PREFERENCES_ACTIVE:-0})) || return 0
    ((row >= 0 && row < UI_LINES && col >= 0 && width > 0 && col + width < UI_COLS)) || return 0
    ui_search_query_signature
    cursor_key="$UI_SEARCH_QUERY_SIGNATURE|$kind|$row|$col|$width"
    if [[ "$cursor_key" != "$UI_SEARCH_QUERY_CURSOR_KEY" ]]; then
        UI_SEARCH_QUERY_CURSOR=$(tput cup "$row" "$col" 2>/dev/null) || UI_SEARCH_QUERY_CURSOR=''
        UI_SEARCH_QUERY_CURSOR_KEY=$cursor_key
    fi
    if [[ -z "$UI_SEARCH_QUERY_CURSOR" ]]; then
        UI_SEARCH_QUERY_CURSOR_KEY=''
        return 0
    fi
    UI_SEARCH_QUERY_KIND=$kind UI_SEARCH_QUERY_WIDTH=$width
    UI_SEARCH_QUERY_FRAME_KEY=$UI_SEARCH_QUERY_SIGNATURE
}

ui_search_query_desktop_parts() {
    UI_SEARCH_QUERY_TEXT="Buscar: ${SEARCH_QUERY}_"
    if ((SEARCH_FILTER_DIRTY)); then
        UI_SEARCH_QUERY_BADGE='filtrando'
    elif [[ -n "$SEARCH_REGION_FILTER$SEARCH_TAG_FILTER" ]]; then
        UI_SEARCH_QUERY_BADGE="filtros · ${#SEARCH_MATCHES[@]} resultados"
    elif ((SEARCH_COUNTRY_FILTER_ENABLED)); then
        UI_SEARCH_QUERY_BADGE="$KEILA_CATALOG_COUNTRY_FILTER · ${#SEARCH_MATCHES[@]} resultados"
    else
        UI_SEARCH_QUERY_BADGE="global · ${#SEARCH_MATCHES[@]} resultados"
    fi
}

ui_search_query_print() {
    local kind=$1 width=$2
    case "$kind" in
        desktop)
            ui_search_query_desktop_parts
            ui_print_split_styled "$width" "$UI_SEARCH_QUERY_TEXT" "$UI_SEARCH_QUERY_BADGE" selected selected ;;
        single)
            search_filters_badge
            ui_print_split_styled "$width" 'Buscar:' "${SEARCH_QUERY}_  [$SEARCH_FILTER_BADGE]" accent selected ;;
        modal-desktop)
            ui_print_split_styled "$width" 'Buscar:' "${SEARCH_QUERY}_" accent selected ;;
        tiny) ui_print_padded "$width" "Buscar: ${SEARCH_QUERY}_" ;;
        *) return 1 ;;
    esac
}

ui_draw_search_query_only() {
    ((UI_ACTIVE && !UI_SUSPENDED && ${SEARCH_ACTIVE:-0} && !${INPUT_RESIZE_PENDING:-0} &&
        !${LABEL_EDITOR_ACTIVE:-0} && !${PREFERENCES_ACTIVE:-0})) || return 1
    ui_search_query_signature
    [[ -n "$UI_SEARCH_QUERY_CURSOR" && "$UI_SEARCH_QUERY_FRAME_KEY" == "$UI_SEARCH_QUERY_SIGNATURE" ]] || return 1
    printf '%s' "$UI_SEARCH_QUERY_CURSOR"
    # Rellenar el ancho reservado borra el texto anterior sin tocar bordes,
    # resultados, reproductor o logo, y sin emitir saltos de línea.
    ui_search_query_print "$UI_SEARCH_QUERY_KIND" "$UI_SEARCH_QUERY_WIDTH"
}

ui_search_result_parts() {
    local source_index="$1"
    UI_SEARCH_NAME="${SEARCH_NAMES[$source_index]}"
    UI_SEARCH_DETAIL=''
    UI_SEARCH_IS_FAVORITE=0
    UI_SEARCH_LABEL=''
    if declare -p FAVORITE_LABELS >/dev/null 2>&1; then
        UI_SEARCH_LABEL="${FAVORITE_LABELS[${SEARCH_URLS[$source_index]}]:-}"
    fi

    if [[ -n "${SEARCH_AMBITS[$source_index]}" ]]; then
        UI_SEARCH_DETAIL="${SEARCH_AMBITS[$source_index]}"
    fi
    if [[ -n "${SEARCH_COUNTRIES[$source_index]}" ]]; then
        [[ -n "$UI_SEARCH_DETAIL" ]] && UI_SEARCH_DETAIL+=" $UI_SEP "
        UI_SEARCH_DETAIL+="${SEARCH_COUNTRIES[$source_index]}"
    fi
    if [[ -n "${SEARCH_COUNTRYCODES[$source_index]:-}" ]]; then
        [[ -n "$UI_SEARCH_DETAIL" ]] && UI_SEARCH_DETAIL+=" $UI_SEP "
        UI_SEARCH_DETAIL+="${SEARCH_COUNTRYCODES[$source_index]}"
    fi

    if declare -F favorites_find_url >/dev/null 2>&1 && \
        favorites_find_url "${SEARCH_URLS[$source_index]}" >/dev/null 2>&1; then
        UI_SEARCH_IS_FAVORITE=1
    fi
}

ui_search_result_badge() {
    local playing="${1:-0}"
    local badge=''

    if ((playing)); then
        badge='[PLAY]'
        ((UI_SEARCH_IS_FAVORITE)) && badge+=" [$UI_FAVORITE]"
    elif ((UI_SEARCH_IS_FAVORITE)); then
        badge="[$UI_FAVORITE]"
    fi
    if [[ -n "${UI_SEARCH_DETAIL:-}" ]]; then
        [[ -n "$badge" ]] && badge+=' '
        badge+="$UI_SEARCH_DETAIL"
    fi
    if [[ -n "${UI_SEARCH_LABEL:-}" ]]; then
        [[ -n "$badge" ]] && badge+=' '
        badge+="$UI_SEARCH_LABEL"
    fi

    printf '%s' "$badge"
}

ui_search_show_details() {
    case "${UI_LAYOUT_MODE:-standard}" in
        tiny|minimal)
            (( ${SEARCH_DETAILS_VISIBLE:-0} ))
            ;;
        *)
            return 0
            ;;
    esac
}

ui_search_desktop() {
    local width="$1"
    local title="KEILA RADIO PLAYER  ${KEILA_VERSION:-dev}"
    local body_height
    ui_desktop_body_height state
    body_height=$UI_DESKTOP_BODY_HEIGHT

    ui_desktop_pane_widths "$width"
    search_sync_scroll "$body_height"

    ui_box_rule "$width" "$UI_TL" "$UI_TR"
    ui_box_center_line "$width" "$title" title
    ui_desktop_header_rule "$width" '[B] BUSQUEDA EMISORAS' "RESULTADOS (${#SEARCH_MATCHES[@]})"

    local row match_position source_index result_text result_badge result_style result_badge_style selected playing
    local left_text left_badge left_style left_badge_style
    for ((row = 0; row < body_height; row++)); do
        left_text=''
        left_badge=''
        left_style=''
        left_badge_style=''

        case "$row" in
            0)
                ui_search_query_prepare modal-desktop 3 2 "$UI_DESKTOP_LEFT_WIDTH"
                left_text='Buscar:'
                left_badge="${SEARCH_QUERY}_"
                left_style='accent'
                left_badge_style='selected'
                ;;
            1)
                left_text='Filtros:'
                search_filters_badge
                if [[ "$SEARCH_FILTER_BADGE" != Global ]]; then
                    left_badge=$SEARCH_FILTER_BADGE
                    left_style='accent'
                    left_badge_style='selected'
                else
                    left_badge='global'
                    left_style='muted'
                    left_badge_style='muted'
                fi
                ;;
            2)
                left_text='Escribe para filtrar'
                left_style='muted'
                ;;
            3)
                left_text='Backspace borrar · Supr limpiar'
                left_style='muted'
                ;;
            4)
                left_text='↑/↓ mover'
                left_style='muted'
                ;;
            5)
                left_text='Enter reproducir'
                left_style='muted'
                ;;
            6)
                left_text='X favorito  ·  Esc volver'
                left_style='muted'
                ;;
            8)
                if player_is_running; then
                    left_text='SONANDO'
                    left_badge="$PLAYER_NAME"
                    left_style='playing'
                    left_badge_style='playing'
                fi
                ;;
        esac

        match_position=$((SEARCH_SCROLL_OFFSET + row))
        result_text=''
        result_badge=''
        result_style=''
        result_badge_style=''
        selected=0
        playing=0

        if ((match_position < ${#SEARCH_MATCHES[@]})); then
            source_index=${SEARCH_MATCHES[$match_position]}
            ui_search_result_parts "$source_index"
            result_text="  $UI_SEARCH_NAME"

            if player_is_running && [[ "${SEARCH_URLS[$source_index]}" == "$PLAYER_URL" ]]; then
                playing=1
            fi
            result_badge=$(ui_search_result_badge "$playing")
            ((UI_SEARCH_IS_FAVORITE)) && result_badge_style='favorite'

            if ((match_position == SEARCH_SELECTED_INDEX)); then
                result_text="$UI_SELECT $UI_SEARCH_NAME"
                selected=1
            elif ((playing)); then
                result_text="$UI_PLAY $UI_SEARCH_NAME"
                result_style='playing'
                result_badge_style='playing'
            fi
        fi

        ui_desktop_row "$left_text" "$left_badge" "$left_style" "$left_badge_style" \
            "$result_text" "$result_badge" "$result_style" "$result_badge_style" "$selected"
    done

    ui_desktop_join_rule "$width"
    ui_box_line "$width" "Escribe  $UI_SEP  P país $KEILA_CATALOG_COUNTRY_FILTER  $UI_SEP  Supr limpiar  $UI_SEP  ↑↓ mover  $UI_SEP  Enter reproducir  $UI_SEP  X favorito  $UI_SEP  Esc volver" muted
    if [[ -n "$UI_MESSAGE" ]]; then
        ui_box_line "$width" "$UI_MESSAGE"
    else
        ui_box_line "$width" ''
    fi
    ui_box_rule "$width" "$UI_BL" "$UI_BR" '' muted final
    tput ed 2>/dev/null || true
}

ui_search_single_column() {
    local width="$1"
    local title
    title=$(ui_responsive_title)

    local body_height=$((UI_LINES - 9))
    ((body_height < 1)) && body_height=1
    search_sync_scroll "$body_height"

    ui_box_rule "$width" "$UI_TL" "$UI_TR"
    ui_box_center_line "$width" "$title" title
    ui_box_rule "$width" "$UI_ML" "$UI_MR" '[B] BUSQUEDA EMISORAS' accent
    search_filters_badge
    local country_filter=$SEARCH_FILTER_BADGE
    ui_search_query_prepare single 3 2 "$((width - 4))"
    ui_box_split_line "$width" 'Buscar:' "${SEARCH_QUERY}_  [$country_filter]" 0 accent selected
    local detail_header=''
    if ui_search_show_details; then detail_header=$(ui_labels_header "$((width - 4))"); fi
    ui_box_split_line "$width" "EMISORAS (${#SEARCH_MATCHES[@]})" "$detail_header" 0 accent accent

    local row match_position source_index text badge selected style badge_style playing
    for ((row = 0; row < body_height; row++)); do
        match_position=$((SEARCH_SCROLL_OFFSET + row))
        if ((match_position >= ${#SEARCH_MATCHES[@]})); then
            if ((row == 0 && ${#SEARCH_MATCHES[@]} == 0)); then
                ui_box_line "$width" '  Sin resultados' muted
            else
                ui_box_line "$width" ''
            fi
            continue
        fi

        source_index=${SEARCH_MATCHES[$match_position]}
        ui_search_result_parts "$source_index"
        text="  $UI_SEARCH_NAME"
        selected=0
        style=''
        badge_style=''
        playing=0

        if player_is_running && [[ "${SEARCH_URLS[$source_index]}" == "$PLAYER_URL" ]]; then
            playing=1
        fi
        badge=''
        if ui_search_show_details; then
            badge=$(ui_search_result_badge "$playing")
            ((UI_SEARCH_IS_FAVORITE)) && badge_style='favorite'
        elif ((UI_SEARCH_IS_FAVORITE)); then
            text="  [$UI_FAVORITE] $UI_SEARCH_NAME"
            badge_style='favorite'
        fi

        if ((match_position == SEARCH_SELECTED_INDEX)); then
            text="$UI_SELECT $UI_SEARCH_NAME"
            if ((!SEARCH_DETAILS_VISIBLE && UI_SEARCH_IS_FAVORITE)) && [[ "$UI_LAYOUT_MODE" != tiny ]]; then
                text="$UI_SELECT [$UI_FAVORITE] $UI_SEARCH_NAME"
            fi
            selected=1
        elif ((playing)); then
            text="$UI_PLAY $UI_SEARCH_NAME"
            style='playing'
            badge_style='playing'
        fi

        ui_box_split_line "$width" "$text" "$badge" "$selected" "$style" "$badge_style"
    done

    ui_box_rule "$width" "$UI_ML" "$UI_MR"
    if ((${LABEL_EDITOR_ACTIVE:-0})); then
        ui_box_line "$width" 'Enter guardar · Esc cancelar · Ctrl-U borrar' muted
    else
        ui_box_line "$width" '↑↓ Enter  Supr limpiar  ←/→ detalles  P país  X favorito  C comentario  Esc volver' muted
    fi
    if [[ -n "$UI_MESSAGE" ]]; then
        ui_box_line "$width" "$UI_MESSAGE"
    else
        ui_box_line "$width" ''
    fi
    ui_box_rule "$width" "$UI_BL" "$UI_BR" '' muted final
    tput ed 2>/dev/null || true
}

ui_draw_search() {
    ((UI_ACTIVE)) || return 0
    ((UI_SUSPENDED)) && return 0
    UI_SEARCH_QUERY_FRAME_KEY=''

    ui_refresh_size
    ui_layout_mode "$UI_COLS" "$UI_LINES" state
    UI_LAYOUT_MODE=$UI_LAYOUT_MODE_VALUE
    tput cup 0 0 2>/dev/null || true

    if [[ "$UI_LAYOUT_MODE" == 'tiny' ]]; then
        local tiny_width
        ui_layout_width "$UI_COLS" state
        tiny_width=$UI_LAYOUT_WIDTH
        ((tiny_width > 60)) && tiny_width=60
        local tiny_body_height=$((UI_LINES - 7))
        ((tiny_body_height < 1)) && tiny_body_height=1
        search_sync_scroll "$tiny_body_height"
        ui_print_padded "$tiny_width" "Keila Radio Player ${KEILA_VERSION:-dev}"
        printf '\n\n'
        if ((${LABEL_EDITOR_ACTIVE:-0})); then
            ui_print_padded "$tiny_width" "$UI_MESSAGE"
        else
            ui_search_query_prepare tiny 2 0 "$tiny_width"
            ui_print_padded "$tiny_width" "Buscar: ${SEARCH_QUERY}_"
        fi
        printf '\n'
            search_filters_badge
            local tiny_filter=$SEARCH_FILTER_BADGE
            local tiny_detail='solo nombres'
            ((SEARCH_DETAILS_VISIBLE)) && tiny_detail='detalles'
            ui_print_padded "$tiny_width" "Resultados: ${#SEARCH_MATCHES[@]} · $tiny_filter · $tiny_detail"
        printf '\n'
        local row match_position source_index text badge playing
        for ((row = 0; row < tiny_body_height; row++)); do
            match_position=$((SEARCH_SCROLL_OFFSET + row))
            if ((match_position >= ${#SEARCH_MATCHES[@]})); then
                if ((row == 0 && ${#SEARCH_MATCHES[@]} == 0)); then
                    ui_print_padded "$tiny_width" 'Sin resultados'
                else
                    ui_print_padded "$tiny_width" ''
                fi
                printf '\n'
                continue
            fi
            source_index=${SEARCH_MATCHES[$match_position]}
            ui_search_result_parts "$source_index"
            playing=0
            if player_is_running && [[ "${SEARCH_URLS[$source_index]}" == "$PLAYER_URL" ]]; then playing=1; fi
            if ((match_position == SEARCH_SELECTED_INDEX)); then
                text="$UI_SELECT $UI_SEARCH_NAME"
            elif ((playing)); then
                text="$UI_PLAY $UI_SEARCH_NAME"
            else
                text="  $UI_SEARCH_NAME"
            fi
            if ((SEARCH_DETAILS_VISIBLE)); then
                badge=$(ui_search_result_badge "$playing")
                [[ -n "$badge" ]] && text+=" · $badge"
            elif ((UI_SEARCH_IS_FAVORITE)); then
                text+=" · $UI_FAVORITE"
            fi
            ui_print_padded "$tiny_width" "$text"
            printf '\n'
        done
        if ((${LABEL_EDITOR_ACTIVE:-0})); then
            ui_print_padded "$tiny_width" 'Enter guardar · Esc cancelar'
        else
            ui_print_padded "$tiny_width" '↑↓ Enter · Supr · ←/→ detalles · Esc'
        fi
        printf '\n'
        tput ed 2>/dev/null || true
        return 0
    fi

    local width
    ui_layout_width "$UI_COLS" state
    width=$UI_LAYOUT_WIDTH

    if ui_desktop_enabled "$UI_COLS" "$UI_LINES" "$UI_LAYOUT_MODE"; then
        ui_search_desktop "$width"
    else
        ui_search_single_column "$width"
    fi
}
