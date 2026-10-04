#!/usr/bin/env bash

# Capa responsive de la TUI. Se carga después de ui.sh y redefine únicamente
# decisiones de composición; no contiene lógica de reproducción ni persistencia.

UI_LAYOUT_MODE='standard'

ui_small_screen() {
    case "${UI_LAYOUT_MODE:-standard}" in
        compact|minimal|tiny) return 0 ;;
        *) return 1 ;;
    esac
}

ui_layout_mode() {
    local cols="${1:-$UI_COLS}"
    local lines="${2:-$UI_LINES}"

    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=24

    if ((cols >= 80 && lines >= 20)); then
        UI_LAYOUT_MODE_VALUE=wide
    elif ((cols >= 62 && lines >= 16)); then
        UI_LAYOUT_MODE_VALUE=standard
    elif ((cols >= 50 && lines >= 13)); then
        UI_LAYOUT_MODE_VALUE=compact
    elif ((cols >= 42 && lines >= 11)); then
        UI_LAYOUT_MODE_VALUE=minimal
    else
        UI_LAYOUT_MODE_VALUE=tiny
    fi
    [[ ${3:-} == state ]] || printf '%s\n' "$UI_LAYOUT_MODE_VALUE"
    return 0
}

ui_layout_width() {
    local cols="${1:-$UI_COLS}"
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    case "${UI_LAYOUT_MODE:-standard}" in
        wide)
            ((cols > 92)) && cols=92
            ;;
        standard)
            ((cols > 78)) && cols=78
            ;;
    esac
    UI_LAYOUT_WIDTH=$cols
    [[ ${2:-} == state ]] || printf '%s\n' "$cols"
    return 0
}

ui_control_line_count() {
    UI_CONTROL_LINE_COUNT=0
    if ((UI_HELP_VISIBLE)); then
        case "${UI_LAYOUT_MODE:-standard}" in
            wide|standard) UI_CONTROL_LINE_COUNT=4 ;;
            compact) UI_CONTROL_LINE_COUNT=2 ;;
            minimal|tiny) UI_CONTROL_LINE_COUNT=1 ;;
        esac
    else
        UI_CONTROL_LINE_COUNT=1
    fi
    [[ ${1:-} == state ]] || printf '%s\n' "$UI_CONTROL_LINE_COUNT"
    return 0
}

ui_stream_info_line_count() {
    local count=0 track_count=0
    if player_is_running; then
        case "${UI_LAYOUT_MODE:-standard}" in
        wide|standard)
            ((count += 1))
            if ((${UI_LINES:-0} >= 25)) && declare -F track_history_display_limit >/dev/null 2>&1; then
                track_history_display_limit state
                track_count=$TRACK_HISTORY_LIMIT
                ((count += 2 + track_count))
            fi
            ((count += 1))
            ;;
        compact)
            [[ -n "${PLAYER_STREAM_TITLE:-}" ]] && ((count += 1))
            ;;
        esac
    fi
    UI_STREAM_INFO_LINE_COUNT=$count
    [[ ${1:-} == state ]] || printf '%s\n' "$count"
    return 0
}

ui_list_height() {
    local info_lines control_lines height minimum
    ui_stream_info_line_count state
    info_lines=$UI_STREAM_INFO_LINE_COUNT
    ui_control_line_count state
    control_lines=$UI_CONTROL_LINE_COUNT

    # Nueve filas fijas: marco superior, título, sección de reproducción,
    # emisora, volumen, sección de favoritos, separador inferior, mensaje y pie.
    height=$((UI_LINES - 9 - info_lines - control_lines))

    case "${UI_LAYOUT_MODE:-standard}" in
        wide|standard) minimum=3 ;;
        compact) minimum=2 ;;
        *) minimum=1 ;;
    esac
    ((height < minimum)) && height=$minimum
    UI_LIST_HEIGHT=$height
    [[ ${1:-} == state ]] || printf '%s\n' "$height"
    return 0
}

ui_responsive_title() {
    local version="${KEILA_VERSION:-dev}"
    case "$UI_LAYOUT_MODE" in
        wide|standard) printf 'KEILA RADIO PLAYER  %s' "$version" ;;
        compact) printf 'KEILA RADIO  %s' "$version" ;;
        minimal) printf 'KEILA  %s' "$version" ;;
    esac
}

ui_responsive_section_title() {
    local section="$1"
    if [[ $section == now ]] && ui_small_screen && player_is_running; then
        ui_quality_info state
        printf '[%s] Calidad' "$UI_QUALITY_KEY"
        return 0
    fi
    case "$UI_LAYOUT_MODE:$section" in
        compact:now) printf 'RADIO' ;;
        minimal:now) printf '' ;;
        compact:favorites) printf 'FAV (%s)' "${#FAVORITE_NAMES[@]}" ;;
        minimal:favorites) printf 'FAV %s' "${#FAVORITE_NAMES[@]}" ;;
        *:now) printf 'AHORA SUENA' ;;
        *:favorites) printf 'EMISORAS FAVORITAS (%s)' "${#FAVORITE_NAMES[@]}" ;;
    esac
}

