#!/usr/bin/env bash

# Capa responsive de la TUI. Se carga después de ui.sh y redefine únicamente
# decisiones de composición; no contiene lógica de reproducción ni persistencia.

UI_LAYOUT_MODE='standard'

ui_layout_mode() {
    local cols="${1:-$UI_COLS}"
    local lines="${2:-$UI_LINES}"

    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=24

    if ((cols >= 80 && lines >= 20)); then
        printf 'wide\n'
    elif ((cols >= 62 && lines >= 16)); then
        printf 'standard\n'
    elif ((cols >= 50 && lines >= 13)); then
        printf 'compact\n'
    elif ((cols >= 42 && lines >= 11)); then
        printf 'minimal\n'
    else
        printf 'tiny\n'
    fi
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
    printf '%s\n' "$cols"
}

ui_control_line_count() {
    if ((UI_HELP_VISIBLE)); then
        case "${UI_LAYOUT_MODE:-standard}" in
            wide|standard) printf '4\n' ;;
            compact) printf '2\n' ;;
            minimal|tiny) printf '1\n' ;;
        esac
    else
        printf '1\n'
    fi
}

ui_stream_info_line_count() {
    player_is_running || { printf '0\n'; return 0; }

    local count=0
    case "${UI_LAYOUT_MODE:-standard}" in
        wide|standard)
            [[ -n "${PLAYER_STREAM_TITLE:-}" ]] && ((count += 1))
            ui_has_audio_info && ((count += 1))
            ;;
        compact)
            [[ -n "${PLAYER_STREAM_TITLE:-}" ]] && ((count += 1))
            ;;
    esac
    printf '%s\n' "$count"
}

ui_list_height() {
    local info_lines control_lines height minimum
    info_lines=$(ui_stream_info_line_count)
    control_lines=$(ui_control_line_count)

    # Nueve filas fijas: marco superior, título, sección de reproducción,
    # emisora, volumen, sección de favoritos, separador inferior, mensaje y pie.
    height=$((UI_LINES - 9 - info_lines - control_lines))

    case "${UI_LAYOUT_MODE:-standard}" in
        wide|standard) minimum=3 ;;
        compact) minimum=2 ;;
        *) minimum=1 ;;
    esac
    ((height < minimum)) && height=$minimum
    printf '%s\n' "$height"
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
    case "$UI_LAYOUT_MODE:$section" in
        compact:now) printf 'RADIO' ;;
        minimal:now) printf '' ;;
        compact:favorites) printf 'FAV (%s)' "${#FAVORITE_NAMES[@]}" ;;
        minimal:favorites) printf 'FAV %s' "${#FAVORITE_NAMES[@]}" ;;
        *:now) printf 'AHORA SUENA' ;;
        *:favorites) printf 'FAVORITOS (%s)' "${#FAVORITE_NAMES[@]}" ;;
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
            [[ -n "$UI_RESP_RECORDING" ]] && UI_RESP_RECORDING="[$UI_RECORD $(recording_elapsed_display)]"
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

    UI_RESP_VOLUME_LEFT="VOL $(printf '%3s' "$PLAYER_VOLUME")%  $(ui_volume_bar "$bar_width")"
    UI_RESP_VOLUME_HINT="$hint"
}

