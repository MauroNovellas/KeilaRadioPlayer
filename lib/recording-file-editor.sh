#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Formularios del gestor: los archivos solo cambian tras confirmar el destino.
recording_name_draw() {
    local file=$1 text=$2 notice=${3:-} preview=$2 visible
    local PANEL_FORM=1 PANEL_FULL_WIDTH=1
    local -a PANEL_ROWS=()
    ui_refresh_size
    visible=$((UI_COLS-7))
    ((UI_COLS < 47)) || visible=$((visible-(UI_COLS-1)/3-2))
    ((visible > 0)) || visible=1
    options_fit_text "${preview}_" "$visible"
    while [[ "$OPTIONS_FITTED" != "${preview}_" && -n "$preview" ]]; do
        preview=${preview:1}; options_fit_text "${preview}_" "$visible"
    done
    panel_add_row '' "${preview}_" "Nombre completo: $text.${file##*.}. La extensión .${file##*.} se conserva automáticamente. Escribe solo el nombre, sin rutas. Retroceso borra; Supr vacía. Enter revisa el cambio y Esc cancela." 'Nuevo nombre'
    panel_draw 'RENOMBRAR GRABACIÓN' 0 0 'Enter revisar | Esc cancelar' "$notice" "Actual: ${file##*/}"
}

recording_move_confirm_rows() {
    local file=$1 target=$2
    PANEL_ROWS=()
    panel_add_row '' "Origen: ${file##*/}" "Archivo original: $file. El audio y su estado de cierre se conservan."
    panel_add_row '' "Destino: ${target##*/}" "Destino completo: $target. Nunca se sustituye un archivo existente. Enter confirma este destino exacto; Esc cancela."
}

recording_move_confirm_draw() {
    local title=$1 file=$2 target=$3 selected=$4 notice=$5
    local -a PANEL_ROWS=()
    recording_move_confirm_rows "$file" "$target"
    panel_draw "$title" "$selected" 0 'Enter confirma | ? detalle | Esc cancela' "$notice" 'Revisa origen y destino antes de confirmar'
}

recording_move_confirm() {
    local kind=$1 file=$2 target=$3 signature=$4 stem=${5:-} selected=0 redraw=1 notice='' title status
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    if [[ "$kind" == rename ]]; then title='CONFIRMAR NUEVO NOMBRE'; else title='RECUPERAR GRABACIÓN'; fi
    while true; do
        if ((redraw)); then recording_move_confirm_draw "$title" "$file" "$target" "$selected" "$notice"; selected=$PANEL_SELECTED; fi
        input_read || return 2
        redraw=1
        case "$INPUT_EVENT" in
            ESC|LEFT) return 2 ;;
            RESIZE) ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$INPUT_EVENT" "$selected" 2 "$PANEL_VISIBLE"; selected=$PANEL_SELECTED ;;
            KEY)
                if [[ "$INPUT_KEY" == '?' ]]; then
                    local -a PANEL_ROWS=()
                    recording_move_confirm_rows "$file" "$target"
                    panel_detail "$title" "$selected"
                fi ;;
            ENTER)
                if ((UI_COLS < 20 || UI_LINES < 6)); then notice='Amplía la terminal antes de confirmar.'; continue; fi
                status=0
                if [[ "$kind" == rename ]]; then recording_rename "$file" "$stem" "$signature" || status=1
                else recording_restore "$file" "$target" "$signature" || status=1; fi
                PENDING_NOTICE=$RECORDING_FILES_NOTICE
                pending_scan_start || true
                return "$status" ;;
        esac
    done
}

app_recording_rename() {
    local file=$1 signature text name=${1##*/} notice='' redraw=1 status target
    recording_files_available "$file" || { PENDING_NOTICE='No se puede renombrar: archivo ocupado o no disponible.'; return 1; }
    signature=$(pending_signature "$file") || return 1
    text=${name%.*}
    while true; do
        ((redraw)) && recording_name_draw "$file" "$text" "$notice"
        input_read || return 1
        redraw=1
        case "$INPUT_EVENT" in
            ESC) PENDING_NOTICE='Cambio de nombre cancelado.'; return 0 ;;
            RESIZE) ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            ENTER)
                if ! recording_name_valid "$text.${name##*.}" || [[ -z "$text" || "$text" != *[![:space:]]* ]]; then
                    notice='Nombre vacío, demasiado largo o no válido. No uses rutas.'; continue
                fi
                target="$RECORDINGS_DIR/$text.${name##*.}"
                if [[ "$target" == "$file" ]]; then notice='El nombre no ha cambiado.'; continue; fi
                status=0
                recording_move_confirm rename "$file" "$target" "$signature" "$text" || status=$?
                # Esc en la confirmación vuelve al editor, conservando el texto.
                if ((status == 2)); then notice='Confirmación cancelada; puedes editar o salir con Esc.'
                else return "$status"; fi ;;
            DELETE) text='' notice='' ;;
            KEY)
                case "$INPUT_KEY" in
                    $'\x7f'|$'\x08') text=${text%?} ;;
                    *) [[ "$INPUT_KEY" != [[:print:]] || ${#text} -ge 240 ]] || text+=$INPUT_KEY ;;
                esac ;;
        esac
    done
}

app_recording_restore() {
    local file=$1 signature
    recording_files_available "$file" || { PENDING_NOTICE='No se puede recuperar: archivo ocupado o no disponible.'; return 1; }
    signature=$(pending_signature "$file") || return 1
    if ! recording_restore_destination "$file"; then PENDING_NOTICE='No se pudo preparar un destino seguro.'; return 1; fi
    local status=0
    recording_move_confirm restore "$file" "$RECORDING_RESTORE_TARGET" "$signature" || status=$?
    ((status != 2)) || PENDING_NOTICE='Recuperación cancelada. El archivo sigue en la papelera.'
    return "$status"
}
