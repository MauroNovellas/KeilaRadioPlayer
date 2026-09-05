#!/usr/bin/env bash

# Vista de escritorio para terminales anchas. Se carga después de ui-responsive.sh
# y ui-safe-width.sh. Conserva el render responsive original como fallback y solo
# reemplaza ui_draw cuando hay espacio real para dos paneles.

UI_DESKTOP_MIN_COLS=112
UI_DESKTOP_MIN_LINES=20
UI_DESKTOP_LEFT_WIDTH=0
UI_DESKTOP_RIGHT_WIDTH=0

# Guardamos la implementación responsive existente antes de redefinir ui_draw.
# La definición proviene de nuestro propio código, no de entrada externa.
if ! declare -F ui_draw_single_column >/dev/null 2>&1; then
    UI_DRAW_SINGLE_DEFINITION=$(declare -f ui_draw)
    UI_DRAW_SINGLE_DEFINITION=${UI_DRAW_SINGLE_DEFINITION/ui_draw ()/ui_draw_single_column ()}
    eval "$UI_DRAW_SINGLE_DEFINITION"
    unset UI_DRAW_SINGLE_DEFINITION
fi

ui_desktop_enabled() {
    local cols="${1:-$UI_COLS}"
    local lines="${2:-$UI_LINES}"
    local mode="${3:-$UI_LAYOUT_MODE}"

    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=24

    [[ "$mode" == 'wide' ]] || return 1
    ((cols >= UI_DESKTOP_MIN_COLS && lines >= UI_DESKTOP_MIN_LINES))
}

ui_desktop_pane_widths() {
    local width="$1"
    local usable left right

    # Una fila de paneles ocupa:
    # │ + espacio + izquierda + espacio + │ + espacio + derecha + espacio + │
    usable=$((width - 7))
    ((usable < 86)) && usable=86

    left=$((usable * 42 / 100))
    ((left < 40)) && left=40
    ((left > 58)) && left=58

    right=$((usable - left))
    if ((right < 46)); then
        right=46
        left=$((usable - right))
    fi

    UI_DESKTOP_LEFT_WIDTH=$left
    UI_DESKTOP_RIGHT_WIDTH=$right
}

ui_desktop_glyph() {
    local name="$1"
    if ((UI_UNICODE)); then
        case "$name" in
            top) printf '┬' ;;
            bottom) printf '┴' ;;
            cross) printf '┼' ;;
        esac
    else
        printf '+'
    fi
}

