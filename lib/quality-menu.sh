#!/usr/bin/env bash
# shellcheck disable=SC2153
# SPDX-License-Identifier: GPL-3.0-or-later
# Estado del trabajo compartido con quality.sh, cargado por el launcher.
QUALITY_ROWS=() QUALITY_RESULT_NOTICE=''

quality_read_result() {
    local file=$1 origin=$2 size row url rate codec bits kind extra
    local -a rows=()
    [[ -f $file && ! -L $file ]] || return 1
    size=$(stat -c %s -- "$file") || return 1
    ((size > 0 && size <= 262144)) || return 1
    jq -e '.version==1 and (.rows|type=="array" and length>0 and length<=100) and (.notice|type=="string") and
        all(.rows[]; (.url|type=="string" and length<=2048 and (test("[|\u0000-\u0020\u007f]")|not)) and (.rate|type=="number" and .>=0 and .<=2000000 and floor==.) and
            (.codec|type=="string" and length<=160) and (.bits|type=="number" and .>=0 and .<=2000000 and floor==.) and
            (.kind=="original" or .kind=="catalog" or .kind=="hls"))' "$file" >/dev/null || return 1
    while IFS= read -r row; do
        IFS='|' read -r url rate codec bits kind extra <<< "$row"
        data_quality_url_valid "$url" || return 1
        [[ -z $extra && $rate =~ ^(0|[1-9][0-9]{0,6})$ && $bits =~ ^(0|[1-9][0-9]{0,6})$ && $codec != *[[:cntrl:]]* ]] || return 1
        [[ $rate == 0 ]] || ((rate >= 8000)) || return 1
        rows+=("$row")
    done < <(jq -r '.rows[] | [.url,.rate,(.codec|gsub("[|\u0000-\u001f\u007f]";" ")),.bits,.kind] | map(tostring) | join("|")' "$file")
    [[ ${rows[0]:-} == "$origin|0|"* && ${rows[0]##*|} == original ]] || return 1
    QUALITY_ROWS=("${rows[@]}")
    QUALITY_RESULT_NOTICE=$(jq -r '.notice | gsub("[\u0000-\u001f\u007f]";" ") | .[0:1000]' "$file")
}

quality_poll_job() {
    [[ -n $QUALITY_JOB_PID ]] || return 1
    local changed=1 status=0
    if ((QUALITY_JOB_CATALOG_READ == 0)) && [[ -f $QUALITY_JOB_DIR/catalog.json ]]; then
        if quality_read_result "$QUALITY_JOB_DIR/catalog.json" "$1"; then QUALITY_JOB_CATALOG_READ=1; changed=0; fi
    fi
    kill -0 "$QUALITY_JOB_PID" 2>/dev/null && return "$changed"
    wait "$QUALITY_JOB_PID" 2>/dev/null || status=$?
    QUALITY_JOB_PID=''
    if ((status == 0)) && quality_read_result "$QUALITY_JOB_DIR/result.json" "$1"; then :
    else QUALITY_RESULT_NOTICE+=' La comprobación no terminó; se conserva la información disponible.'; fi
    quality_cleanup
    return 0
}

quality_menu_rows() {
    local origin=$1 input=$2 current_rate=$3 row url rate codec bits kind title detail badge amount i found=0
    local saved=${QUALITY_TARGETS[$origin]:-} saved_rate=${QUALITY_RATES[$origin]:-0}
    PANEL_ROWS=()
    QUALITY_MENU_CHOICES=("${QUALITY_ROWS[@]}")
    if [[ -n $saved ]]; then
        for row in "${QUALITY_ROWS[@]}"; do [[ $row == "$saved|$saved_rate|"* ]] && found=1; done
        ((found)) || QUALITY_MENU_CHOICES+=("$saved|$saved_rate||0|saved")
    fi
    for i in "${!QUALITY_MENU_CHOICES[@]}"; do
        row=${QUALITY_MENU_CHOICES[i]}
        IFS='|' read -r url rate codec bits kind <<< "$row"
        title=${codec:-'Formato no especificado'} badge=''
        case $kind in original) title='Original'; [[ -z $codec ]] || title+=" · $codec" ;; saved) title='Guardada'; ((rate == 0)) || bits=$rate ;; esac
        if ((bits > 0)); then
            title+=" · $((bits/1000)) kb/s"
            amount=$((bits*45/10000))
            printf -v amount '%d.%d' "$((amount/10))" "$((amount%10))"
            title+=" · ~$amount MB/h"
        fi
        detail="Formato: ${codec:-no especificado}."
        if ((bits > 0)); then detail+=" Bitrate: $((bits/1000)) kb/s. Consumo aproximado: $amount MB/h."
        else detail+=' Bitrate y consumo no especificados.'; fi
        detail+=" URL: $url. Bitrate declarado, no medida universal de calidad ni prueba de conexión. El consumo no incluye cabeceras, segmentos ni reintentos."
        if [[ $kind == hls ]]; then detail+=' Variante de audio de la lista HLS; guarda el master y el límite de bitrate, no una dirección hija temporal.'
        elif [[ $kind == catalog ]]; then detail+=' Alternativa del catálogo con mismo nombre, país, zona y web; verifica que conserva la programación.'; fi
        [[ $kind != original ]] || detail+=' Vuelve al stream original y a la selección predeterminada de mpv; elimina solo la preferencia de calidad de esta emisora.'
        if [[ $url == "$input" && $rate == "$current_rate" ]]; then
            badge='Actual'
            # El renderer común omite badges en terminales estrechas.
            ((UI_COLS >= 48)) || title="Actual · $title"
        fi
        [[ -z $QUALITY_RESULT_NOTICE ]] || detail+=" $QUALITY_RESULT_NOTICE"
        panel_add_row '' "$title" "$detail Enter comprueba el audio antes de guardar; si falla recupera la versión anterior. En pausa espera a que reanudes. Puede haber un breve corte; se conservan volumen, silencio y pausa." "$badge"
    done
}

# La consulta larga queda en ?. La ausencia de filas no demuestra que la radio
# no tenga otras emisiones; solo describe lo encontrado por esta comprobación.
quality_menu_notice() {
    if [[ -n $QUALITY_JOB_PID ]]; then QUALITY_MENU_NOTICE='Consultando versiones… · U reiniciar'
    elif ((${#QUALITY_ROWS[@]} == 1)); then QUALITY_MENU_NOTICE='Sin alternativas detectadas · U reintentar'
    else QUALITY_MENU_NOTICE='Bitrate declarado; más no siempre significa mejor calidad.'; fi
}

# Ventana local de tamaño fijo: navegar repinta solo su rectángulo. El fondo se
# restaura una vez al abrir, redimensionar o volver del detalle, no por cada tecla.
# Termux y pantallas pequeñas conservan el panel común a pantalla completa.
quality_draw() {
    local selected=$1 offset=$2 notice=$3 name=$4 geometry width=72 height=12 top left inner row index
    # El bucle modal ya toma el tamaño al abrir y con WINCH. No lanzar dos
    # tput por pulsación en la ventana; la llamada aislada sí puede medirlo.
    ((${5:-0})) || ui_refresh_size
    if ((UI_COLS < 96 || UI_LINES < 16)) || deps_is_termux; then
        QUALITY_OVERLAY_GEOMETRY=''
        panel_draw 'CALIDAD / VERSIONES' "$selected" "$offset" 'Enter elegir | ? detalle | U actualizar | Esc volver' "$notice" "$name · sin cambio automático"
        return
    fi
    geometry="$UI_COLS/$UI_LINES"
    if [[ ${QUALITY_OVERLAY_GEOMETRY:-} != "$geometry" ]]; then
        if ((${UI_ACTIVE:-0})); then
            if ((previous_preferences)); then options_draw
            elif ((${SEARCH_ACTIVE:-0})); then search_draw_view
            else ui_draw; fi
        fi
        logo_hide
        QUALITY_OVERLAY_GEOMETRY=$geometry
    fi
    top=$(((UI_LINES-height)/2+1)) left=$(((UI_COLS-width)/2+1)) inner=$((width-2))
    local OPTIONS_SELECTED=$selected OPTIONS_SCROLL=$offset OPTIONS_VISIBLE=5 OPTIONS_BADGE_MAX_WIDTH=7
    local -a OPTIONS_ROWS=("${PANEL_ROWS[@]}")
    options_clamp_selection
    for ((row=0; row<height; row++)); do
        printf '\033[%d;%dH' "$((top+row))" "$left"
        case $row in
            0) printf '%s' "$UI_TL"; ui_repeat_char "$UI_H" "$inner"; printf '%s' "$UI_TR" ;;
            11) printf '%s' "$UI_BL"; ui_repeat_char "$UI_H" "$inner"; printf '%s' "$UI_BR" ;;
            *)
                printf '%s' "$UI_V"
                case $row in
                    1) options_print "$inner" " CALIDAD / VERSIONES · $((OPTIONS_SELECTED+1))/${#OPTIONS_ROWS[@]}" title ;;
                    2) options_print "$inner" " $name" accent ;;
                    [3-7]) index=$((OPTIONS_SCROLL+row-3)); options_draw_row "$index" "$inner" ;;
                    8) options_print "$inner" " $notice" warning ;;
                    9) options_print "$inner" ' Flechas seleccionan; la emisión no cambia hasta pulsar Enter.' muted ;;
                    10) options_print "$inner" ' Enter elegir · ? detalle · U actualizar · Esc volver' muted ;;
                esac
                printf '%s' "$UI_V" ;;
        esac
    done
    PANEL_SELECTED=$OPTIONS_SELECTED PANEL_SCROLL=$OPTIONS_SCROLL PANEL_VISIBLE=$OPTIONS_VISIBLE
}

