#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Menú jerárquico de opciones para usuarios que no quieren memorizar atajos.

OPTIONS_ACTIVE=0
OPTIONS_SELECTED=0
OPTIONS_SCROLL=0
OPTIONS_TITLE='OPCIONES'
OPTIONS_INTRO='Elige una categoría. Esc vuelve al reproductor.'
OPTIONS_FOOTER='↑↓ seleccionar · Enter abrir · Esc volver'
declare -a OPTIONS_ROWS=()

options_bool_label() {
    if (($1)); then printf 'activado'; else printf 'desactivado'; fi
}

options_selected_recent() {
    favorites_load >/dev/null 2>&1 || true
    ui_navigation_refresh
    ((UI_SELECTED_INDEX >= ${#FAVORITE_NAMES[@]} && UI_SELECTED_INDEX < ${#FAVORITE_NAMES[@]} + ${#RECENT_NAMES[@]}))
}

options_toggle_selected_favorite() {
    if options_selected_recent; then app_toggle_selected_recent_favorite || true; else app_toggle_favorite || true; fi
}

options_toggle_color() {
    PREF_COLOR=$((1 - PREF_COLOR))
    preferences_apply
    if preferences_save; then
        if ((PREF_COLOR)); then app_message 'Colores activados.' 4; else app_message 'Colores desactivados.' 4; fi
    else
        app_message 'No se pudo guardar la preferencia de colores.' 7
    fi
}

options_toggle_unicode() {
    PREF_UNICODE=$((1 - PREF_UNICODE))
    preferences_apply
    if preferences_save; then
        if ((PREF_UNICODE)); then app_message 'Unicode activado si la terminal lo permite.' 4; else app_message 'Unicode desactivado: modo ASCII.' 4; fi
    else
        app_message 'No se pudo guardar la preferencia de Unicode.' 7
    fi
}

options_toggle_autoplay() {
    PREF_AUTOPLAY=$((1 - PREF_AUTOPLAY))
    if preferences_save; then
        if ((PREF_AUTOPLAY)); then app_message 'Inicio automático activado.' 4; else app_message 'Inicio automático desactivado.' 4; fi
    else
        app_message 'No se pudo guardar la preferencia de inicio automático.' 7
    fi
}

options_cancel_alarm() {
    alarm_set ''
}

options_build_rows() {
    local menu=${1:-main}
    local spectrum_state color_state unicode_state autoplay_state
    spectrum_state=$(options_bool_label "${SPECTRUM_ENABLED:-0}")
    color_state=$(options_bool_label "${PREF_COLOR:-0}")
    unicode_state=$(options_bool_label "${PREF_UNICODE:-0}")
    autoplay_state=$(options_bool_label "${PREF_AUTOPLAY:-0}")

    case "$menu" in
        main)
            OPTIONS_TITLE='OPCIONES'
            OPTIONS_INTRO='Elige una categoría. Esc vuelve al reproductor.'
            OPTIONS_FOOTER='↑↓ seleccionar · Enter abrir · P/E/V/T/G/S/C/D/H directo · Esc volver'
            OPTIONS_ROWS=(
                'P|Reproducción|Pausa, silencio, volumen y reproducción de la selección|menu:playback'
                'E|Emisoras|Buscar, actualizar, favoritos, recientes y comentarios|menu:stations'
                'V|Visualización|Espectrograma, ecualizador, colores y Unicode|menu:visual'
                'T|Temporizador|Alarma temporal de esta sesión|menu:timer'
                'G|Grabaciones|Grabar y revisar archivos conservados o pendientes|menu:recordings'
                'S|Sesión|Ver el TXT de canciones reproducidas en esta ejecución|menu:session'
                'C|Configuración|Preferencias persistentes y atajos personalizables|menu:config'
                'D|Diagnóstico|Estado del reproductor, catálogo, rutas y grabaciones|status'
                'H|Ayuda|Atajos completos y controles locales|help'
            )
            ;;
        playback)
            OPTIONS_TITLE='OPCIONES · REPRODUCCIÓN'
            OPTIONS_INTRO='Acciones de escucha. Esc vuelve a Opciones.'
            OPTIONS_FOOTER='↑↓ seleccionar · Enter ejecutar · P/M/+/-/G directo · Esc atrás'
            OPTIONS_ROWS=(
                '↵|Reproducir selección|Inicia la emisora marcada en Favoritas o Recientes|play_selected'
                'P|Pausar / reanudar|Alterna pausa sin cerrar la emisora|pause'
                'M|Silencio|Mutea o recupera el sonido de la emisora actual|mute'
                '+|Subir volumen|Aumenta el volumen y guarda el valor|volume_up'
                '-|Bajar volumen|Reduce el volumen y guarda el valor|volume_down'
                'G|Grabar / detener|Inicia o cierra la grabación del stream actual|record_toggle'
            )
            ;;
        stations)
            OPTIONS_TITLE='OPCIONES · EMISORAS'
            OPTIONS_INTRO='Búsqueda y gestión de favoritas/recientes. Esc vuelve a Opciones.'
            OPTIONS_FOOTER='↑↓ seleccionar · Enter ejecutar · B/U/F/R/X/C/J/K directo · Esc atrás'
            OPTIONS_ROWS=(
                'B|Buscar emisoras|Abre la búsqueda integrada de Radio Browser|search'
                'U|Actualizar catálogo|Actualiza la copia local diaria de emisoras|catalog_update'
                'F|Ir a Favoritas|Mueve la selección a la columna de favoritas|select_favorites'
                'R|Ir a Recientes|Mueve la selección a la columna de recientes|select_recents'
                '↵|Reproducir selección|Inicia la emisora marcada actualmente|play_selected'
                'X|Añadir / quitar favorito|Gestiona favorita según la selección actual|favorite_toggle'
                'C|Editar comentario|Edita el comentario personal de la emisora|comment'
                'K|Subir favorito|Mueve el favorito seleccionado una posición arriba|favorite_up'
                'J|Bajar favorito|Mueve el favorito seleccionado una posición abajo|favorite_down'
            )
            ;;
        visual)
            OPTIONS_TITLE='OPCIONES · VISUALIZACIÓN'
            OPTIONS_INTRO='Ajustes visuales y análisis de audio. Esc vuelve a Opciones.'
            OPTIONS_FOOTER='↑↓ seleccionar · Enter ejecutar · V/Z/C/U/A directo · Esc atrás'
            OPTIONS_ROWS=(
                "V|Espectrograma|Mostrar u ocultar el espectrograma ($spectrum_state)|spectrum"
                'Z|Ecualizador|Editar bandas y presets del ecualizador|equalizer'
                "C|Colores|Alternar colores de la interfaz ($color_state)|color"
                "U|Unicode|Alternar símbolos Unicode/ASCII ($unicode_state)|unicode"
                'A|Ajustes y atajos|Abrir configuración completa y atajos personalizables|settings'
            )
            ;;
        timer)
            OPTIONS_TITLE='OPCIONES · TEMPORIZADOR'
            OPTIONS_INTRO='Temporizadores de la sesión actual. Esc vuelve a Opciones.'
            OPTIONS_FOOTER='↑↓ seleccionar · Enter ejecutar · A/X directo · Esc atrás'
            OPTIONS_ROWS=(
                'A|Alarma temporal|Poner hora para encender la última emisora reproducida|alarm'
                'X|Cancelar alarma|Cancela la alarma pendiente de esta sesión|alarm_cancel'
            )
            ;;
        recordings)
            OPTIONS_TITLE='OPCIONES · GRABACIONES'
            OPTIONS_INTRO='Grabación actual y archivos pendientes. Esc vuelve a Opciones.'
            OPTIONS_FOOTER='↑↓ seleccionar · Enter ejecutar · G/R directo · Esc atrás'
            OPTIONS_ROWS=(
                'G|Grabar / detener|Inicia o cierra la grabación del stream actual|record_toggle'
                'R|Revisar grabaciones|Lista, comprueba, escucha y protege archivos|pending'
            )
            ;;
        session)
            OPTIONS_TITLE='OPCIONES · SESIÓN'
            OPTIONS_INTRO='Información generada durante esta ejecución. Esc vuelve a Opciones.'
            OPTIONS_FOOTER='↑↓ seleccionar · Enter ejecutar · S/D directo · Esc atrás'
            OPTIONS_ROWS=(
                'S|Historial de canciones|Ver el TXT de esta sesión dentro de Keila|session_history'
                'D|Diagnóstico en vivo|Ver rutas, estado de catálogo, grabaciones y reproductor|status'
            )
            ;;
        config)
            OPTIONS_TITLE='OPCIONES · CONFIGURACIÓN'
            OPTIONS_INTRO='Preferencias persistentes y documentación. Esc vuelve a Opciones.'
            OPTIONS_FOOTER='↑↓ seleccionar · Enter ejecutar · C/I/D/H directo · Esc atrás'
            OPTIONS_ROWS=(
                'C|Preferencias y atajos|Cambiar visualización, teclas e inicio automático|settings'
                "I|Inicio automático|Reproducir última emisora al abrir ($autoplay_state)|autoplay"
                'D|Diagnóstico|Comprobar estado, rutas y datos locales|status'
                'H|Ayuda completa|Ver mapa de atajos y controles locales|help'
            )
            ;;
        *)
            return 1
            ;;
    esac
}

