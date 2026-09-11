#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Centro de control: acciones existentes, estados en memoria y foco por menú.

OPTIONS_ACTIVE=0
OPTIONS_SELECTED=0
OPTIONS_SCROLL=0
OPTIONS_VISIBLE=1
OPTIONS_TITLE='OPCIONES'
OPTIONS_CLOSE_REQUESTED=0
OPTIONS_RESULT=0
OPTIONS_CATALOG_CHECK_AT=0
OPTIONS_CATALOG_SIGNATURE=''
OPTIONS_CATALOG_STATE='Sin catálogo'
declare -a OPTIONS_ROWS=()
declare -A OPTIONS_SELECTIONS=() OPTIONS_OFFSETS=()

options_cancel_confirmation() {
    if [[ -n "${FAVORITES_CONFIRM_URL:-}" ]]; then
        favorites_confirm_clear
        ui_clear_message
    fi
}

options_toggle_preference() {
    local preference=$1 old=${!1} label=$2
    printf -v "$preference" '%s' "$((1 - old))"
    if preferences_save; then
        preferences_apply
        app_message "$label: cambio guardado." 4
    else
        # No mostrar como persistente un cambio que no llegó al disco.
        printf -v "$preference" '%s' "$old"
        app_message "No se pudo guardar $label. Se conserva el valor anterior." 7
    fi
}