app_quality_menu() {
    local origin=${PLAYER_URL:-} pid=${PLAYER_PID:-} name=${PLAYER_NAME:-} previous_preferences=$PREFERENCES_ACTIVE
    local selected=0 offset=0 redraw=1 notice='' selected_key='' row i status=1 key_url key_rate unused
    local QUALITY_OVERLAY_GEOMETRY='' QUALITY_MENU_NOTICE=''
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    local -a PANEL_ROWS=() QUALITY_MENU_CHOICES=()
    if ! player_is_running || ! data_quality_url_valid "$origin"; then app_message 'Primero reproduce una emisora HTTP/HTTPS.' 5; return 1; fi
    if ((QUALITY_CHECK_ACTIVE)); then app_message 'Ya hay una calidad pendiente de comprobar; reanuda si está en pausa.' 7; return 1; fi
    if ((RECORDING_ACTIVE)) || record_plan_busy || [[ -n ${PENDING_PREVIEW_PID:-} ]]; then app_message 'No se cambia calidad durante una grabación o escucha de archivo.' 6; return 1; fi
    quality_load || { app_message 'No se pudieron leer las preferencias de calidad.' 6; return 1; }
    ui_refresh_size
    PREFERENCES_ACTIVE=1
    QUALITY_ROWS=("$origin|0||0|original") QUALITY_RESULT_NOTICE='Consultando catálogo y variantes de audio…'
    quality_start_job "$origin" "${PLAYER_INPUT_URL:-$origin}" "$name" || QUALITY_RESULT_NOTICE='No se pudo iniciar la consulta; puedes conservar la emisión original.'
    quality_menu_rows "$origin" "${PLAYER_INPUT_URL:-$origin}" "${PLAYER_HLS_RATE:-0}"
    for i in "${!QUALITY_MENU_CHOICES[@]}"; do
        [[ ${QUALITY_MENU_CHOICES[i]} == "${PLAYER_INPUT_URL:-$origin}|${PLAYER_HLS_RATE:-0}|"* ]] && { selected=$i; break; }
    done
    while true; do
        if [[ $PLAYER_URL != "$origin" || $PLAYER_PID != "$pid" ]] || ! player_is_running; then
            app_message 'La reproducción cambió; se cierra el selector sin aplicar nada.' 6; break
        fi
        if ((redraw)); then
            quality_menu_rows "$origin" "${PLAYER_INPUT_URL:-$origin}" "${PLAYER_HLS_RATE:-0}"
            quality_menu_notice
            quality_draw "$selected" "$offset" "${notice:-$QUALITY_MENU_NOTICE}" "$name" 1
            selected=$PANEL_SELECTED offset=$PANEL_SCROLL
        fi
        input_read || break
        redraw=1
        case $INPUT_EVENT in
            ESC|LEFT) break ;;
            RESIZE) ui_refresh_size ;;
            TICK)
                redraw=0; panel_poll && redraw=1
                if [[ -n $QUALITY_JOB_PID ]]; then
                    row=${QUALITY_MENU_CHOICES[selected]:-}
                    IFS='|' read -r key_url key_rate unused <<< "$row"
                    selected_key="$key_url|$key_rate"
                    if quality_poll_job "$origin"; then
                        quality_menu_rows "$origin" "${PLAYER_INPUT_URL:-$origin}" "${PLAYER_HLS_RATE:-0}"
                        selected=0
                        for i in "${!QUALITY_MENU_CHOICES[@]}"; do [[ ${QUALITY_MENU_CHOICES[i]} == "$selected_key|"* ]] && { selected=$i; break; }; done
                        redraw=1
                    fi
                fi ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                notice=''
                panel_move "$INPUT_EVENT" "$selected" "${#QUALITY_MENU_CHOICES[@]}" "$PANEL_VISIBLE"; selected=$PANEL_SELECTED ;;
            ENTER)
                if ((UI_COLS < 20 || UI_LINES < 6)); then notice='Amplía la terminal antes de elegir.'; continue; fi
                local target rate
                IFS='|' read -r target rate unused <<< "${QUALITY_MENU_CHOICES[selected]}"
                if quality_apply_choice "$origin" "$pid" "$target" "$rate"; then status=0; fi
                app_message "$QUALITY_NOTICE" 9
                break ;;
            KEY)
                case ${INPUT_KEY,,} in
                    '?') panel_detail 'CALIDAD / VERSIONES' "$selected"; QUALITY_OVERLAY_GEOMETRY='' ;;
                    u) notice=''; QUALITY_RESULT_NOTICE='Actualizando catálogo y variantes…'; quality_start_job "$origin" "${PLAYER_INPUT_URL:-$origin}" "$name" || QUALITY_RESULT_NOTICE='No se pudo iniciar la consulta; se conserva la información disponible.' ;;
                esac ;;
        esac
    done
    quality_cleanup
    PREFERENCES_ACTIVE=$previous_preferences
    return "$status"
}