options_parse_row() {
    local row=$1
    IFS='|' read -r OPTIONS_ROW_KEY OPTIONS_ROW_LABEL OPTIONS_ROW_DETAIL OPTIONS_ROW_ACTION <<< "$row"
}

options_clamp_selection() {
    local count=${#OPTIONS_ROWS[@]}
    ((count > 0)) || { OPTIONS_SELECTED=0 OPTIONS_SCROLL=0; return; }
    ((OPTIONS_SELECTED < 0)) && OPTIONS_SELECTED=0
    ((OPTIONS_SELECTED >= count)) && OPTIONS_SELECTED=$((count - 1))
}

options_draw() {
    ui_refresh_size
    local width=$((UI_COLS - 1)) height=$((UI_LINES - 6)) visible i row_index row marker key label detail
    ((width < 1)) && width=1
    ((height < 1)) && height=1

    options_clamp_selection
    visible=$((height / 2))
    ((visible < 1)) && visible=1
    ((visible > ${#OPTIONS_ROWS[@]})) && visible=${#OPTIONS_ROWS[@]}
    ((OPTIONS_SELECTED < OPTIONS_SCROLL)) && OPTIONS_SCROLL=$OPTIONS_SELECTED
    ((OPTIONS_SELECTED >= OPTIONS_SCROLL + visible)) && OPTIONS_SCROLL=$((OPTIONS_SELECTED - visible + 1))
    ((OPTIONS_SCROLL < 0)) && OPTIONS_SCROLL=0

    tput cup 0 0 2>/dev/null || true
    ui_print_styled_padded "$width" "KEILA · $OPTIONS_TITLE" title
    printf '\n'
    ui_print_padded "$width" "$OPTIONS_INTRO"
    printf '\n\n'

    for ((i = 0; i < visible; i++)); do
        row_index=$((OPTIONS_SCROLL + i))
        ((row_index < ${#OPTIONS_ROWS[@]})) || break
        row=${OPTIONS_ROWS[row_index]}
        options_parse_row "$row"
        key=$OPTIONS_ROW_KEY
        label=$OPTIONS_ROW_LABEL
        detail=$OPTIONS_ROW_DETAIL
        marker='  '
        ((row_index == OPTIONS_SELECTED)) && marker='> '
        ui_print_styled_padded "$width" "${marker}[${key}] $label" accent
        printf '\n'
        ui_print_padded "$width" "    $detail"
        printf '\n'
    done

    ui_print_padded "$width" "$OPTIONS_FOOTER"
    printf '\n'
    ui_print_padded "$width" "${UI_MESSAGE:-}"
    tput ed 2>/dev/null || true
}

options_execute() {
    local action=$1
    case "$action" in
        menu:*) options_menu_loop "${action#menu:}" ;;
        play_selected) app_play_selected || true ;;
        pause) app_toggle_pause || true ;;
        mute) app_toggle_mute || true ;;
        volume_up) app_change_volume "$KEILA_VOLUME_STEP" || true ;;
        volume_down) app_change_volume "$((-KEILA_VOLUME_STEP))" || true ;;
        record_toggle) app_toggle_recording || true ;;
        search) app_search_catalog || true ;;
        catalog_update) app_update_catalog || true ;;
        select_favorites) ui_select_emisoras || true ;;
        select_recents) ui_select_recientes || true ;;
        favorite_toggle) options_toggle_selected_favorite || true ;;
        comment) app_edit_label || true ;;
        favorite_up) app_move_selected_favorite -1 || true ;;
        favorite_down) app_move_selected_favorite 1 || true ;;
        spectrum) app_toggle_spectrum || true ;;
        equalizer) app_edit_equalizer || true ;;
        color) options_toggle_color || true ;;
        unicode) options_toggle_unicode || true ;;
        alarm) app_edit_alarm || true ;;
        alarm_cancel) options_cancel_alarm || true ;;
        pending) app_pending_menu || true ;;
        session_history) app_session_history_screen || true ;;
        autoplay) options_toggle_autoplay || true ;;
        settings) app_preferences_menu settings ;;
        status) app_status_screen || true ;;
        help) app_preferences_menu help ;;
    esac
    PREFERENCES_ACTIVE=1
    OPTIONS_ACTIVE=1
}

