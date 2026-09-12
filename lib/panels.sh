#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Presentación común de las pantallas hijas. Reutiliza el render de Opciones;
# cada pantalla conserva sus filas, selección y acciones mediante variables
# locales de Bash, sin modificar el menú del que procede.

PANEL_PARENT_PATH=''
PANEL_VISIBLE=1
PANEL_SELECTED=0
PANEL_SCROLL=0
declare -a PANEL_ROWS=()

panel_add_row() {
    local key=$1 label=$2 detail=$3 state=${4:-} reason=${5:-}
    label=${label//[[:cntrl:]]/ } label=${label//|//}
    detail=${detail//[[:cntrl:]]/ } detail=${detail//|//}
    state=${state//[[:cntrl:]]/ } state=${state//|//}
    PANEL_ROWS+=("$key|$label|$detail|panel|$state|$reason")
}

panel_path() {
    PANEL_PATH=$1
    [[ -z "${PANEL_PARENT_PATH:-}" ]] || PANEL_PATH="$PANEL_PARENT_PATH > $1"
}

panel_call() {
    local title=$1
    shift
    panel_path "$title"
    local PANEL_PARENT_PATH=$PANEL_PATH
    "$@"
}

panel_summary() {
    PANEL_SUMMARY='Detenido'
    if [[ -n "${PLAYER_PID:-}" ]]; then
        PANEL_SUMMARY='Reproduciendo'
        if ((${PLAYER_PAUSED:-0})); then PANEL_SUMMARY='En pausa'
        elif ((${PLAYER_BUFFERING:-0})); then PANEL_SUMMARY='Esperando audio'
        elif ((!${PLAYER_STREAM_READY:-0})); then PANEL_SUMMARY='Conectando'; fi
    fi
    PANEL_SUMMARY+=" | Vol ${PLAYER_VOLUME:-0}%"
    ((${PLAYER_MUTED:-0})) && PANEL_SUMMARY+=' | Silencio'
    ((${RECORDING_ACTIVE:-0})) && PANEL_SUMMARY+=' | Grabación activa'
    return 0
}

panel_draw() {
    local title=$1 selected=$2 offset=$3 footer=$4 notice=${5:-} subtitle=${6:-}
    local OPTIONS_TITLE=$title OPTIONS_SELECTED=$selected OPTIONS_SCROLL=$offset OPTIONS_VISIBLE=1
    local OPTIONS_BREADCRUMB OPTIONS_FOOTER_OVERRIDE=$footer OPTIONS_NOTICE_OVERRIDE=$notice OPTIONS_SUMMARY_OVERRIDE
    local OPTIONS_FORM=${PANEL_FORM:-0} OPTIONS_DETAIL_HEADING=''
    ((OPTIONS_FORM == 0)) || OPTIONS_DETAIL_HEADING='Ayuda de edición'
    local -a OPTIONS_ROWS=("${PANEL_ROWS[@]}") OPTIONS_DETAIL_LINES=()
    if ((${#OPTIONS_ROWS[@]} == 0)); then OPTIONS_ROWS=('|Sin elementos|No hay elementos para mostrar.|panel||'); fi
    panel_path "$title"
    OPTIONS_BREADCRUMB=$PANEL_PATH
    panel_summary
    OPTIONS_SUMMARY_OVERRIDE=${subtitle:-$PANEL_SUMMARY}
    options_draw
    PANEL_SELECTED=$OPTIONS_SELECTED PANEL_SCROLL=$OPTIONS_SCROLL PANEL_VISIBLE=$OPTIONS_VISIBLE
}

# Los cuadros de espectro no son cambios de un menú. Los trabajos de audio,
# reconexión, alarma y escaneo siguen atendiéndose en cada tick.
panel_snapshot() {
    printf -v PANEL_SNAPSHOT '%s\034' "${PLAYER_PID:-}" "${PLAYER_PAUSED:-0}" "${PLAYER_MUTED:-0}" \
        "${PLAYER_VOLUME:-0}" "${PLAYER_STREAM_READY:-0}" "${PLAYER_BUFFERING:-0}" "${PLAYER_NAME:-}" \
        "${ALARM_AT:-0}" "${RECORDING_PHASE:-}" "${UI_MESSAGE:-}" "${CATALOG_PID:-}" "${CATALOG_LAST_ERROR:-}" \
        "${PENDING_SCAN_PID:-}"
}

panel_poll() {
    local before
    panel_snapshot; before=$PANEL_SNAPSHOT
    app_poll_player || true
    catalog_poll || true
    pending_scan_poll || true
    ui_message_tick || true
    panel_snapshot
    [[ "$before" != "$PANEL_SNAPSHOT" ]]
}

panel_move() {
    local event=$1 selected=$2 count=$3 visible=$4 repeat=${INPUT_REPEAT_COUNT:-1}
    [[ "$repeat" =~ ^[1-8]$ ]] || repeat=1
    case "$event" in
        UP) selected=$((selected-repeat)) ;;
        DOWN) selected=$((selected+repeat)) ;;
        HOME) selected=0 ;;
        END) selected=$((count-1)) ;;
        PAGE_UP) selected=$((selected-visible)) ;;
        PAGE_DOWN) selected=$((selected+visible)) ;;
    esac
    ((selected >= count)) && selected=$((count-1))
    ((selected < 0)) && selected=0
    PANEL_SELECTED=$selected
}

panel_detail() {
    local title=$1 index=$2 redraw=1
    local OPTIONS_SELECTED=$index OPTIONS_TITLE=$title OPTIONS_DETAIL_SCROLL=0 OPTIONS_DETAIL_VISIBLE=1 OPTIONS_BREADCRUMB
    local OPTIONS_SCROLL=0 OPTIONS_VISIBLE=1 OPTIONS_FORM=0
    local -a OPTIONS_ROWS=("${PANEL_ROWS[@]}") OPTIONS_DETAIL_LINES=()
    ((${#OPTIONS_ROWS[@]})) || return 0
    panel_path "$title"
    OPTIONS_BREADCRUMB="$PANEL_PATH > DETALLE"
    while true; do
        ((redraw)) && options_detail_draw
        input_read || break
        redraw=1
        case "$INPUT_EVENT" in
            ESC|LEFT) break ;;
            KEY) [[ "$INPUT_KEY" != '?' ]] || break ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            RESIZE) ;;
            *) panel_move "$INPUT_EVENT" "$OPTIONS_DETAIL_SCROLL" "${#OPTIONS_DETAIL_LINES[@]}" "$OPTIONS_DETAIL_VISIBLE"; OPTIONS_DETAIL_SCROLL=$PANEL_SELECTED ;;
        esac
    done
    return 0
}
