#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck source=lib/record-schedule.sh
source "$(dirname "${BASH_SOURCE[0]}")/record-schedule.sh"

record_plan_form_draw() {
    local name=$1 url=$2 hour=$3 minutes=$4 selected=$5 offset=$6 notice=$7
    PANEL_ROWS=()
    panel_add_row E 'Emisora favorita' "Emisora: ${name:-sin elegir}. URL: $url. La programación conserva esta selección aunque después cambien tus favoritas." "${name:-Elegir}"
    panel_add_row H 'Hora de inicio' 'Escribe HHMM; los dos puntos se añaden solos. Si esa hora ya pasó, se propondrá mañana. La fecha exacta se revisa antes de confirmar.' "${hour:-HH:MM}"
    panel_add_row D 'Duración en minutos' 'De 1 a 1440. El final se calcula desde la hora prevista, no desde cuando llegue el audio.' "$minutes min"
    panel_add_row G 'Revisar programación' 'Todavía no guarda: muestra emisora, fecha, inicio y final. Solo una programación por sesión. Puede cambiar la radio actual; no restaura la emisora anterior. Mantén Keila abierto y el equipo despierto.' 'Confirmación'
    panel_draw 'PROGRAMAR GRABACIÓN' "$selected" "$offset" 'Enter editar | G revisar | Esc volver' "$notice"
}