options_open_selected() {
    options_clamp_selection
    options_parse_row "${OPTIONS_ROWS[$OPTIONS_SELECTED]}"
    options_execute "$OPTIONS_ROW_ACTION"
}

options_key_select() {
    local wanted=${1,,} i row key
    [[ -n "$wanted" ]] || return 1
    for ((i = 0; i < ${#OPTIONS_ROWS[@]}; i++)); do
        row=${OPTIONS_ROWS[i]}
        options_parse_row "$row"
        key=${OPTIONS_ROW_KEY,,}
        if [[ "$wanted" == "$key" ]]; then
            OPTIONS_SELECTED=$i
            return 0
        fi
    done
    return 1
}

options_menu_loop() {
    local menu=${1:-main} event key redraw=1 previous_selected previous_scroll max_index
    previous_selected=$OPTIONS_SELECTED
    previous_scroll=$OPTIONS_SCROLL
    if [[ "$menu" != main ]]; then
        OPTIONS_SELECTED=0
        OPTIONS_SCROLL=0
    fi

    while true; do
        options_build_rows "$menu" || break
        max_index=$((${#OPTIONS_ROWS[@]} - 1))
        ((redraw)) && options_draw
        input_read || break
        event=$INPUT_EVENT
        key=$INPUT_KEY
        redraw=1

        case "$event" in
            TICK)
                redraw=0
                app_poll_player && redraw=1
                catalog_poll && redraw=1
                ui_message_tick && redraw=1
                pending_scan_poll && redraw=1
                ;;
            RESIZE)
                ;;
            ESC)
                break
                ;;
            UP)
                ((OPTIONS_SELECTED > 0)) && ((OPTIONS_SELECTED -= 1))
                ;;
            DOWN)
                ((OPTIONS_SELECTED < max_index)) && ((OPTIONS_SELECTED += 1))
                ;;
            HOME)
                OPTIONS_SELECTED=0
                ;;
            END)
                OPTIONS_SELECTED=$max_index
                ;;
            PAGE_UP)
                OPTIONS_SELECTED=$((OPTIONS_SELECTED - 5))
                ((OPTIONS_SELECTED < 0)) && OPTIONS_SELECTED=0
                ;;
            PAGE_DOWN)
                OPTIONS_SELECTED=$((OPTIONS_SELECTED + 5))
                ((OPTIONS_SELECTED > max_index)) && OPTIONS_SELECTED=$max_index
                ;;
            ENTER)
                options_open_selected
                redraw=1
                ;;
            KEY)
                if options_key_select "$key"; then
                    options_open_selected
                    redraw=1
                fi
                ;;
        esac
    done

    if [[ "$menu" != main ]]; then
        OPTIONS_SELECTED=$previous_selected
        OPTIONS_SCROLL=$previous_scroll
    fi
}

app_options_menu() {
    OPTIONS_ACTIVE=1
    OPTIONS_SELECTED=${OPTIONS_SELECTED:-0}
    OPTIONS_SCROLL=${OPTIONS_SCROLL:-0}
    PREFERENCES_ACTIVE=1

    options_menu_loop main

    PREFERENCES_ACTIVE=0
    OPTIONS_ACTIVE=0
    ui_draw
}
