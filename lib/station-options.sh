#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Pantallas locales de Opciones. No añade atajos al reproductor ni al buscador.

station_field_draw() {
    local title=$1 text=$2 detail=$3 notice=${4:-} preview=$2 visible
    local PANEL_FORM=1 PANEL_FULL_WIDTH=1
    local -a PANEL_ROWS=()
    ui_refresh_size
    visible=$((UI_COLS-7))
    ((UI_COLS < 47)) || visible=$((visible-(UI_COLS-1)/3-2))
    ((visible > 0)) || visible=1
    # Una URL puede medir 2048 caracteres. Acotar antes de medir celdas evita
    # volver a recorrer su prefijo entero por cada carácter del editor.
    ((${#preview} <= visible)) || preview=${preview: -visible}
    options_fit_text "${preview}_" "$visible"
    while [[ "$OPTIONS_FITTED" != "${preview}_" && -n "$preview" ]]; do
        preview=${preview:1}; options_fit_text "${preview}_" "$visible"
    done
    panel_add_row '' "${preview}_" "$detail Valor completo: $text" 'Editar'
    panel_draw "$title" 0 0 'Enter aceptar | Supr vaciar | Esc cancelar' "$notice"
}

station_field_edit() {
    local title=$1 text=$2 detail=$3 max=$4 redraw=1
    while true; do
        ((redraw)) && station_field_draw "$title" "$text" "$detail"
        input_read || return 1
        redraw=1
        case "$INPUT_EVENT" in
            ESC) return 1 ;;
            ENTER) STATION_FIELD_RESULT=$text; return 0 ;;
            DELETE) text='' ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            RESIZE) ;;
            KEY)
                case "$INPUT_KEY" in
                    $'\x7f'|$'\x08') text=${text%?} ;;
                    *) [[ "$INPUT_KEY" != [[:print:]] || ${#text} -ge max ]] || text+=$INPUT_KEY ;;
                esac ;;
        esac
    done
}

station_picker_rows() {
    local file=$1 query=$2 row value label
    STATION_PICK_VALUES=('')
    PANEL_ROWS=()
    panel_add_row '' 'Sin este filtro' 'Quita solo este filtro. Cambiar el país también quita la región anterior.'
    while IFS= read -r row; do
        IFS=$'\t' read -r value label <<< "$row"
        [[ -n "$value" ]] || continue
        STATION_PICK_VALUES+=("$value")
        panel_add_row '' "$label" "Valor del catálogo: $label. Enter lo aplica; Esc conserva el filtro anterior."
    done < <(KEILA_PICK_QUERY="${query,,}" awk -F '\t' 'BEGIN { q=ENVIRON["KEILA_PICK_QUERY"] } index(tolower($0),q) || q == "" { print; if (++n >= 300) exit }' "$file")
    if [[ -n "$query" ]] && ((${#STATION_PICK_VALUES[@]} == 1)); then
        PANEL_ROWS=()
        panel_add_row '' 'Sin coincidencias' 'Acorta el texto o pulsa Supr para ver todos los valores. Esc conserva el filtro actual.' '' 'No hay valores que elegir.'
    fi
}

station_picker_prepare() {
    local kind=$1 file=$2
    STATION_PICK_NOTICE=''
    if ! search_filter_choices "$kind" > "$file"; then
        STATION_PICK_NOTICE='No hay catálogo local disponible. Actualízalo desde Opciones > Emisoras.'
    elif [[ "$kind" != country ]] && ! stations_tsv_has_facets; then
        STATION_PICK_NOTICE='Índice antiguo: espera su preparación o actualiza el catálogo desde Emisoras.'
    elif [[ ! -s "$file" ]]; then
        STATION_PICK_NOTICE='No hay valores declarados para esta selección. Prueba a quitar país o región.'
    fi
}

app_station_filter_picker() {
    local kind=$1 title directory query='' selected=0 offset=0 redraw=1 dirty=1 status=1 notice='' previous_job selected_value i
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    local -a PANEL_ROWS=() STATION_PICK_VALUES=()
    case "$kind" in country) title='ELEGIR PAÍS' ;; region) title='ELEGIR REGIÓN' ;; tag) title='ELEGIR TEMÁTICA' ;; *) return 1 ;; esac
    directory=$(mktemp -d "${TMPDIR:-/tmp}/keila-filters.XXXXXX") || return 1
    station_picker_prepare "$kind" "$directory/choices"
    notice=$STATION_PICK_NOTICE previous_job=${CATALOG_PID:-}
    while true; do
        if ((dirty)); then
            station_picker_rows "$directory/choices" "$query"
            if [[ -n "$query" ]] && ((${#STATION_PICK_VALUES[@]} > 1)); then selected=1; fi
            dirty=0
        fi
        if ((redraw)); then
            panel_draw "$title" "$selected" "$offset" 'Escribe para filtrar | Enter elegir | Esc volver' "$notice" "Buscar: ${query}_ | Hasta 300 valores; afina el texto"
            selected=$PANEL_SELECTED offset=$PANEL_SCROLL
        fi
        input_read || break
        redraw=1
        case "$INPUT_EVENT" in
            ESC|LEFT) break ;;
            ENTER)
                if ((UI_COLS < 20 || UI_LINES < 6)); then notice='Amplía la terminal antes de elegir.'; continue; fi
                if [[ -n "$query" ]] && ((${#STATION_PICK_VALUES[@]} == 1)); then notice='Sin coincidencias. Acorta el texto o pulsa Supr.'; continue; fi
                search_filters_set "$kind" "${STATION_PICK_VALUES[selected]}"
                search_filters_summary
                app_message "$SEARCH_FILTER_SUMMARY. Consulta conservada." 5
                status=0; break ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$INPUT_EVENT" "$selected" "${#PANEL_ROWS[@]}" "$PANEL_VISIBLE"; selected=$PANEL_SELECTED ;;
            DELETE) query='' selected=0 offset=0 dirty=1 ;;
            TICK)
                redraw=0; panel_poll && redraw=1
                if [[ -n "$previous_job" && -z "${CATALOG_PID:-}" ]]; then
                    selected_value=${STATION_PICK_VALUES[selected]:-}
                    station_picker_prepare "$kind" "$directory/choices"
                    station_picker_rows "$directory/choices" "$query"
                    notice=$STATION_PICK_NOTICE selected=0
                    for i in "${!STATION_PICK_VALUES[@]}"; do
                        [[ "${STATION_PICK_VALUES[i]}" != "$selected_value" ]] || { selected=$i; break; }
                    done
                    redraw=1
                fi
                previous_job=${CATALOG_PID:-} ;;
            RESIZE) ;;
            KEY)
                case "$INPUT_KEY" in
                    '?') panel_detail "$title" "$selected" ;;
                    $'\x7f'|$'\x08') query=${query%?}; dirty=1 ;;
                    *) if [[ "$INPUT_KEY" == [[:print:]] ]] && ((${#query} < 80)); then query+=$INPUT_KEY; dirty=1; fi ;;
                esac
                ((dirty == 0)) || { selected=0; offset=0; } ;;
        esac
    done
    rm -rf -- "$directory"
    return "$status"
}

station_manual_valid() {
    local name=$1 url=$2 authority host
    STATION_MANUAL_ERROR=''
    if [[ -z "$name" || "$name" != *[![:space:]]* || "$name" == *[[:cntrl:]\|]* ]] || ((${#name} > 160)); then
        STATION_MANUAL_ERROR='Escribe un nombre de 1 a 160 caracteres, sin controles ni |.'; return 1
    fi
    if [[ ! "$url" =~ ^https?://[^/\?#]+ || "$url" == *[[:space:][:cntrl:]\|\\]* ]] || ((${#url} > 2048)); then
        STATION_MANUAL_ERROR='Usa una URL de audio HTTP/HTTPS, sin espacios, barras inversas ni |.'; return 1
    fi
    authority=${url#*://}; authority=${authority%%[/?#]*}
    host='^([a-zA-Z0-9][a-zA-Z0-9._-]*|\[[0-9a-fA-F:]+\])(:[0-9]{1,5})?$'
    if [[ ! "$authority" =~ $host ]]; then
        STATION_MANUAL_ERROR='La dirección necesita un servidor válido y no admite usuario ni contraseña.'; return 1
    fi
}

station_manual_save() {
    local name=$1 url=$2 status=0
    station_manual_valid "$name" "$url" || return 1
    favorites_add "$name" "$url" || status=$?
    case "$status" in
        0) ui_navigation_refresh; STATION_MANUAL_ERROR='Guardada en Favoritas. No se ha publicado en Radio Browser.' ;;
        2) STATION_MANUAL_ERROR='Esta dirección ya está en Favoritas. No se ha duplicado ni cambiado su nombre.' ;;
        *) STATION_MANUAL_ERROR='No se pudo guardar. Se conservan las favoritas anteriores.' ;;
    esac
    return "$status"
}

station_manual_rows() {
    local name=$1 url=$2 reason='' playing=''
    PANEL_ROWS=()
    panel_add_row N Nombre 'Nombre con el que aparecerá en Favoritas. Editarlo aquí no modifica emisoras existentes.' "${name:-Sin rellenar}"
    panel_add_row D 'Dirección del audio' 'URL HTTP/HTTPS del stream o lista compatible, no la página web de la radio. No admite credenciales en el servidor.' "${url:-Sin rellenar}"
    ((${RECORDING_ACTIVE:-0} == 0)) || reason='Detén la grabación antes de probar otra emisora.'
    if [[ -n "$url" && "${PLAYER_URL:-}" == "$url" && -n "${PLAYER_PID:-}" ]]; then
        playing='Conectando'; ((${PLAYER_STREAM_READY:-0} == 0)) || playing='Audio disponible'
    fi
    panel_add_row P 'Probar: reproducir ahora' 'Cambia la emisora que suena usando el reproductor habitual. No guarda en Favoritas; sí puede aparecer en Recientes y en el registro de sesión. Esc vuelve sin deshacer la reproducción.' "$playing" "$reason"
    panel_add_row G 'Guardar en Favoritas' 'Guarda nombre y URL como datos personales, con las protecciones y copias existentes. No requiere conexión ni reproduce automáticamente. No publica en Radio Browser.'
}

app_station_manual() {
    local name='' url='' selected=0 offset=0 redraw=1 notice='' action status tested_url=''
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    local -a PANEL_ROWS=()
    while true; do
        if ((redraw)); then
            if [[ -n "$tested_url" && "$tested_url" == "$url" ]]; then notice=${UI_MESSAGE:-'Prueba en el reproductor. Todavía no está guardada en Favoritas.'}; fi
            station_manual_rows "$name" "$url"
            panel_draw 'AÑADIR EMISORA MANUAL' "$selected" "$offset" 'Enter abrir | ? detalle | Esc volver' "$notice"
            selected=$PANEL_SELECTED offset=$PANEL_SCROLL
        fi
        input_read || break
        redraw=1 action=''
        case "$INPUT_EVENT" in
            ESC|LEFT) break ;;
            ENTER) action=${selected} ;;
            KEY) case "${INPUT_KEY,,}" in n) action=0 ;; d) action=1 ;; p) action=2 ;; g) action=3 ;; '?') panel_detail 'AÑADIR EMISORA MANUAL' "$selected" ;; esac ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            RESIZE) ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$INPUT_EVENT" "$selected" 4 "$PANEL_VISIBLE"; selected=$PANEL_SELECTED ;;
        esac
        [[ -n "$action" ]] || continue
        selected=$action
        case "$action" in
            0) if station_field_edit 'NOMBRE DE LA EMISORA' "$name" 'Nombre personal. Retroceso borra; Supr vacía; Esc cancela la edición.' 160; then name=$(config_trim "$STATION_FIELD_RESULT"); notice='' tested_url=''; fi ;;
            1) if station_field_edit 'DIRECCIÓN DEL AUDIO' "$url" 'URL completa del audio. Retroceso borra; Supr vacía; Esc cancela la edición.' 2048; then url=$(config_trim "$STATION_FIELD_RESULT"); notice='' tested_url=''; fi ;;
            2|3)
                if ((UI_COLS < 20 || UI_LINES < 6)); then notice='Amplía la terminal antes de continuar.'; continue; fi
                if ! station_manual_valid "$name" "$url"; then notice=$STATION_MANUAL_ERROR; continue; fi
                if [[ "$action" == 2 ]]; then
                    if ((${RECORDING_ACTIVE:-0})); then notice='Detén la grabación antes de probar.'; continue; fi
                    app_play "$name" "$url" || true
                    tested_url=$url
                    notice="${UI_MESSAGE:-Reproducción solicitada. No se guarda en Favoritas.}"
                else
                    status=0; station_manual_save "$name" "$url" || status=$?
                    tested_url=''
                    notice=$STATION_MANUAL_ERROR
                    if ((status == 0)); then app_message "$notice" 6; break; fi
                fi ;;
        esac
    done
    return 0
}