options_toggle_selected_favorite() {
    favorites_load || { app_message 'No se pudieron cargar favoritas.' 6; return 1; }
    ui_navigation_refresh
    if ((UI_SELECTED_INDEX < ${#FAVORITE_NAMES[@]})); then
        # La acción del menú siempre opera sobre la selección, aunque otra
        # emisora esté sonando. X en la pantalla principal conserva su contrato.
        app_remove_selected_favorite
    else
        app_toggle_selected_recent_favorite
    fi
    if [[ -n "${FAVORITES_CONFIRM_URL:-}" ]]; then
        app_message 'Repite Enter o X para confirmar la eliminación. Moverse cancela.' 5
    fi
}

# No analizar JSON ni contar el catálogo en el ciclo de teclado. El índice se
# comprueba al entrar, al terminar una actualización y como máximo cada 30 s.
options_catalog_refresh() {
    local now=$EPOCHSECONDS signature="${CATALOG_PID:-}|${CATALOG_LAST_ERROR:-}|${KEILA_STATIONS_TSV:-}"
    if [[ "$signature" == "$OPTIONS_CATALOG_SIGNATURE" ]] && ((now < OPTIONS_CATALOG_CHECK_AT)); then return 0; fi
    OPTIONS_CATALOG_SIGNATURE=$signature
    OPTIONS_CATALOG_CHECK_AT=$((now + 30))
    if [[ -n "${CATALOG_PID:-}" ]]; then
        OPTIONS_CATALOG_STATE='Actualizando'
    elif stations_tsv_valid; then
        local modified
        modified=$(stat -c %Y -- "$KEILA_STATIONS_TSV" 2>/dev/null) || modified=0
        if [[ "$modified" =~ ^[0-9]+$ ]] && ((now >= modified && now - modified < KEILA_CATALOG_MAX_AGE)); then
            OPTIONS_CATALOG_STATE='Al día'
        else
            OPTIONS_CATALOG_STATE='Copia anterior'
        fi
        [[ -z "${CATALOG_LAST_ERROR:-}" ]] || OPTIONS_CATALOG_STATE='Copia local'
    elif [[ -s "${KEILA_STATIONS_JSON:-}" ]]; then
        OPTIONS_CATALOG_STATE='Sin índice'
    else
        OPTIONS_CATALOG_STATE='Sin catálogo'
    fi
}

options_read_state() {
    OPTIONS_RUNNING=0
    OPTIONS_PLAYBACK='Detenido'
    if player_is_running; then
        OPTIONS_RUNNING=1
        OPTIONS_PLAYBACK='Reproduciendo'
        if ((PLAYER_PAUSED)); then OPTIONS_PLAYBACK='En pausa'
        elif ((PLAYER_BUFFERING)); then OPTIONS_PLAYBACK='Esperando audio'
        elif ((!PLAYER_STREAM_READY)); then OPTIONS_PLAYBACK='Conectando'; fi
    elif ((${APP_RECONNECT_NEXT_AT:-0} > 0)); then
        OPTIONS_PLAYBACK='Reconectando'
    fi
    OPTIONS_RECORDING='Detenida'
    OPTIONS_RECORD_LABEL='Iniciar grabación'
    if ((RECORDING_ACTIVE)); then
        OPTIONS_RECORD_LABEL='Detener grabación'
        case "${RECORDING_PHASE:-}" in
            preparing) OPTIONS_RECORDING='Preparando' ;;
            closing) OPTIONS_RECORDING='Cierre pendiente'; OPTIONS_RECORD_LABEL='Reintentar cierre' ;;
            *) OPTIONS_RECORDING='Grabando' ;;
        esac
    fi
    OPTIONS_ALARM='Sin programar'
    ((ALARM_AT > 0)) && OPTIONS_ALARM=$ALARM_LABEL
    OPTIONS_STATION_NAME='' OPTIONS_STATION_URL='' OPTIONS_STATION_LIST='Favoritas'
    local index=${UI_SELECTED_INDEX:-0}
    if ((index >= 0 && index < ${#FAVORITE_NAMES[@]})); then
        OPTIONS_STATION_NAME=${FAVORITE_NAMES[index]}
        OPTIONS_STATION_URL=${FAVORITE_URLS[index]}
    elif ((index >= ${#FAVORITE_NAMES[@]})); then
        index=$((index - ${#FAVORITE_NAMES[@]}))
        OPTIONS_STATION_LIST='Recientes'
        OPTIONS_STATION_NAME=${RECENT_NAMES[index]:-}
        OPTIONS_STATION_URL=${RECENT_URLS[index]:-}
    fi
}

options_action_reason() {
    OPTIONS_REASON=''
    case "$1" in
        pause|mute) ((OPTIONS_RUNNING)) || OPTIONS_REASON='Primero reproduce una emisora.' ;;
        record_toggle) ((OPTIONS_RUNNING || RECORDING_ACTIVE)) || OPTIONS_REASON='Primero reproduce una emisora.' ;;
        play_selected|favorite_toggle|comment) [[ -n "$OPTIONS_STATION_URL" ]] || OPTIONS_REASON='Selecciona una emisora en Favoritas o Recientes.' ;;
        select_favorites) ((${#FAVORITE_NAMES[@]})) || OPTIONS_REASON='Todavía no tienes favoritas. Entra en Buscar emisoras.' ;;
        select_recents) ((${#RECENT_NAMES[@]})) || OPTIONS_REASON='Todavía no has escuchado ninguna emisora.' ;;
        favorite_up|favorite_down)
            if [[ -z "$OPTIONS_STATION_URL" || "$OPTIONS_STATION_LIST" != Favoritas ]]; then
                OPTIONS_REASON='Selecciona una emisora en Favoritas.'
            elif [[ "$1" == favorite_up ]] && ((UI_SELECTED_INDEX == 0)); then
                OPTIONS_REASON='Esta favorita ya es la primera.'
            elif [[ "$1" == favorite_down ]] && ((UI_SELECTED_INDEX + 1 >= ${#FAVORITE_NAMES[@]})); then
                OPTIONS_REASON='Esta favorita ya es la última.'
            fi
            ;;
        alarm_cancel) ((ALARM_AT > 0)) || OPTIONS_REASON='No hay ninguna alarma programada.' ;;
        catalog_update) [[ -z "${CATALOG_PID:-}" ]] || OPTIONS_REASON='La actualización ya está en curso. Puedes seguir escuchando.' ;;
        volume_up) ((PLAYER_VOLUME < 100)) || OPTIONS_REASON='El volumen ya está al máximo.' ;;
        volume_down) ((PLAYER_VOLUME > 0)) || OPTIONS_REASON='El volumen ya está a cero.' ;;
    esac
}

options_add_row() {
    local key=$1 label=$2 detail=$3 action=$4 state=${5:-}
    options_action_reason "$action"
    # Los nombres y rutas son datos; nunca deben introducir filas ni campos.
    detail=${detail//[[:cntrl:]]/ }
    detail=${detail//|//}
    state=${state//[[:cntrl:]]/ }
    state=${state//|//}
    OPTIONS_ROWS+=("$key|$label|$detail|$action|$state|$OPTIONS_REASON")
}

options_build_rows() {
    local menu=${1:-main} pause='Pausar' mute='Silenciar' sound='Con sonido' selected
    local -a enabled=(Desactivado Activado)
    options_read_state
    ((PLAYER_PAUSED)) && pause='Reanudar'
    ((PLAYER_MUTED)) && { mute='Activar sonido'; sound='Silenciado'; }
    selected="Selección en $OPTIONS_STATION_LIST: ${OPTIONS_STATION_NAME:-ninguna}."
    OPTIONS_ROWS=()
    case "$menu" in
        main)
            OPTIONS_TITLE='OPCIONES'
            options_add_row P Reproducción 'Pausa, sonido, volumen y grabación de la emisora actual.' menu:playback "$OPTIONS_PLAYBACK"
            options_add_row E Emisoras 'Busca una emisora o gestiona la seleccionada: favoritas, recientes y comentarios.' menu:stations "$OPTIONS_CATALOG_STATE"
            options_add_row V Visualización 'Espectrograma, ecualizador, colores y símbolos. Las preferencias se guardan al cambiarlas.' menu:visual
            options_add_row T Temporizador 'La alarma suena una sola vez. Mantén Keila abierto y el equipo despierto; no se restaura al iniciar.' menu:timer "$OPTIONS_ALARM"
            options_add_row G Grabaciones 'Graba el audio o revisa los archivos guardados. El gestor permite comprobarlos, escucharlos y eliminarlos con confirmación.' menu:recordings "$OPTIONS_RECORDING"
            options_add_row S Sesión 'Consulta el registro de canciones de esta ejecución, con su hora y emisora.' menu:session
            options_add_row C Configuración 'Preferencias guardadas y teclas personalizables para la pantalla principal.' menu:config
            options_add_row D Diagnóstico 'Estado en vivo del reproductor, catálogo, grabaciones y rutas de datos.' status
            options_add_row H Ayuda 'Guía de uso y teclas vigentes. Dentro de Opciones las letras son locales y no dependen de los atajos personalizados.' help
            ;;
        playback)
            OPTIONS_TITLE='REPRODUCCIÓN'
            options_add_row I 'Reproducir selección' "$selected Vuelve al reproductor al iniciar la escucha." play_selected
            options_add_row P "$pause" 'Pausa o reanuda la escucha sin cerrar la emisora.' pause "$OPTIONS_PLAYBACK"
            options_add_row M "$mute" 'Cambia el sonido sin modificar el volumen ni interrumpir una grabación.' mute "$sound"
            options_add_row + 'Subir volumen' "Aumenta el volumen en $KEILA_VOLUME_STEP puntos. El nivel se guarda para el próximo inicio." volume_up "$PLAYER_VOLUME%"
            options_add_row - 'Bajar volumen' "Reduce el volumen en $KEILA_VOLUME_STEP puntos. El nivel se guarda para el próximo inicio." volume_down "$PLAYER_VOLUME%"
            options_add_row G "$OPTIONS_RECORD_LABEL" 'Graba el stream actual. Al detenerlo se espera al cierre del archivo antes de validarlo.' record_toggle "$OPTIONS_RECORDING"
            ;;
        stations)
            OPTIONS_TITLE='EMISORAS'
            options_add_row B 'Buscar emisoras' 'Abre la búsqueda. Escribe el nombre; Supr limpia la consulta y Enter reproduce. Esc vuelve al reproductor.' search
            options_add_row U 'Actualizar catálogo' 'Actualiza la copia local de Radio Browser en segundo plano. Conserva la copia anterior si falla la descarga.' catalog_update "$OPTIONS_CATALOG_STATE"
            options_add_row F 'Ir a Favoritas' 'Cierra Opciones y lleva el cursor a Favoritas.' select_favorites "${#FAVORITE_NAMES[@]} emisoras"
            options_add_row R 'Ir a Recientes' 'Cierra Opciones y lleva el cursor a Recientes.' select_recents "${#RECENT_NAMES[@]} emisoras"
            options_add_row I 'Reproducir selección' "$selected Vuelve al reproductor al iniciar la escucha." play_selected
            options_add_row X 'Añadir / quitar favorita' "$selected Añadir es inmediato; quitar requiere repetir Enter o X. Moverse cancela la confirmación." favorite_toggle
            options_add_row C 'Editar comentario' "$selected Enter guarda y Esc cancela en el editor." comment
            options_add_row K 'Subir favorita' "$selected Sube una posición y guarda el orden." favorite_up
            options_add_row J 'Bajar favorita' "$selected Baja una posición y guarda el orden." favorite_down
            ;;
        visual)
            OPTIONS_TITLE='VISUALIZACIÓN'
            options_add_row V Espectrograma 'Activa u oculta el análisis de audio. Requiere captura de audio disponible; se adapta al espacio de la terminal.' spectrum "${enabled[SPECTRUM_ENABLED]}"
            options_add_row Z Ecualizador 'Ajusta bandas con las flechas o elige un preset con 1-5. En pantallas pequeñas el panel principal permanece oculto.' equalizer
            local colors=${enabled[PREF_COLOR]} unicode=${enabled[PREF_UNICODE]}
            ((PREF_COLOR && !UI_COLOR)) && colors='Sin soporte'
            ((PREF_UNICODE && !UI_UNICODE)) && unicode='Modo ASCII'
            options_add_row C Colores 'Usa colores cuando la terminal lo permite. La selección también se reconoce por el cursor. Cambio persistente.' color "$colors"
            options_add_row U 'Símbolos Unicode' 'Desactiva los símbolos para usar flechas y bordes ASCII. Los textos conservan sus acentos. Cambio persistente.' unicode "$unicode"
            options_add_row A 'Preferencias y atajos' 'Abre la configuración completa. Reasigna teclas de la pantalla principal o restaura los ajustes con confirmación.' settings
            ;;
        timer)
            OPTIONS_TITLE='TEMPORIZADOR'
            options_add_row A 'Alarma temporal' 'Escribe HHMM: los dos puntos se añaden solos. Enter guarda; vacío cancela. Sonará la última emisora. Keila debe seguir abierto y el equipo despierto.' alarm "$OPTIONS_ALARM"
            options_add_row X 'Cancelar alarma' 'Desactiva la alarma de esta sesión. Las alarmas nunca se guardan para el siguiente inicio.' alarm_cancel "$OPTIONS_ALARM"
            ;;
        recordings)
            OPTIONS_TITLE='GRABACIONES'
            options_add_row G "$OPTIONS_RECORD_LABEL" "Graba la emisora actual. Archivo: ${RECORDING_FILE:-todavía no iniciado}. El cierre se verifica antes de dar la grabación por finalizada." record_toggle "$OPTIONS_RECORDING"
            local files="${#PENDING_FILES[@]} archivos"
            [[ -z "$PENDING_SCAN_PID" ]] || files='Buscando archivos'
            options_add_row R 'Revisar grabaciones' 'Lista los archivos con fecha y tamaño. Permite comprobar, escuchar y finalizar los verificados. Eliminar requiere confirmación y usa una papelera recuperable.' pending "$files"
            ;;
        session)
            OPTIONS_TITLE='SESIÓN'
            options_add_row S 'Historial de canciones' "Hora, emisora y título recibidos en esta ejecución. Archivo: ${SESSION_LOG_FILE:-el registro aún no se ha iniciado}." session_history
            options_add_row D 'Diagnóstico en vivo' 'Consulta estado del audio, catálogo y rutas de datos sin interrumpir la reproducción.' status
            ;;
        config)
            OPTIONS_TITLE='CONFIGURACIÓN'
            options_add_row C 'Preferencias y atajos' 'Ajustes guardados automáticamente. Las teclas de búsqueda y editores son locales; reasignar una tecla ocupada intercambia ambas acciones.' settings
            options_add_row I 'Inicio automático' 'Al abrir Keila, reproduce la última emisora que llegó a sonar. No restaura alarmas. Cambio persistente.' autoplay "${enabled[PREF_AUTOPLAY]}"
            options_add_row D Diagnóstico 'Consulta dónde se guardan configuración, favoritas, comentarios, sesiones y grabaciones.' status
            options_add_row H 'Ayuda completa' 'Teclas personalizadas vigentes y controles de cada pantalla.' help
            ;;
        *) return 1 ;;
    esac
}

options_parse_row() {
    IFS='|' read -r OPTIONS_ROW_KEY OPTIONS_ROW_LABEL OPTIONS_ROW_DETAIL OPTIONS_ROW_ACTION OPTIONS_ROW_STATE OPTIONS_ROW_REASON <<< "$1"
}

options_clamp_selection() {
    local count=${#OPTIONS_ROWS[@]} max_scroll
    ((OPTIONS_SELECTED < 0)) && OPTIONS_SELECTED=0
    ((OPTIONS_SELECTED >= count)) && OPTIONS_SELECTED=$((count > 0 ? count - 1 : 0))
    max_scroll=$((count - OPTIONS_VISIBLE))
    ((max_scroll < 0)) && max_scroll=0
    ((OPTIONS_SCROLL > max_scroll)) && OPTIONS_SCROLL=$max_scroll
    ((OPTIONS_SELECTED < OPTIONS_SCROLL)) && OPTIONS_SCROLL=$OPTIONS_SELECTED
    ((OPTIONS_SELECTED >= OPTIONS_SCROLL + OPTIONS_VISIBLE)) && OPTIONS_SCROLL=$((OPTIONS_SELECTED - OPTIONS_VISIBLE + 1))
    ((OPTIONS_SCROLL < 0)) && OPTIONS_SCROLL=0
    return 0
}

# Anchura en celdas para nombres internacionales. Camino rápido para latín;
# las marcas combinantes no ocupan celdas y CJK/emoji se reservan como anchos.
# Se sobreestima alguna secuencia emoji unida, evitando desbordar el terminal.
options_fit_text() {
    local text=${1//[[:cntrl:]]/ } max=$2 ellipsis=${3:-1} char code cells i prefix='' prefix_width=0
    local latin_pattern='^[ -~À-ÿ]*$'
    OPTIONS_FITTED='' OPTIONS_FITTED_WIDTH=0
    ((max > 0)) || return 0
    if [[ "$text" =~ $latin_pattern ]]; then
        if ((ellipsis)); then ui_truncate "$text" "$max" state; OPTIONS_FITTED=$UI_TRUNCATED_TEXT
        else OPTIONS_FITTED=${text:0:max}; fi
        OPTIONS_FITTED_WIDTH=${#OPTIONS_FITTED}
        return 0
    fi
    for ((i=0; i<${#text}; i++)); do
        char=${text:i:1}
        printf -v code '%d' "'$char"
        cells=1
        if (( (code >= 0x300 && code <= 0x36f) || (code >= 0x1ab0 && code <= 0x1aff) ||
              (code >= 0x1dc0 && code <= 0x1dff) || (code >= 0x20d0 && code <= 0x20ff && code != 0x20e3) ||
              (code >= 0xfe00 && code <= 0xfe0f) || (code >= 0xfe20 && code <= 0xfe2f) ||
              code == 0x200b || code == 0x200c || code == 0x200d )); then
            cells=0
        elif (( (code >= 0x1100 && code <= 0x115f) || (code >= 0x2300 && code <= 0x23ff) ||
                (code >= 0x2600 && code <= 0x27bf) || (code >= 0x2b00 && code <= 0x2bff) ||
                (code >= 0x2e80 && code <= 0xa4cf) || (code >= 0xac00 && code <= 0xd7a3) ||
                (code >= 0xf900 && code <= 0xfaff) || (code >= 0xfe10 && code <= 0xfe6f) ||
                (code >= 0xff00 && code <= 0xff60) || (code >= 0xffe0 && code <= 0xffe6) ||
                (code >= 0x1f000 && code <= 0x1faff) || (code >= 0x20000 && code <= 0x3fffd) )); then
            cells=2
        fi
        if ((OPTIONS_FITTED_WIDTH + cells > max)); then
            if ((ellipsis && max > 3)); then OPTIONS_FITTED="$prefix..."; OPTIONS_FITTED_WIDTH=$((prefix_width + 3)); fi
            return 0
        fi
        OPTIONS_FITTED+=$char
        OPTIONS_FITTED_WIDTH=$((OPTIONS_FITTED_WIDTH + cells))
        if ((OPTIONS_FITTED_WIDTH <= max - 3)); then prefix=$OPTIONS_FITTED; prefix_width=$OPTIONS_FITTED_WIDTH; fi
    done
}

options_print() {
    local width=$1 text=${2:-} style=${3:-}
    options_fit_text "$text" "$width"
    ui_style_begin "$style"
    printf '%s' "$OPTIONS_FITTED"
    ui_style_end
    ui_repeat_char ' ' "$((width - OPTIONS_FITTED_WIDTH))"
}

# División por palabras para la explicación seleccionada, sin procesos hijos.
options_wrap_detail() {
    local text=$1 width=$2 limit=$3 line word
    OPTIONS_DETAIL_LINES=()
    text=${text//[[:cntrl:]]/ }
    while [[ -n "$text" ]] && ((${#OPTIONS_DETAIL_LINES[@]} < limit)); do
        options_fit_text "$text" "$width" 0
        line=$OPTIONS_FITTED
        # Si una única letra ancha no cabe, consumirla sin atascar el detalle.
        [[ -n "$line" ]] || line=${text:0:1}
        if ((${#text} > ${#line})) && [[ "$line" == *' '* ]]; then
            word=${line##* }
            [[ -z "$word" ]] || line=${line% *}
        fi
        [[ -n "$line" ]] || line=${text:0:width}
        text=${text:${#line}}
        text=${text#"${text%%[![:space:]]*}"}
        if ((${#OPTIONS_DETAIL_LINES[@]} + 1 == limit)) && [[ -n "$text" ]]; then
            options_fit_text "$line $text" "$width"
            line=$OPTIONS_FITTED
        fi
        OPTIONS_DETAIL_LINES+=("$line")
    done
}

options_draw_row() {
    local index=$1 width=$2 marker='  ' style='' badge='' badge_width=0
    if ((index >= ${#OPTIONS_ROWS[@]})); then options_print "$width" ''; return; fi
    options_parse_row "${OPTIONS_ROWS[index]}"
    if ((index == OPTIONS_SELECTED)); then marker='> '; style=selected; fi
    [[ -z "$OPTIONS_ROW_REASON" ]] || style=muted
    if ((width >= 46)); then
        badge=$OPTIONS_ROW_STATE
        [[ -z "$OPTIONS_ROW_REASON" ]] || badge='No disponible'
    fi
    if [[ "$OPTIONS_ROW_ACTION" == menu:* ]]; then badge="${badge:+$badge } >"; fi
    if [[ -n "$badge" ]]; then badge_width=$((${#badge} + 2)); fi
    if ((width < 9)); then
        options_print "$width" "$marker$OPTIONS_ROW_LABEL" "$style"
        return
    fi
    options_print 2 "$marker" "$style"
    local key_style=warning
    [[ -z "$OPTIONS_ROW_REASON" ]] || key_style=muted
    options_print 4 "[$OPTIONS_ROW_KEY] " "$key_style"
    options_print "$((width - 6 - badge_width))" "$OPTIONS_ROW_LABEL" "$style"
    if ((badge_width)); then options_print "$badge_width" "  $badge" muted; fi
}

options_draw() {
    ui_refresh_size
    local width=$((UI_COLS - 1)) lines=$UI_LINES split=0 body detail_count=0 list_width
    local row title="$OPTIONS_TITLE" summary footer detail state reason count=${#OPTIONS_ROWS[@]}
    ((width < 1)) && width=1
    ((lines < 1)) && lines=1
    # Una terminal reducida transitoriamente a pocas filas también tiene una
    # salida válida: no imprimir nunca más filas ni tocar la última columna.
    if ((lines < 6)); then
        OPTIONS_VISIBLE=1
        options_clamp_selection
        tput cup 0 0 2>/dev/null || true
        options_draw_row "$OPTIONS_SELECTED" "$width"
        for ((row=1; row<lines; row++)); do
            printf '\n'
            if ((row == lines - 1)); then options_print "$width" 'Esc volver'; else options_print "$width" ''; fi
        done
        tput ed 2>/dev/null || true
        return 0
    fi
    body=$((lines - 4))
    if ((width >= 96 && lines >= 16)); then
        split=1
        list_width=$((width * 48 / 100))
        ((list_width > 60)) && list_width=60
        OPTIONS_VISIBLE=$((body - 2))
    else
        list_width=$width
        if ((lines >= 12)); then detail_count=4
        elif ((lines >= 8)); then detail_count=2; fi
        OPTIONS_VISIBLE=$((body - detail_count - 1))
    fi
    ((OPTIONS_VISIBLE < 1)) && OPTIONS_VISIBLE=1
    options_clamp_selection
    options_parse_row "${OPTIONS_ROWS[OPTIONS_SELECTED]}"
    title=$OPTIONS_ROW_LABEL state=$OPTIONS_ROW_STATE reason=$OPTIONS_ROW_REASON
    detail=$OPTIONS_ROW_DETAIL
    [[ -z "$reason" ]] || detail="No disponible: $reason $detail"
    [[ -z "$state" ]] || detail="$state. $detail"
    local detail_width=$((split ? width - list_width - 3 : width))
    options_wrap_detail "$detail" "$detail_width" "$((split ? body - 3 : detail_count > 0 ? detail_count - 1 : 1))"

    tput cup 0 0 2>/dev/null || true
    local breadcrumb=OPCIONES
    [[ "$OPTIONS_TITLE" == OPCIONES ]] || breadcrumb="OPCIONES > $OPTIONS_TITLE"
    if ((width < 32)) && [[ "$OPTIONS_TITLE" != OPCIONES ]]; then breadcrumb="O > $OPTIONS_TITLE"; fi
    local position="$((OPTIONS_SELECTED + 1))/$count"
    ((width >= 70)) && position="KEILA  $position"
    ui_print_split_styled "$width" "$breadcrumb" "$position" title muted
    printf '\n'
    summary="$OPTIONS_PLAYBACK | Vol $PLAYER_VOLUME%"
    ((PLAYER_MUTED)) && summary+=' | Silencio'
    ((RECORDING_ACTIVE)) && summary+=" | $OPTIONS_RECORDING"
    if ((width >= 70)) && [[ -n "$PLAYER_NAME" ]]; then summary+=" | $PLAYER_NAME"; fi
    summary=${summary//[[:cntrl:]]/ }
    options_print "$width" "$summary" muted
    printf '\n'

    # El cuerpo y los pies tienen altura fija; al cambiar de opción no saltan.
    for ((row=0; row<body; row++)); do
        if ((row == 0)); then
            ui_style_begin muted; ui_repeat_char "$UI_H" "$width"; ui_style_end
        elif ((split)); then
            if ((row <= OPTIONS_VISIBLE)); then options_draw_row "$((OPTIONS_SCROLL + row - 1))" "$list_width"
            else options_print "$list_width" ''; fi
            options_print 3 " $UI_V " muted
            if ((row == 1)); then options_print "$detail_width" "$title" selected
            else options_print "$detail_width" "${OPTIONS_DETAIL_LINES[row-2]:-}"; fi
        elif ((row <= OPTIONS_VISIBLE)); then
            options_draw_row "$((OPTIONS_SCROLL + row - 1))" "$width"
        elif ((row == OPTIONS_VISIBLE + 1)); then
            options_print "$width" "$title" selected
        else
            options_print "$width" "${OPTIONS_DETAIL_LINES[row-OPTIONS_VISIBLE-2]:-}"
        fi
        printf '\n'
    done
    footer='Flechas mover | Enter abrir | Esc volver'
    if ((UI_UNICODE)); then footer='↑↓ mover · →/Enter abrir · ←/Esc volver'; fi
    if ((width >= 64)); then footer+=' | PgUp/PgDn | ? detalle'
    elif ((width < 38)); then
        if ((UI_UNICODE)); then footer='↑↓ mover  Enter abrir  Esc volver'
        else footer='Enter abrir | Esc volver'; fi
    fi
    if ((${#footer} > width)); then footer='Enter abrir | Esc volver'; fi
    if ((${#footer} > width)); then footer='Enter | Esc volver'; fi
    options_print "$width" "$footer" muted
    printf '\n'
    local notice=${UI_MESSAGE:-}
    [[ -n "$notice" ]] || notice='? detalle | Letras: acceso directo'
    notice=${notice//[[:cntrl:]]/ }
    options_print "$width" "$notice" warning
    tput ed 2>/dev/null || true
}

# El detalle completo también es accesible en una pantalla diminuta. Es una
# vista de lectura: Enter/derecha aquí nunca ejecutan la acción explicada.
options_detail_draw() {
    ui_refresh_size
    local width=$((UI_COLS - 1)) row text
    ((width < 1)) && width=1
    if ((UI_LINES < 6)); then options_draw; return; fi
    OPTIONS_DETAIL_VISIBLE=$((UI_LINES - 4))
    options_parse_row "${OPTIONS_ROWS[OPTIONS_SELECTED]}"
    text=$OPTIONS_ROW_DETAIL
    [[ -z "$OPTIONS_ROW_REASON" ]] || text="No disponible: $OPTIONS_ROW_REASON $text"
    [[ -z "$OPTIONS_ROW_STATE" ]] || text="$OPTIONS_ROW_STATE. $text"
    [[ -z "${UI_MESSAGE:-}" ]] || text+=" Aviso: $UI_MESSAGE"
    options_wrap_detail "$text" "$width" 200
    local max_scroll=$((${#OPTIONS_DETAIL_LINES[@]} - OPTIONS_DETAIL_VISIBLE))
    ((max_scroll < 0)) && max_scroll=0
    ((OPTIONS_DETAIL_SCROLL > max_scroll)) && OPTIONS_DETAIL_SCROLL=$max_scroll
    ((OPTIONS_DETAIL_SCROLL < 0)) && OPTIONS_DETAIL_SCROLL=0
    tput cup 0 0 2>/dev/null || true
    options_print "$width" 'OPCIONES > DETALLE' title; printf '\n'
    options_print "$width" "$OPTIONS_ROW_LABEL" selected; printf '\n'
    for ((row=0; row<OPTIONS_DETAIL_VISIBLE; row++)); do
        options_print "$width" "${OPTIONS_DETAIL_LINES[OPTIONS_DETAIL_SCROLL+row]:-}"
        printf '\n'
    done
    local footer='Flechas mover | Esc volver'
    if ((${#footer} > width)); then footer='Esc volver'; fi
    options_print "$width" "$footer"; printf '\n'
    options_print "$width" 'Solo lectura | ? cerrar'
    tput ed 2>/dev/null || true
}

options_execute() {
    local action=$1 status=0
    [[ "$action" == favorite_toggle ]] || options_cancel_confirmation
    case "$action" in
        menu:*) options_menu_loop "${action#menu:}" ;;
        play_selected) app_play_selected && OPTIONS_CLOSE_REQUESTED=1 ;;
        pause) app_toggle_pause || true ;;
        mute) app_toggle_mute || true ;;
        volume_up) app_change_volume "$KEILA_VOLUME_STEP" || true ;;
        volume_down) app_change_volume "$((-KEILA_VOLUME_STEP))" || true ;;
        record_toggle) app_toggle_recording || true ;;
        search) app_search_catalog || true; OPTIONS_CLOSE_REQUESTED=1 ;;
        catalog_update) app_update_catalog || true ;;
        select_favorites) ui_select_emisoras && OPTIONS_CLOSE_REQUESTED=1 ;;
        select_recents) ui_select_recientes && OPTIONS_CLOSE_REQUESTED=1 ;;
        favorite_toggle) options_toggle_selected_favorite || true ;;
        comment) app_edit_label || true ;;
        favorite_up) app_move_selected_favorite -1 || true ;;
        favorite_down) app_move_selected_favorite 1 || true ;;
        spectrum) app_toggle_spectrum || true ;;
        equalizer) app_edit_equalizer || true ;;
        color) options_toggle_preference PREF_COLOR Colores ;;
        unicode) options_toggle_preference PREF_UNICODE Unicode ;;
        autoplay) options_toggle_preference PREF_AUTOPLAY 'Inicio automático' ;;
        alarm) app_edit_alarm || true ;;
        alarm_cancel) alarm_set '' || true ;;
        pending) app_pending_menu || true ;;
        session_history) app_session_history_screen || status=$? ;;
        settings) app_preferences_menu settings || true ;;
        status) app_status_screen || status=$? ;;
        help) app_preferences_menu help || true ;;
    esac
    if ((status == 2)); then OPTIONS_RESULT=2; OPTIONS_CLOSE_REQUESTED=1; fi
    PREFERENCES_ACTIVE=1
    OPTIONS_ACTIVE=1
}

options_open_selected() {
    options_read_state
    options_clamp_selection
    options_parse_row "${OPTIONS_ROWS[OPTIONS_SELECTED]}"
    options_action_reason "$OPTIONS_ROW_ACTION"
    if [[ -n "$OPTIONS_REASON" ]]; then
        options_cancel_confirmation
        app_message "$OPTIONS_REASON" 5
        return 0
    fi
    options_execute "$OPTIONS_ROW_ACTION"
}

options_key_select() {
    local wanted=${1,,} i
    [[ -n "$wanted" ]] || return 1
    for ((i=0; i<${#OPTIONS_ROWS[@]}; i++)); do
        options_parse_row "${OPTIONS_ROWS[i]}"
        if [[ "$wanted" == "${OPTIONS_ROW_KEY,,}" ]]; then OPTIONS_SELECTED=$i; return 0; fi
    done
    return 1
}

# Solo valores que afectan a Opciones: un cuadro del espectro o un segundo de
# grabación no obliga a reconstruir y redibujar este menú.
options_snapshot() {
    printf -v OPTIONS_SNAPSHOT '%s\034' "$PLAYER_PID" "$PLAYER_PAUSED" "$PLAYER_MUTED" "$PLAYER_VOLUME" \
        "$PLAYER_BUFFERING" "$PLAYER_STREAM_READY" "$PLAYER_NAME" "$RECORDING_ACTIVE" "$RECORDING_PHASE" \
        "$ALARM_AT" "$ALARM_LABEL" "$CATALOG_PID" "$CATALOG_LAST_ERROR" "$PENDING_SCAN_PID" \
        "${#PENDING_FILES[@]}" "$SPECTRUM_ENABLED" "${UI_MESSAGE:-}" "$UI_SELECTED_INDEX" \
        "${#FAVORITE_NAMES[@]}" "${#RECENT_NAMES[@]}" "${APP_RECONNECT_NEXT_AT:-0}"
}

options_menu_loop() {
    local menu=${1:-main} event key redraw=1 previous_snapshot max_index previous_selected repeat
    local detail_active=0 OPTIONS_DETAIL_SCROLL=0 OPTIONS_DETAIL_VISIBLE=1
    OPTIONS_SELECTED=${OPTIONS_SELECTIONS[$menu]:-0}
    OPTIONS_SCROLL=${OPTIONS_OFFSETS[$menu]:-0}
    while ((!OPTIONS_CLOSE_REQUESTED)); do
        if ((redraw)); then
            options_catalog_refresh
            options_build_rows "$menu" || break
            if ((detail_active)); then options_detail_draw; else options_draw; fi
        fi
        options_snapshot
        previous_snapshot=$OPTIONS_SNAPSHOT
        if ! input_read; then OPTIONS_CLOSE_REQUESTED=1; break; fi
        event=$INPUT_EVENT key=$INPUT_KEY redraw=1
        max_index=$((${#OPTIONS_ROWS[@]} - 1))
        previous_selected=$OPTIONS_SELECTED
        repeat=${INPUT_REPEAT_COUNT:-1}
        [[ "$repeat" =~ ^[1-8]$ ]] || repeat=1
        if ((detail_active)) && [[ "$event" != TICK && "$event" != RESIZE ]]; then
            case "$event" in
                ESC|LEFT) detail_active=0 ;;
                UP) OPTIONS_DETAIL_SCROLL=$((OPTIONS_DETAIL_SCROLL - repeat)) ;;
                DOWN) OPTIONS_DETAIL_SCROLL=$((OPTIONS_DETAIL_SCROLL + repeat)) ;;
                PAGE_UP) OPTIONS_DETAIL_SCROLL=$((OPTIONS_DETAIL_SCROLL - OPTIONS_DETAIL_VISIBLE)) ;;
                PAGE_DOWN) OPTIONS_DETAIL_SCROLL=$((OPTIONS_DETAIL_SCROLL + OPTIONS_DETAIL_VISIBLE)) ;;
                HOME) OPTIONS_DETAIL_SCROLL=0 ;;
                END) OPTIONS_DETAIL_SCROLL=${#OPTIONS_DETAIL_LINES[@]} ;;
                KEY) [[ "$key" != '?' ]] || detail_active=0 ;;
            esac
            continue
        fi
        case "$event" in
            TICK)
                app_poll_player || true
                catalog_poll || true
                ui_message_tick || true
                pending_scan_poll || true
                options_snapshot
                redraw=0
                if [[ "$OPTIONS_SNAPSHOT" != "$previous_snapshot" ]] || ((EPOCHSECONDS >= OPTIONS_CATALOG_CHECK_AT)); then redraw=1; fi
                ;;
            RESIZE) ;;
            ESC|LEFT) options_cancel_confirmation; break ;;
            UP) OPTIONS_SELECTED=$((OPTIONS_SELECTED - repeat)); options_cancel_confirmation ;;
            DOWN) OPTIONS_SELECTED=$((OPTIONS_SELECTED + repeat)); options_cancel_confirmation ;;
            HOME) OPTIONS_SELECTED=0; options_cancel_confirmation ;;
            END) OPTIONS_SELECTED=$max_index; options_cancel_confirmation ;;
            PAGE_UP) OPTIONS_SELECTED=$((OPTIONS_SELECTED - OPTIONS_VISIBLE)); options_cancel_confirmation ;;
            PAGE_DOWN) OPTIONS_SELECTED=$((OPTIONS_SELECTED + OPTIONS_VISIBLE)); options_cancel_confirmation ;;
            ENTER|RIGHT)
                options_parse_row "${OPTIONS_ROWS[OPTIONS_SELECTED]}"
                # Derecha expande categorías; no altera ajustes ni confirma un
                # borrado cuando el usuario solo intenta explorar el árbol.
                if [[ "$event" == ENTER || "$OPTIONS_ROW_ACTION" == menu:* ]]; then
                    OPTIONS_SELECTIONS[$menu]=$OPTIONS_SELECTED OPTIONS_OFFSETS[$menu]=$OPTIONS_SCROLL
                    options_open_selected
                    OPTIONS_SELECTED=${OPTIONS_SELECTIONS[$menu]} OPTIONS_SCROLL=${OPTIONS_OFFSETS[$menu]}
                else
                    options_cancel_confirmation
                fi
                ;;
            KEY)
                if [[ "$key" == '?' ]]; then
                    options_cancel_confirmation
                    detail_active=1 OPTIONS_DETAIL_SCROLL=0
                elif options_key_select "$key"; then
                    ((OPTIONS_SELECTED == previous_selected)) || options_cancel_confirmation
                    OPTIONS_SELECTIONS[$menu]=$OPTIONS_SELECTED OPTIONS_OFFSETS[$menu]=$OPTIONS_SCROLL
                    options_open_selected
                    OPTIONS_SELECTED=${OPTIONS_SELECTIONS[$menu]} OPTIONS_SCROLL=${OPTIONS_OFFSETS[$menu]}
                else
                    options_cancel_confirmation
                    redraw=0
                fi
                ;;
            *) redraw=0 ;;
        esac
        # El hijo comparte las filas globales; el siguiente frame reconstruye
        # las del padre antes de usarlas, conservando su posición por separado.
    done
    OPTIONS_SELECTIONS[$menu]=$OPTIONS_SELECTED OPTIONS_OFFSETS[$menu]=$OPTIONS_SCROLL
    return 0
}

app_options_menu() {
    local previous_preferences=$PREFERENCES_ACTIVE
    OPTIONS_ACTIVE=1 OPTIONS_CLOSE_REQUESTED=0 OPTIONS_RESULT=0
    OPTIONS_CATALOG_CHECK_AT=0
    PREFERENCES_ACTIVE=1
    options_cancel_confirmation
    options_menu_loop main
    options_cancel_confirmation
    PREFERENCES_ACTIVE=$previous_preferences
    OPTIONS_ACTIVE=0
    ((OPTIONS_RESULT == 2)) || ui_draw
    return "$OPTIONS_RESULT"
}