record_plan_field_edit() {
    local kind=$1 text=$2 title detail redraw=1
    if [[ "$kind" == hour ]]; then
        title='HORA DE GRABACIÓN'; detail='Introduce cuatro cifras HHMM. Los dos puntos son automáticos. Enter acepta el campo, todavía sin programar. Esc conserva el valor anterior.'
    else title='DURACIÓN DE GRABACIÓN'; detail='De 1 a 1440 minutos. Enter acepta el campo; Esc conserva el anterior.'; fi
    while true; do
        ((redraw)) && station_field_draw "$title" "$text" "$detail"
        input_read || return 1
        redraw=1
        case "$INPUT_EVENT" in
            ESC) return 1 ;;
            ENTER) RECORD_PLAN_FIELD=$text; return 0 ;;
            RESIZE) ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            DELETE) text='' ;;
            KEY)
                case "$INPUT_KEY" in
                    $'\x7f'|$'\x08') [[ "$text" != *: ]] || text=${text%:}; text=${text%?} ;;
                    $'\x15') text='' ;;
                    [0-9])
                        if [[ "$kind" == hour ]]; then
                            if ((${#text} < 5)); then text+=$INPUT_KEY; ((${#text} != 2)) || text+=':'; fi
                        elif ((${#text} < 4)); then text+=$INPUT_KEY; fi ;;
                    :) [[ "$kind" != hour || ${#text} != 2 ]] || text+=':' ;;
                esac ;;
        esac
    done
}

app_record_plan_station() {
    local selected=0 offset=0 redraw=1 i
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    local -a names=("${FAVORITE_NAMES[@]}") urls=("${FAVORITE_URLS[@]}") PANEL_ROWS=()
    ((${#names[@]} > 0)) || { app_message 'Primero añade alguna emisora a Favoritas.' 6; return 1; }
    for i in "${!names[@]}"; do panel_add_row '' "${names[i]}" "URL: ${urls[i]}. Enter elige esta emisora sin reproducirla."; done
    while true; do
        if ((redraw)); then
            panel_draw 'EMISORA PARA GRABAR' "$selected" "$offset" 'Enter elegir | Esc volver' ''
            selected=$PANEL_SELECTED offset=$PANEL_SCROLL
        fi
        input_read || return 1
        redraw=1
        case "$INPUT_EVENT" in
            ESC|LEFT) return 1 ;;
            ENTER)
                ((UI_COLS >= 20 && UI_LINES >= 6)) || continue
                RECORD_PLAN_PICK_NAME=${names[selected]} RECORD_PLAN_PICK_URL=${urls[selected]}; return 0 ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$INPUT_EVENT" "$selected" "${#names[@]}" "$PANEL_VISIBLE"; selected=$PANEL_SELECTED ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            RESIZE) ;;
            KEY) [[ "$INPUT_KEY" != '?' ]] || panel_detail 'EMISORA PARA GRABAR' "$selected" ;;
        esac
    done
}

record_plan_confirm_draw() {
    local title=$1 detail=$2 notice=${3:-}
    local -a PANEL_ROWS=()
    panel_add_row G Confirmar "$detail" 'Revisar antes'
    panel_draw "$title" 0 0 'Enter confirmar | ? detalle | Esc volver' "$notice"
}

app_record_plan_confirm() {
    local action=$1 name=${2:-} url=${3:-} at=${4:-0} end=${5:-0} label=${6:-}
    # FILE pertenece al motor cargado arriba; FIELD es solo la entrada del editor.
    # shellcheck disable=SC2153
    local redraw=1 notice='' detail token="$RECORD_PLAN_STATE|$RECORD_PLAN_AT|$RECORD_PLAN_FILE|$RECORD_PLAN_PID"
    if [[ "$action" == arm ]]; then
        detail="Emisora: $name. URL: $url. $label. Carpeta: ${RECORDINGS_DIR:-sin configurar}. Sustituye la programación pendiente anterior. Usa la radio actual y respeta volumen/silencio, pero puede cambiar la emisora. No restaura la anterior. Si ya grabas, escuchas un archivo o restauras datos al inicio, se omite. La parada automática puede interrumpirla. Keila debe seguir abierto y el equipo despierto. Solo esta sesión."
    else
        record_plan_status
        detail="$RECORD_PLAN_DETAIL. Confirma cancelar esta programación; si su grabación está activa, se cerrará de forma segura, sin borrar el archivo ni detener otra grabación."
    fi
    while true; do
        ((redraw)) && record_plan_confirm_draw 'CONFIRMAR PROGRAMACIÓN' "$detail" "$notice"
        input_read || return 1
        redraw=1
        case "$INPUT_EVENT" in
            ESC|LEFT) return 1 ;;
            RESIZE) ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            ENTER|KEY)
                if [[ "$INPUT_EVENT" == KEY && "$INPUT_KEY" == '?' ]]; then
                    local -a PANEL_ROWS=()
                    panel_add_row G Confirmar "$detail"
                    panel_detail 'CONFIRMAR PROGRAMACIÓN' 0
                    continue
                fi
                [[ "$INPUT_EVENT" == ENTER || "${INPUT_KEY,,}" == g ]] || continue
                if ((UI_COLS < 20 || UI_LINES < 6)); then notice='Amplía la terminal antes de confirmar.'; continue; fi
                if [[ "$action" == arm ]]; then
                    if record_plan_arm "$name" "$url" "$at" "$end"; then return 0; fi
                    notice=$RECORD_PLAN_ERROR
                else
                    if [[ "$token" != "$RECORD_PLAN_STATE|$RECORD_PLAN_AT|$RECORD_PLAN_FILE|$RECORD_PLAN_PID" ]]; then
                        app_message 'El estado cambió. Vuelve a revisar antes de cancelar o detener.' 8; return 1
                    fi
                    record_plan_cancel; return 0
                fi ;;
        esac
    done
}

app_edit_record_plan() {
    local name='' url='' hour='' minutes=30 selected=0 offset=0 redraw=1 notice='' key
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    local -a PANEL_ROWS=()
    if [[ "$RECORD_PLAN_STATE" == pending ]]; then
        name=$RECORD_PLAN_NAME url=$RECORD_PLAN_URL
        hour=$(date -d "@$RECORD_PLAN_AT" +%H:%M)
        minutes=$(((RECORD_PLAN_END-RECORD_PLAN_AT)/60))
    fi
    while true; do
        if ((redraw)); then
            record_plan_form_draw "$name" "$url" "$hour" "$minutes" "$selected" "$offset" "$notice"
            selected=$PANEL_SELECTED offset=$PANEL_SCROLL
        fi
        input_read || return 1
        redraw=1
        case "$INPUT_EVENT" in
            ESC|LEFT) return 1 ;;
            RESIZE) ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$INPUT_EVENT" "$selected" 4 "$PANEL_VISIBLE"; selected=$PANEL_SELECTED ;;
            ENTER|KEY)
                key=${INPUT_KEY,,}
                if [[ "$INPUT_EVENT" == ENTER ]]; then
                    case "$selected" in 0) key=e ;; 1) key=h ;; 2) key=d ;; 3) key=g ;; esac
                fi
                case "$key" in
                    e) if app_record_plan_station; then name=$RECORD_PLAN_PICK_NAME url=$RECORD_PLAN_PICK_URL; fi ;;
                    h) if record_plan_field_edit hour "$hour"; then hour=$RECORD_PLAN_FIELD; fi ;;
                    d) if record_plan_field_edit minutes "$minutes"; then minutes=$RECORD_PLAN_FIELD; fi ;;
                    g)
                        if record_plan_prepare "$name" "$url" "$hour" "$minutes"; then
                            if app_record_plan_confirm arm "$name" "$url" "$RECORD_PLAN_DRAFT_AT" "$RECORD_PLAN_DRAFT_END" "$RECORD_PLAN_DRAFT_LABEL"; then return 0; fi
                        else notice=$RECORD_PLAN_ERROR; fi ;;
                    '?') panel_detail 'PROGRAMAR GRABACIÓN' "$selected" ;;
                esac ;;
        esac
    done
}

app_record_plan_info() {
    local -a PANEL_ROWS=()
    record_plan_status
    panel_add_row '' "$RECORD_PLAN_STATUS" "$RECORD_PLAN_DETAIL. Estado al abrir; vuelve al menú para actualizarlo."
    panel_detail 'GRABACIÓN PROGRAMADA' 0
}