ui_responsive_badges() {
    local recording="$1"
    local favorite="$2"
    local state="$3"

    UI_RESP_RECORDING="$recording"
    UI_RESP_FAVORITE="$favorite"
    UI_RESP_STATE="$state"

    case "$UI_LAYOUT_MODE" in
        compact)
            [[ -n "$UI_RESP_RECORDING" ]] && UI_RESP_RECORDING="[$UI_RECORD $(ui_recording_status_display)]"
            [[ -n "$UI_RESP_FAVORITE" ]] && UI_RESP_FAVORITE="[$UI_FAVORITE]"
            ;;
        minimal)
            if [[ -n "$UI_RESP_STATE" ]]; then
                UI_RESP_RECORDING=''
                UI_RESP_FAVORITE=''
            elif [[ -n "$UI_RESP_RECORDING" ]]; then
                UI_RESP_RECORDING="[$UI_RECORD REC]"
                UI_RESP_FAVORITE=''
            else
                UI_RESP_FAVORITE=''
            fi
            ;;
    esac
}

ui_responsive_volume_line() {
    local width="$1"
    local bar_width hint

    case "$UI_LAYOUT_MODE" in
        wide)
            bar_width=$(ui_volume_bar_width "$width")
            hint='A/D  ←/→'
            ;;
        standard)
            bar_width=$(ui_volume_bar_width "$width")
            ((bar_width > 20)) && bar_width=20
            hint='←/→'
            ;;
        compact)
            bar_width=12
            hint='←/→'
            ;;
        minimal)
            bar_width=$((width - 18))
            ((bar_width < 6)) && bar_width=6
            ((bar_width > 12)) && bar_width=12
            hint=''
            ;;
    esac

    ui_volume_bar "$bar_width" state
    printf -v UI_RESP_VOLUME_LEFT 'VOL %3s%%  %s' "$PLAYER_VOLUME" "$UI_VOLUME_BAR"
    UI_RESP_VOLUME_HINT="$hint"
}

ui_draw_responsive_controls() {
    local width="$1"

    if ((UI_HELP_VISIBLE)); then
        case "$UI_LAYOUT_MODE" in
            wide|standard)
                ui_box_line "$width" 'W/S o ↑/↓ mover   Home/End extremos   PgUp/PgDn saltar' muted
                ui_box_line "$width" 'Enter reproducir   1-9/0 directo   A/D o ←/→ volumen   P pausa' muted
                ui_box_line "$width" 'F Favoritas X favorito J/K ordenar M silencio L alarma' muted
                ui_box_line "$width" 'F favoritas C comentario R recientes G grabar O opciones Z ecualizador V espectrograma D diagnóstico H cerrar Q salir' muted
                ;;
            compact)
                ui_box_line "$width" '↑↓ mover  Enter play  ←→ volumen  P pausa  F Favoritas X favorito' muted
                ui_box_line "$width" 'F favoritas C comentario R recientes G grabar O opciones Z/V audio D diagnóstico H cerrar Q salir' muted
                ;;
            minimal)
                ui_box_line "$width" '↑↓ Enter B F C R G O D H Q' muted
                ;;
        esac
        return 0
    fi

    case "$UI_LAYOUT_MODE" in
        wide)
            ui_box_line "$width" "↑↓ Enter $UI_SEP F fav. C com. R rec. G grab. $UI_SEP D diag. H ayuda Q salir" muted
            ;;
        standard)
            ui_box_line "$width" "↑↓ Enter $UI_SEP F fav. C com. R rec. G grab. $UI_SEP D diag. H ayuda Q salir" muted
            ;;
        compact)
            ui_box_line "$width" "F fav C coment R rec G grab $UI_SEP B D H Q" muted
            ;;
        minimal)
            ui_box_line "$width" '↑↓ Enter B F C R G D H Q' muted
            ;;
    esac
}

