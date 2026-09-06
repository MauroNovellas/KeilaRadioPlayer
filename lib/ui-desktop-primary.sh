#!/usr/bin/env bash

# Ajuste de composición desktop: "Ahora suena" ocupa el panel principal de la
# izquierda y Favoritos queda como columna de navegación a la derecha.
# Se carga después de ui-desktop.sh y redefine solo geometría/render desktop.

ui_desktop_pane_widths() {
    local width="$1"
    local usable favorites now_playing

    # Una fila de paneles ocupa:
    # │ + espacio + izquierda + espacio + │ + espacio + derecha + espacio + │
    usable=$((width - 7))
    ((usable < 86)) && usable=86

    # Favoritos queda contenido; todo el ancho extra se entrega a Ahora suena.
    favorites=$((usable * 42 / 100))
    ((favorites < 40)) && favorites=40
    ((favorites > 58)) && favorites=58

    now_playing=$((usable - favorites))
    if ((now_playing < 46)); then
        now_playing=46
        favorites=$((usable - now_playing))
    fi

    UI_DESKTOP_LEFT_WIDTH=$now_playing
    UI_DESKTOP_RIGHT_WIDTH=$favorites
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

    # La selección pertenece ahora al panel derecho de Favoritos.
    if ((selected)); then
        right_style='selected'
        right_badge_style='selected'
    fi

    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf ' '
    ui_print_split_styled "$UI_DESKTOP_LEFT_WIDTH" "$left_text" "$left_badge" "$left_style" "$left_badge_style"
    printf ' '
    if [[ "$right_style" == separator ]]; then
        # La regla ocupa también los márgenes y conecta con ambos bordes.
        ui_style_begin muted
        printf '%s' "$UI_ML"
        ui_repeat_char "$UI_H" "$((UI_DESKTOP_RIGHT_WIDTH + 2))"
        printf '%s' "$UI_MR"
        ui_style_end
        printf '\n'
        return 0
    fi
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

ui_draw_desktop() {
    local width="$1"
    local title="KEILA RADIO PLAYER  ${KEILA_VERSION:-dev}"
    local body_height
    body_height=$(ui_desktop_body_height)

    ui_desktop_pane_widths "$width"
    ui_desktop_sync_selection "$body_height"

    ui_box_rule "$width" "$UI_TL" "$UI_TR"
    ui_box_center_line "$width" "$title" title
    ui_desktop_header_rule "$width" 'AHORA SUENA' "FAVORITOS (${#FAVORITE_NAMES[@]})"

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

    local main_badges='' main_badge_style=''
    if [[ -n "$recording_badge" ]]; then
        main_badges="$recording_badge"
        main_badge_style='record'
        [[ -n "$favorite_badge" ]] && main_badges+="  $favorite_badge"
        [[ -n "$state_badge" ]] && main_badges+="  $state_badge"
    elif [[ -n "$state_badge" ]]; then
        main_badges="$state_badge"
        main_badge_style='warning'
        [[ -n "$favorite_badge" ]] && main_badges+="  $favorite_badge"
    elif [[ -n "$favorite_badge" ]]; then
        main_badges="$favorite_badge"
        main_badge_style='favorite'
    fi

    local audio_info=''
    player_is_running && audio_info=$(ui_audio_info)

    local volume_bar_width volume_left volume_hint
    volume_bar_width=$((UI_DESKTOP_LEFT_WIDTH - 22))
    ((volume_bar_width < 16)) && volume_bar_width=16
    ((volume_bar_width > 56)) && volume_bar_width=56
    volume_left="VOL $(printf '%3s' "$PLAYER_VOLUME")%  $(ui_volume_bar "$volume_bar_width")"
    volume_hint='A/D  ←/→'

    local row index fav_marker preset_label fav_badge fav_style fav_badge_style selected
    local main_text main_badge main_style main_style_badge spectrum_cells
    local spectrum_columns=16 spectrum_badge_width=4 spectrum_available_width
    if ((SPECTRUM_ENABLED)); then
        if ((${EQUALIZER_EDITOR_ACTIVE:-0})); then
            local selected_eq_badge
            printf -v selected_eq_badge '%s %s  %+d dB' "$UI_SELECT" "${EQUALIZER_LABELS[EQUALIZER_SELECTED]}" "${EQUALIZER_GAINS[EQUALIZER_SELECTED]}"
            spectrum_badge_width=${#selected_eq_badge}
        fi
        spectrum_available_width=$((UI_DESKTOP_LEFT_WIDTH - 29 - 2 - spectrum_badge_width - 1))
        if ((spectrum_available_width < 10)); then
            spectrum_badge_width=0
            spectrum_available_width=$((UI_DESKTOP_LEFT_WIDTH - 29 - 2))
        fi
        ((spectrum_available_width < spectrum_columns)) && spectrum_columns=$spectrum_available_width
        ((spectrum_columns < 1)) && spectrum_columns=1
    fi
    for ((row = 0; row < body_height; row++)); do
        main_text=''
        main_badge=''
        main_style=''
        main_style_badge=''

        case "$row" in
            0)
                main_text="$marker $station"
                main_badge="$main_badges"
                main_style="$station_style"
                main_style_badge="$main_badge_style"
                ;;
            1)
                if player_is_running && [[ -n "${PLAYER_STREAM_TITLE:-}" ]]; then
                    main_text="$UI_NOTE $PLAYER_STREAM_TITLE"
                    main_style='accent'
                else
                    main_text='Sin título de emisión disponible'
                    main_style='muted'
                fi
                ;;
            2)
                if [[ -n "$audio_info" ]]; then
                    main_text="$audio_info"
                    main_style='muted'
                fi
                ;;
            3)
                main_text="$volume_left"
                main_badge="$volume_hint"
                main_style='accent'
                main_style_badge='muted'
                ;;
            4|5|6|7|8|9|10|11)
                ui_equalizer_editor_row "$((row - 4))"
                main_text="$UI_EQ_TEXT"
                if ((SPECTRUM_ENABLED)); then
                    spectrum_cells=$(ui_spectrum_editor_row "$((row - 4))" "$spectrum_columns")
                    main_text+="  $spectrum_cells"
                fi
                main_style="$UI_EQ_STYLE"
                if ((row == 4)); then
                    if ((${EQUALIZER_EDITOR_ACTIVE:-0})); then
                        if ((spectrum_badge_width > 0)); then
                            printf -v main_badge '%s  %+d dB' "${EQUALIZER_LABELS[EQUALIZER_SELECTED]}" "${EQUALIZER_GAINS[EQUALIZER_SELECTED]}"
                        else
                            main_badge=''
                        fi
                        main_style_badge='selected'
                    else
                        if ((SPECTRUM_ENABLED && spectrum_badge_width > 0)); then
                            main_badge='Z EQ'
                        elif ((SPECTRUM_ENABLED)); then
                            main_badge=''
                        else
                            main_badge='Z editar'
                        fi
                        main_style_badge='muted'
                    fi
                fi
                ;;
            12)
                main_text='ESPECTRO'
                if ((!${SPECTRUM_ENABLED:-0})); then
                    main_badge='V mostrar'
                elif [[ "${SPECTRUM_AVAILABLE:-unknown}" == no ]]; then
                    main_badge='No disponible'
                else
                    main_badge='V ocultar'
                fi
                main_style='playing'
                main_style_badge='muted'
                ;;
        esac

        index=$((UI_SCROLL_OFFSET + row))
        fav_marker='  '
        preset_label=''
        fav_badge=''
        fav_style=''
        fav_badge_style=''
        selected=0

        if ((index < ${#FAVORITE_NAMES[@]})); then
            ((index == UI_SELECTED_INDEX)) && { fav_marker="$UI_SELECT "; selected=1; }
            case "$index" in
                0|1|2|3|4|5|6|7|8) preset_label="$((index + 1)). " ;;
                9) preset_label='0. ' ;;
                *) preset_label='   ' ;;
            esac

            if player_is_running && [[ "${FAVORITE_URLS[$index]}" == "$PLAYER_URL" ]]; then
                fav_style='playing'
                fav_badge_style='playing'
                fav_badge='[PLAY]'
                [[ "$fav_marker" == '  ' ]] && fav_marker="$UI_PLAY "
            elif [[ -n "${STATE_LAST_URL:-}" && "${FAVORITE_URLS[$index]}" == "$STATE_LAST_URL" ]]; then
                fav_badge='[ÚLTIMA]'
                fav_badge_style='muted'
            fi

            fav_marker+="$preset_label${FAVORITE_NAMES[$index]}"
        else
            fav_marker=''
        fi

        ui_desktop_row "$main_text" "$main_badge" "$main_style" "$main_style_badge" \
            "$fav_marker" "$fav_badge" "$fav_style" "$fav_badge_style" "$selected"
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
