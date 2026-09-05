#!/usr/bin/env bash

# Render de la búsqueda integrada. No modifica el estado del catálogo ni del
# reproductor: solo presenta SEARCH_* y reutiliza los helpers visuales actuales.

ui_search_result_parts() {
    local source_index="$1"
    UI_SEARCH_NAME="${SEARCH_NAMES[$source_index]}"
    UI_SEARCH_DETAIL=''
    UI_SEARCH_IS_FAVORITE=0

    if [[ -n "${SEARCH_AMBITS[$source_index]}" ]]; then
        UI_SEARCH_DETAIL="${SEARCH_AMBITS[$source_index]}"
    fi
    if [[ -n "${SEARCH_COUNTRIES[$source_index]}" ]]; then
        [[ -n "$UI_SEARCH_DETAIL" ]] && UI_SEARCH_DETAIL+=" $UI_SEP "
        UI_SEARCH_DETAIL+="${SEARCH_COUNTRIES[$source_index]}"
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
        [[ -n "$UI_SEARCH_DETAIL" ]] && badge+=" $UI_SEARCH_DETAIL"
    else
        badge="$UI_SEARCH_DETAIL"
    fi

    printf '%s' "$badge"
}

ui_search_desktop() {
    local width="$1"
    local title="KEILA RADIO PLAYER  ${KEILA_VERSION:-dev}"
    local body_height
    body_height=$(ui_desktop_body_height)

    ui_desktop_pane_widths "$width"
    search_sync_scroll "$body_height"

    ui_box_rule "$width" "$UI_TL" "$UI_TR"
    ui_box_center_line "$width" "$title" title
    ui_desktop_header_rule "$width" 'BUSCAR EMISORAS' "RESULTADOS (${#SEARCH_MATCHES[@]})"

    local row match_position source_index result_text result_badge result_style result_badge_style selected playing
    local left_text left_badge left_style left_badge_style
    for ((row = 0; row < body_height; row++)); do
        left_text=''
        left_badge=''
        left_style=''
        left_badge_style=''

        case "$row" in
            0)
                left_text='Buscar:'
                left_badge="${SEARCH_QUERY}_"
                left_style='accent'
                left_badge_style='selected'
                ;;
            2)
                left_text='Escribe para filtrar'
                left_style='muted'
                ;;
            3)
                left_text='Backspace borrar'
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
                left_text='F favorito  ·  Esc volver'
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
    ui_box_line "$width" "Escribe  $UI_SEP  ↑↓ mover  $UI_SEP  Enter reproducir  $UI_SEP  F favorito  $UI_SEP  Esc volver" muted
    if [[ -n "$UI_MESSAGE" ]]; then
        ui_box_line "$width" "$UI_MESSAGE"
    else
        ui_box_line "$width" ''
    fi
    ui_box_rule "$width" "$UI_BL" "$UI_BR"
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
    ui_box_rule "$width" "$UI_ML" "$UI_MR" 'BUSCAR EMISORAS' accent
    ui_box_split_line "$width" 'Buscar:' "${SEARCH_QUERY}_" 0 accent selected
    ui_box_rule "$width" "$UI_ML" "$UI_MR" "RESULTADOS (${#SEARCH_MATCHES[@]})" accent

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
        badge=$(ui_search_result_badge "$playing")
        ((UI_SEARCH_IS_FAVORITE)) && badge_style='favorite'

        if ((match_position == SEARCH_SELECTED_INDEX)); then
            text="$UI_SELECT $UI_SEARCH_NAME"
            selected=1
        elif ((playing)); then
            text="$UI_PLAY $UI_SEARCH_NAME"
            style='playing'
            badge_style='playing'
        fi

        ui_box_split_line "$width" "$text" "$badge" "$selected" "$style" "$badge_style"
    done

    ui_box_rule "$width" "$UI_ML" "$UI_MR"
    ui_box_line "$width" "Escribe  $UI_SEP  ↑↓  $UI_SEP  Enter play  $UI_SEP  F favorito  $UI_SEP  Esc" muted
    if [[ -n "$UI_MESSAGE" ]]; then
        ui_box_line "$width" "$UI_MESSAGE"
    else
        ui_box_line "$width" ''
    fi
    ui_box_rule "$width" "$UI_BL" "$UI_BR"
    tput ed 2>/dev/null || true
}

ui_draw_search() {
    ((UI_ACTIVE)) || return 0
    ((UI_SUSPENDED)) && return 0

    ui_refresh_size
    UI_LAYOUT_MODE=$(ui_layout_mode "$UI_COLS" "$UI_LINES")
    tput cup 0 0 2>/dev/null || true

    if [[ "$UI_LAYOUT_MODE" == 'tiny' ]]; then
        local tiny_width=$UI_COLS
        ((tiny_width > 60)) && tiny_width=60
        ui_print_padded "$tiny_width" "Keila Radio Player ${KEILA_VERSION:-dev}"
        printf '\n\n'
        ui_print_padded "$tiny_width" "Buscar: ${SEARCH_QUERY}_"
        printf '\n'
        ui_print_padded "$tiny_width" "Resultados: ${#SEARCH_MATCHES[@]}"
        printf '\n\n'
        ui_print_padded "$tiny_width" 'F = favorito · Esc = volver'
        printf '\n'
        tput ed 2>/dev/null || true
        return 0
    fi

    local width
    width=$(ui_layout_width "$UI_COLS")

    if ui_desktop_enabled "$UI_COLS" "$UI_LINES" "$UI_LAYOUT_MODE"; then
        ui_search_desktop "$width"
    else
        ui_search_single_column "$width"
    fi
}