ui_draw() {
    ((UI_ACTIVE)) || return 0
    ((UI_SUSPENDED)) && return 0

    ui_refresh_size
    ui_layout_mode "$UI_COLS" "$UI_LINES" state
    UI_LAYOUT_MODE=$UI_LAYOUT_MODE_VALUE
    ui_sync_selection
    tput cup 0 0 2>/dev/null || true

    if [[ "$UI_LAYOUT_MODE" == 'tiny' ]]; then
        # ui-safe-width.sh sustituye ui_layout_width por la variante que
        # reserva la última celda física. Mantener el cálculo aquí evita que
        # la pantalla de emergencia sea la única que active autowrap.
        local tiny_width
        ui_layout_width "$UI_COLS" state
        tiny_width=$UI_LAYOUT_WIDTH
        ((tiny_width > 60)) && tiny_width=60
        ui_print_padded "$tiny_width" "Keila Radio Player ${KEILA_VERSION:-dev}"
        printf '\n\n'
        ui_print_padded "$tiny_width" "Terminal demasiado pequeña: ${UI_COLS}x${UI_LINES}."
        printf '\n'
        ui_print_padded "$tiny_width" 'Mínimo útil: 42 columnas y 11 filas.'
        printf '\n\n'
        ui_quality_info state
        ui_print_padded "$tiny_width" "[$UI_QUALITY_KEY] Calidad · Q salir"
        printf '\n'
        tput ed 2>/dev/null || true
        return 0
    fi

    local width title now_label favorites_label
    ui_layout_width "$UI_COLS" state
    width=$UI_LAYOUT_WIDTH
    title=$(ui_responsive_title)
    now_label=$(ui_responsive_section_title now)
    favorites_label=$(ui_responsive_section_title favorites)

    ui_box_rule "$width" "$UI_TL" "$UI_TR"
    ui_box_center_line "$width" "$title" title
    ui_box_rule "$width" "$UI_ML" "$UI_MR" "$now_label" accent

    local station favorite_badge recording_badge state_badge marker station_style
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
        recording_badge="[$UI_RECORD $(ui_recording_status_display)]"
    else
        recording_badge=''
    fi

    state_badge=''
    if player_is_running && ((PLAYER_PAUSED)); then
        state_badge='[PAUSA]'
    elif player_is_running && ((PLAYER_BUFFERING)); then
        state_badge='[BUFFERING]'
    fi

    ui_responsive_badges "$recording_badge" "$favorite_badge" "$state_badge"
    ui_box_player_line "$width" "$marker $station" "$station_style" "$UI_RESP_RECORDING" "$UI_RESP_FAVORITE" "$UI_RESP_STATE"

    if player_is_running; then
        case "$UI_LAYOUT_MODE" in
            wide|standard)
                if [[ -n "${PLAYER_STREAM_TITLE:-}" ]]; then
                    ui_box_line "$width" "$UI_NOTE $PLAYER_STREAM_TITLE" accent
                else
                    ui_box_line "$width" 'Sin título de emisión disponible' muted
                fi
                local track_history_count=0 track_history_index track_history_info=''
                if ((${UI_LINES:-0} >= 25)) && declare -F track_history_display_limit >/dev/null 2>&1; then
                    track_history_display_limit state
                    track_history_count=$TRACK_HISTORY_LIMIT
                fi
                if ((track_history_count > 0)); then
                    ui_box_line "$width" '  Canciones anteriores' accent
                    for ((track_history_index = 0; track_history_index < track_history_count; track_history_index++)); do
                        track_history_line "$track_history_index" "$((width - 4))" state || true
                        track_history_info=$TRACK_HISTORY_LINE
                        ui_box_line "$width" "$track_history_info" muted
                    done
                    track_history_session_line "$((width - 4))" state || true
                    track_history_info=$TRACK_HISTORY_LINE
                    ui_box_line "$width" "$track_history_info" muted
                fi
                local audio_info
                ui_quality_info state
                audio_info=$UI_QUALITY_INFO
                ui_box_line "$width" "$audio_info" quality
                ;;
            compact)
                [[ -n "${PLAYER_STREAM_TITLE:-}" ]] && ui_box_line "$width" "$UI_NOTE $PLAYER_STREAM_TITLE" accent
                ;;
        esac
    fi

    ui_responsive_volume_line "$width"
    if ! ui_small_screen; then
        UI_RESP_VOLUME_HINT="$(ui_equalizer_mini_graph compact)"
    fi
    ui_box_split_line "$width" "$UI_RESP_VOLUME_LEFT" "$UI_RESP_VOLUME_HINT" 0 accent muted
    ui_box_rule "$width" "$UI_ML" "$UI_MR" "$favorites_label" accent

    local height
    ui_list_height state
    height=$UI_LIST_HEIGHT
    ui_navigation_refresh
    if ((height >= 3)); then
        local comments_header=''
        if ! ui_small_screen; then comments_header=$(ui_labels_header "$((width - 4))"); fi
        ui_box_split_line "$width" '  EMISORAS' "$comments_header" 0 accent accent
        ((height -= 1))
    fi
    ui_navigation_sync "$height"
    local row
    for ((row = 0; row < height; row++)); do
        ui_navigation_row "$row"
        ui_box_split_line "$width" "$UI_NAV_TEXT" "$UI_NAV_BADGE" "$UI_NAV_SELECTED" "$UI_NAV_STYLE" "$UI_NAV_BADGE_STYLE"
    done

    ui_box_rule "$width" "$UI_ML" "$UI_MR"
    ui_draw_responsive_controls "$width"

    if [[ -n "$UI_MESSAGE" ]]; then
        ui_box_line "$width" "$UI_MESSAGE"
    else
        ui_box_line "$width" ''
    fi
    ui_box_rule "$width" "$UI_BL" "$UI_BR" '' muted final
    tput ed 2>/dev/null || true
}
