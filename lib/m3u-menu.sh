#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck source=lib/m3u.sh
source "$(dirname "${BASH_SOURCE[0]}")/m3u.sh"
M3U_JOB_PID='' M3U_JOB_DIR=''

m3u_cleanup() {
    if [[ -n "$M3U_JOB_PID" ]]; then
        player_terminate_group_bounded "$M3U_JOB_PID" "$M3U_JOB_PID" || true
        wait "$M3U_JOB_PID" 2>/dev/null || true
    fi
    M3U_JOB_PID=''
    [[ -z "$M3U_JOB_DIR" ]] || rm -rf -- "$M3U_JOB_DIR"
    M3U_JOB_DIR=''
}

m3u_draw() {
    local mode=$1 path=$2 selected=$3 offset=$4 notice=$5 title label row name url badge
    local footer='G confirmar | Enter detalle | Esc cancelar'
    ((selected != 0)) || footer='Enter/G confirmar | Esc cancelar'
    PANEL_ROWS=()
    if [[ "$mode" == import ]]; then title='IMPORTAR M3U'; label='Confirmar importación'
    else title='EXPORTAR M3U'; label='Confirmar exportación'; fi
    panel_add_row G "$label" "Archivo: $path. $M3U_SUMMARY. Importar añade solo URL nuevas sin cambiar nombres existentes ni comentarios. Exportar no sobrescribe archivos; solo nombres y URL, que pueden contener tokens privados. Esc cancela sin guardar."
    for row in "${M3U_ROWS[@]}"; do
        name=${row%%|*} url=${row#*|} badge='Emisora'
        if [[ "$mode" == import ]]; then
            badge='Nueva'
            [[ -z "${M3U_EXISTING[$url]:-}" ]] || badge='Ya favorita'
        fi
        panel_add_row '' "$name" "URL completa: $url. Solo lectura; no se reproduce ni se descarga al importar." "$badge"
    done
    panel_draw "$title" "$selected" "$offset" "$footer" "$notice" "$M3U_SUMMARY"
}

app_m3u_dialog() {
    local mode=$1 path="$HOME/Keila-favoritas.m3u" source directory pid status=1 prepared=0
    local redraw=1 notice='' selected=0 offset=0 count=0 duplicates=0 rejected=0 existing=0 row url
    local selected_url=${OPTIONS_STATION_URL:-} previous_preferences=${PREFERENCES_ACTIVE:-0}
    local M3U_SUMMARY='' PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    local -a M3U_ROWS=() PANEL_ROWS=()
    local -A M3U_EXISTING=()
    [[ "$mode" == import || "$mode" == export ]] || return 1
    if [[ "$mode" == export ]]; then path="$HOME/Keila-favoritas-$(date +%Y%m%d-%H%M%S).m3u"; fi
    PREFERENCES_ACTIVE=1
    if ! station_field_edit 'ARCHIVO M3U' "$path" 'Ruta local absoluta, relativa a la carpeta actual o ~/…; no se expanden variables ni comandos. Después verás una vista previa, todavía sin guardar. Máximo 256 KiB y 2000 emisoras.' 2048; then
        PREFERENCES_ACTIVE=$previous_preferences; return 1
    fi
    path=$STATION_FIELD_RESULT
    if [[ "$path" == \~/* ]]; then path="$HOME/${path:2}"; fi
    if [[ -z "$path" || "$path" == *[[:cntrl:]]* ]]; then
        app_message 'Ruta vacía o no válida.' 6; PREFERENCES_ACTIVE=$previous_preferences; return 1
    fi
    [[ "$path" == /* ]] || path="$PWD/$path"
    directory=$(mktemp -d "${TMPDIR:-/tmp}/keila-m3u.XXXXXX") || { PREFERENCES_ACTIVE=$previous_preferences; return 1; }
    M3U_JOB_DIR=$directory
    source=$path
    [[ "$mode" != export ]] || source=$KEILA_FAVORITES_FILE
    setsid -- bash "$BASE_DIR/lib/m3u.sh" "$mode" "$source" "$directory" </dev/null >/dev/null 2>&1 &
    pid=$!
    M3U_JOB_PID=$pid
    local deadline=$((EPOCHSECONDS+15))
    while true; do
        if ((prepared == 0)) && [[ -f "$directory/status" ]]; then
            wait "$pid" 2>/dev/null || true; pid='' M3U_JOB_PID=''
            IFS= read -r status < "$directory/status" || status=1
            if [[ "$status" != 0 ]]; then
                IFS= read -r notice < "$directory/notice" || notice='No se pudo leer la lista.'
                app_message "$notice" 9; status=1; break
            fi
            read -r count duplicates rejected < "$directory/counts"
            mapfile -t M3U_ROWS < "$directory/rows"
            for url in "${FAVORITE_URLS[@]}"; do M3U_EXISTING[$url]=1; done
            for row in "${M3U_ROWS[@]}"; do
                url=${row#*|}
                [[ -z "${M3U_EXISTING[$url]:-}" ]] || ((existing+=1))
            done
            M3U_SUMMARY="$count emisoras · $duplicates duplicadas · $rejected omitidas por formato/URL"
            [[ "$mode" != import ]] || M3U_SUMMARY+=" · $existing ya favoritas"
            prepared=1 redraw=1 status=1
        fi
        if ((prepared == 0 && EPOCHSECONDS >= deadline)); then
            app_message 'La lectura no terminó a tiempo. Ningún dato se ha importado ni exportado.' 8; break
        fi
        if ((redraw)); then
            if ((prepared)); then
                m3u_draw "$mode" "$path" "$selected" "$offset" "$notice"
                selected=$PANEL_SELECTED offset=$PANEL_SCROLL
            else
                PANEL_ROWS=()
                panel_add_row '' 'Preparando vista previa…' "Archivo: $path. Puedes cancelar con Esc. La radio y los temporizadores siguen funcionando."
                panel_draw 'INTERCAMBIAR FAVORITAS' 0 0 'Esc cancelar' ''
            fi
        fi
        input_read || break
        redraw=1
        case "$INPUT_EVENT" in
            ESC|LEFT) break ;;
            RESIZE) ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$INPUT_EVENT" "$selected" "$((${#M3U_ROWS[@]}+1))" "$PANEL_VISIBLE"; selected=$PANEL_SELECTED ;;
            ENTER|KEY)
                ((prepared)) || continue
                if [[ "$INPUT_EVENT" == KEY && "$INPUT_KEY" == '?' ]] || [[ "$INPUT_EVENT" == ENTER && $selected != 0 ]]; then
                    panel_detail 'VISTA PREVIA M3U' "$selected"; continue
                fi
                if [[ "$INPUT_EVENT" == ENTER || "${INPUT_KEY,,}" == g ]]; then
                    if ((UI_COLS < 20 || UI_LINES < 6)); then notice='Amplía la terminal antes de confirmar.'; continue; fi
                    if [[ "$mode" == import ]]; then
                        if m3u_import_commit "$directory/rows"; then
                            ui_navigation_refresh
                            [[ -z "$selected_url" ]] || ui_select_url "$selected_url" || true
                            app_message "Importadas $M3U_ADDED emisoras; $M3U_DUPLICATES ya favoritas. Comentarios conservados." 9
                            status=0; break
                        fi
                    elif m3u_export_commit "$directory/rows" "$path"; then
                        app_message "M3U exportado: $path" 10; status=0; break
                    fi
                    notice=$M3U_ERROR
                fi ;;
        esac
    done
    m3u_cleanup
    PREFERENCES_ACTIVE=$previous_preferences
    ((previous_preferences)) || ui_draw
    return "$status"
}