ui_draw_responsive_controls() {
    local width="$1"

    if ((UI_HELP_VISIBLE)); then
        case "$UI_LAYOUT_MODE" in
            wide|standard)
                ui_box_line "$width" 'W/S o ↑/↓ mover   Home/End extremos   PgUp/PgDn saltar' muted
                ui_box_line "$width" 'Enter reproducir   1-9/0 directo   A/D o ←/→ volumen   P pausa' muted
                ui_box_line "$width" 'F favorito actual   J/K reordenar   X quitar seleccionado' muted
                ui_box_line "$width" 'B buscar  E etiqueta  Z EQ  V analizador  R grabar  H cerrar  Q salir' muted
                ;;
            compact)
                ui_box_line "$width" '↑↓ mover  Enter play  ←→ volumen  P pausa  F favorito' muted
                ui_box_line "$width" 'B buscar E etiqueta Z EQ V spec R rec H cerrar Q salir' muted
                ;;
            minimal)
                ui_box_line "$width" '↑↓ Enter B buscar E Z V R H cerrar Q' muted
                ;;
        esac
        return 0
    fi

    case "$UI_LAYOUT_MODE" in
        wide)
            ui_box_line "$width" "↑↓ mover $UI_SEP Enter reproducir $UI_SEP B buscar E etiqueta Z EQ V spec $UI_SEP R grabar H ayuda Q salir" muted
            ;;
        standard)
            ui_box_line "$width" "↑↓ Enter $UI_SEP B buscar $UI_SEP E etiqueta Z EQ V spec $UI_SEP R grabar $UI_SEP H ayuda Q salir" muted
            ;;
        compact)
            ui_box_line "$width" "B buscar $UI_SEP E etiq $UI_SEP Z EQ V spec $UI_SEP R rec $UI_SEP H Q salir" muted
            ;;
        minimal)
            ui_box_line "$width" '↑↓ Enter B E Z V R H Q' muted
            ;;
    esac
}

ui_draw() {
    ((UI_ACTIVE)) || return 0
    ((UI_SUSPENDED)) && return 0

    ui_refresh_size
    UI_LAYOUT_MODE=$(ui_layout_mode "$UI_COLS" "$UI_LINES")
    ui_sync_selection
    tput cup 0 0 2>/dev/null || true

    if [[ "$UI_LAYOUT_MODE" == 'tiny' ]]; then
        local tiny_width=$UI_COLS
        ((tiny_width > 60)) && tiny_width=60
        ui_print_padded "$tiny_width" "Keila Radio Player ${KEILA_VERSION:-dev}"
        printf '\n\n'
        ui_print_padded "$tiny_width" "Terminal demasiado pequeña: ${UI_COLS}x${UI_LINES}."
        printf '\n'
        ui_print_padded "$tiny_width" 'Mínimo útil: 42 columnas y 11 filas.'
        printf '\n\n'
        ui_print_padded "$tiny_width" 'Q = salir'
        printf '\n'
        tput ed 2>/dev/null || true
        return 0
    fi

    local width title now_label favorites_label
    width=$(ui_layout_width "$UI_COLS")
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

    ui_responsive_badges "$recording_badge" "$favorite_badge" "$state_badge"
    ui_box_player_line "$width" "$marker $station" "$station_style" "$UI_RESP_RECORDING" "$UI_RESP_FAVORITE" "$UI_RESP_STATE"

    if player_is_running; then
        case "$UI_LAYOUT_MODE" in
            wide|standard)
                [[ -n "${PLAYER_STREAM_TITLE:-}" ]] && ui_box_line "$width" "$UI_NOTE $PLAYER_STREAM_TITLE" accent
                local audio_info
                audio_info=$(ui_audio_info)
                [[ -n "$audio_info" ]] && ui_box_line "$width" "  $audio_info" muted
                ;;
            compact)
                [[ -n "${PLAYER_STREAM_TITLE:-}" ]] && ui_box_line "$width" "$UI_NOTE $PLAYER_STREAM_TITLE" accent
                ;;
        esac
    fi

    ui_responsive_volume_line "$width"
    UI_RESP_VOLUME_HINT="$(ui_equalizer_mini_graph compact)"
    ui_box_split_line "$width" "$UI_RESP_VOLUME_LEFT" "$UI_RESP_VOLUME_HINT" 0 accent muted
    ui_box_rule "$width" "$UI_ML" "$UI_MR" "$favorites_label" accent

    local height
    height=$(ui_list_height)
    ui_navigation_refresh
    if ((height >= 3)); then
        ui_box_split_line "$width" '  EMISORAS' "$(ui_labels_header "$((width - 4))")" 0 accent accent
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
    ui_box_rule "$width" "$UI_BL" "$UI_BR"
    tput ed 2>/dev/null || true
}