ui_desktop_rule_segment() {
    local span="$1"
    local label="${2:-}"
    local style="${3:-accent}"

    if [[ -z "$label" ]]; then
        ui_repeat_char "$UI_H" "$span"
        return 0
    fi

    local prefix="$UI_H " suffix=' '
    local label_max=$((span - ${#prefix} - ${#suffix}))
    ((label_max < 1)) && label_max=1
    label=$(ui_truncate "$label" "$label_max")

    printf '%s' "$prefix"
    ui_style_end
    ui_style_begin "$style"
    printf '%s' "$label"
    ui_style_end
    ui_style_begin muted
    printf '%s' "$suffix"

    local used=$((${#prefix} + ${#label} + ${#suffix}))
    ((used < span)) && ui_repeat_char "$UI_H" "$((span - used))"
}

ui_desktop_header_rule() {
    local width="$1"
    local left_label="$2"
    local right_label="$3"
    local left_span=$((UI_DESKTOP_LEFT_WIDTH + 2))
    local right_span=$((UI_DESKTOP_RIGHT_WIDTH + 2))

    ui_style_begin muted
    printf '%s' "$UI_ML"
    ui_desktop_rule_segment "$left_span" "$left_label" accent
    printf '%s' "$(ui_desktop_glyph top)"
    ui_desktop_rule_segment "$right_span" "$right_label" accent
    printf '%s' "$UI_MR"
    ui_style_end
    printf '\n'

    # width se usa como contrato de geometría aunque la suma se derive de panes.
    : "$width"
}

ui_desktop_join_rule() {
    local width="$1"
    local left_span=$((UI_DESKTOP_LEFT_WIDTH + 2))
    local right_span=$((UI_DESKTOP_RIGHT_WIDTH + 2))

    ui_style_begin muted
    printf '%s' "$UI_ML"
    ui_repeat_char "$UI_H" "$left_span"
    printf '%s' "$(ui_desktop_glyph bottom)"
    ui_repeat_char "$UI_H" "$right_span"
    printf '%s' "$UI_MR"
    ui_style_end
    printf '\n'
    : "$width"
}

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

    if ((selected)); then
        left_style='selected'
        left_badge_style='selected'
    fi

    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf ' '
    ui_print_split_styled "$UI_DESKTOP_LEFT_WIDTH" "$left_text" "$left_badge" "$left_style" "$left_badge_style"
    printf ' '
    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf ' '
    ui_print_split_styled "$UI_DESKTOP_RIGHT_WIDTH" "$right_text" "$right_badge" "$right_style" "$right_badge_style"
    printf ' '
    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf '\n'
}

ui_desktop_body_height() {
    local control_lines
    control_lines=$(ui_control_line_count)

    # Superior + título + cabecera paneles + unión + mensaje + borde = 6.
    local height=$((UI_LINES - 6 - control_lines))
    ((height < 8)) && height=8
    printf '%s\n' "$height"
}

ui_desktop_sync_selection() {
    local height="$1"
    local count=${#FAVORITE_NAMES[@]}

    if ((count == 0)); then
        UI_SELECTED_INDEX=0
        UI_SCROLL_OFFSET=0
        return 0
    fi

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
}

ui_desktop_player_state_style() {
    if ! player_is_running; then
        printf 'muted'
    elif ((PLAYER_PAUSED || PLAYER_BUFFERING)); then
        printf 'warning'
    else
        printf 'playing'
    fi
}

ui_draw_desktop() {
    local width="$1"
    local title="KEILA RADIO PLAYER  ${KEILA_VERSION:-dev}"
    local body_height
    body_height=$(ui_desktop_body_height)

    ui_desktop_pane_widths "$width"
    ui_desktop_sync_selection "$body_height"

    ui_box_rule "$width" "$UI_TL" "$UI_TR"
    ui_box_center_line "$width" "$title" title
    ui_desktop_header_rule "$width" "FAVORITOS (${#FAVORITE_NAMES[@]})" 'AHORA SUENA'

    local station station_style marker favorite_badge recording_badge state_badge
    marker=$(ui_player_marker)
    if player_is_running; then
        station="$PLAYER_NAME"
        station_style='playing'
        if favorites_find_url "$PLAYER_URL" >/dev/null 2>&1; then
            favorite_badge="[$UI_FAVORITE FAVORITA]"
        else
            favorite_badge=''
        fi
    elif [[ -n "${STATE_LAST_NAME:-}" ]]; then
        station="Última: $STATE_LAST_NAME"
        station_style='muted'
        favorite_badge=''
    else
        station='Ninguna emisora seleccionada'
        station_style='muted'
        favorite_badge=''
    fi

    if ((RECORDING_ACTIVE)); then
        recording_badge="[$UI_RECORD REC $(recording_elapsed_display)]"
    else
        recording_badge=''
    fi

    state_badge=''
    if player_is_running && ((PLAYER_PAUSED)); then
        state_badge='[PAUSA]'
    elif player_is_running && ((PLAYER_BUFFERING)); then
        state_badge='[BUFFERING]'
    fi

    local right_badges='' right_badge_style=''
    if [[ -n "$recording_badge" ]]; then
        right_badges="$recording_badge"
        right_badge_style='record'
        [[ -n "$favorite_badge" ]] && right_badges+="  $favorite_badge"
        [[ -n "$state_badge" ]] && right_badges+="  $state_badge"
    elif [[ -n "$state_badge" ]]; then
        right_badges="$state_badge"
        right_badge_style='warning'
        [[ -n "$favorite_badge" ]] && right_badges+="  $favorite_badge"
    elif [[ -n "$favorite_badge" ]]; then
        right_badges="$favorite_badge"
        right_badge_style='favorite'
    fi

    local audio_info=''
    player_is_running && audio_info=$(ui_audio_info)

    local volume_bar_width volume_left volume_hint
    volume_bar_width=$((UI_DESKTOP_RIGHT_WIDTH - 17))
    ((volume_bar_width < 16)) && volume_bar_width=16
    ((volume_bar_width > 52)) && volume_bar_width=52
    volume_left="VOL $(printf '%3s' "$PLAYER_VOLUME")%  $(ui_volume_bar "$volume_bar_width")"
    volume_hint='A/D  ←/→'

    local row index left_marker left_badge left_style left_badge_style selected
    local right_text right_badge right_style right_style_badge
    for ((row = 0; row < body_height; row++)); do
        index=$((UI_SCROLL_OFFSET + row))
        left_marker='  '
        left_badge=''
        left_style=''
        left_badge_style=''
        selected=0

        if ((index < ${#FAVORITE_NAMES[@]})); then
            ((index == UI_SELECTED_INDEX)) && { left_marker="$UI_SELECT "; selected=1; }

            if player_is_running && [[ "${FAVORITE_URLS[$index]}" == "$PLAYER_URL" ]]; then
                left_style='playing'
                left_badge_style='playing'
                left_badge='[PLAY]'
                [[ "$left_marker" == '  ' ]] && left_marker="$UI_PLAY "
            elif [[ -n "${STATE_LAST_URL:-}" && "${FAVORITE_URLS[$index]}" == "$STATE_LAST_URL" ]]; then
                left_badge='[ÚLTIMA]'
                left_badge_style='muted'
            fi

            left_marker+="${FAVORITE_NAMES[$index]}"
        else
            left_marker=''
        fi

        right_text=''
        right_badge=''
        right_style=''
        right_style_badge=''

        case "$row" in
            0)
                right_text="$marker $station"
                right_badge="$right_badges"
                right_style="$station_style"
                right_style_badge="$right_badge_style"
                ;;
            1)
                if player_is_running && [[ -n "${PLAYER_STREAM_TITLE:-}" ]]; then
                    right_text="$UI_NOTE $PLAYER_STREAM_TITLE"
                    right_style='accent'
                else
                    right_text='Sin título de emisión disponible'
                    right_style='muted'
                fi
                ;;
            2)
                if [[ -n "$audio_info" ]]; then
                    right_text="$audio_info"
                    right_style='muted'
                fi
                ;;
            4)
                right_text="$volume_left"
                right_badge="$volume_hint"
                right_style='accent'
                right_style_badge='muted'
                ;;
            5)
                right_text='ESTADO'
                right_badge=$(ui_player_status)
                right_style='muted'
                right_style_badge=$(ui_desktop_player_state_style)
                ;;
            6)
                if ((RECORDING_ACTIVE)); then
                    right_text='GRABACIÓN'
                    right_badge=$(recording_filename)
                    right_style='record'
                    right_style_badge='record'
                fi
                ;;
        esac

        ui_desktop_row "$left_marker" "$left_badge" "$left_style" "$left_badge_style" \
            "$right_text" "$right_badge" "$right_style" "$right_style_badge" "$selected"
    done

    ui_desktop_join_rule "$width"
    ui_draw_responsive_controls "$width"

    if [[ -n "$UI_MESSAGE" ]]; then
        ui_box_line "$width" "$UI_MESSAGE"
    else
        ui_box_line "$width" ''
    fi
    ui_box_rule "$width" "$UI_BL" "$UI_BR"
    tput ed 2>/dev/null || true
}

ui_draw() {
    ((UI_ACTIVE)) || return 0
    ((UI_SUSPENDED)) && return 0

    ui_refresh_size
    UI_LAYOUT_MODE=$(ui_layout_mode "$UI_COLS" "$UI_LINES")

    if ui_desktop_enabled "$UI_COLS" "$UI_LINES" "$UI_LAYOUT_MODE"; then
        tput cup 0 0 2>/dev/null || true
        local width
        width=$(ui_layout_width "$UI_COLS")
        ui_draw_desktop "$width"
        return 0
    fi

    ui_draw_single_column
}
