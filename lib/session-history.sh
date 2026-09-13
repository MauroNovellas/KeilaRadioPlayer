#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Visor TUI del registro de canciones de la sesión actual.

SESSION_HISTORY_ACTIVE=0
SESSION_HISTORY_SCROLL=0
SESSION_HISTORY_SELECTED=0
SESSION_HISTORY_CHECK_AT=0
SESSION_HISTORY_SIGNATURE=''
SESSION_HISTORY_ROWS=()

session_history_file() {
    printf '%s' "${SESSION_LOG_FILE:-}"
}

session_history_signature() {
    local file
    file=$(session_history_file)
    [[ -n "$file" && -f "$file" && ! -L "$file" ]] || { printf 'none'; return 0; }
    stat -c '%s:%Y' "$file" 2>/dev/null || printf 'unavailable'
}

session_history_load() {
    local file raw timestamp station title rest

    file=$(session_history_file)
    SESSION_HISTORY_ROWS=()
    [[ -n "$file" && -f "$file" && -r "$file" && ! -L "$file" ]] || return 1

    while IFS= read -r raw || [[ -n "$raw" ]]; do
        [[ -n "$raw" && "${raw:0:1}" != '#' ]] || continue
        IFS=$'\t' read -r timestamp station title rest <<< "$raw"
        [[ -n "$timestamp$station$title" ]] || continue
        timestamp=${timestamp//[[:cntrl:]]/ } timestamp=${timestamp:0:32}
        station=${station//[[:cntrl:]]/ } station=${station:0:120}
        title=${title//[[:cntrl:]]/ } title=${title:0:240}
        SESSION_HISTORY_ROWS+=("$timestamp"$'\t'"$station"$'\t'"$title")
    done < "$file"
}

session_history_row_text() {
    local width="$1" raw="$2" timestamp station title time_text station_width title_width

    [[ "$width" =~ ^[0-9]+$ ]] || width=80
    IFS=$'\t' read -r timestamp station title <<< "$raw"
    time_text="${timestamp#* }"
    [[ "$time_text" == "$timestamp" ]] && time_text="$timestamp"
    time_text=$(session_log_truncate "$time_text" 8)

    if ((width >= 90)); then
        station_width=$((width * 30 / 100))
        ((station_width < 18)) && station_width=18
        ((station_width > 30)) && station_width=30
        title_width=$((width - station_width - 14))
        ((title_width < 10)) && title_width=10
        station=$(session_log_truncate "$station" "$station_width")
        title=$(session_log_truncate "$title" "$title_width")
        printf '%-8s  %-*s  %s' "$time_text" "$station_width" "$station" "$title"
    else
        title_width=$((width - 13))
        ((title_width < 8)) && title_width=8
        printf '%s  %s' "$time_text" "$(session_log_truncate "$station — $title" "$title_width")"
    fi
}

session_history_clamp_scroll() {
    local visible="$1" count="${#SESSION_HISTORY_ROWS[@]}" max_scroll

    ((visible < 1)) && visible=1
    max_scroll=$((count - visible))
    ((max_scroll < 0)) && max_scroll=0
    ((SESSION_HISTORY_SCROLL < 0)) && SESSION_HISTORY_SCROLL=0
    ((SESSION_HISTORY_SCROLL > max_scroll)) && SESSION_HISTORY_SCROLL=$max_scroll
}

session_history_refresh() {
    ((EPOCHSECONDS >= SESSION_HISTORY_CHECK_AT)) || return 1
    SESSION_HISTORY_CHECK_AT=$((EPOCHSECONDS + 1))
    local signature old_count=${#SESSION_HISTORY_ROWS[@]} follow=0
    ((SESSION_HISTORY_SELECTED >= old_count - 1)) && follow=1
    signature=$(session_history_signature)
    [[ "$signature" != "$SESSION_HISTORY_SIGNATURE" ]] || return 1
    SESSION_HISTORY_SIGNATURE=$signature
    session_history_load >/dev/null 2>&1 || true
    ((follow == 0)) || SESSION_HISTORY_SELECTED=$((${#SESSION_HISTORY_ROWS[@]} > 0 ? ${#SESSION_HISTORY_ROWS[@]} - 1 : 0))
    return 0
}

session_history_build_panel() {
    local row timestamp station title label count=${#SESSION_HISTORY_ROWS[@]}
    PANEL_ROWS=()
    for row in "${SESSION_HISTORY_ROWS[@]}"; do
        IFS=$'\t' read -r timestamp station title <<< "$row"
        label="${timestamp##* } $station"
        if ((UI_COLS < 70)); then label="${timestamp##* } $title"; fi
        panel_add_row '' "$label" "Hora: $timestamp. Emisora: $station. Canción / evento: $title. Archivo: ${SESSION_LOG_FILE:-no iniciado}." "$title"
    done
    ((count > 0)) || panel_add_row '' 'Sin canciones registradas' "El registro se actualiza al recibir títulos de la emisora. Archivo: ${SESSION_LOG_FILE:-todavía no iniciado}."
}

session_history_draw() {
    ui_refresh_size
    session_history_refresh || true
    local -a PANEL_ROWS=()
    session_history_build_panel
    panel_draw 'HISTORIAL DE SESIÓN' "$SESSION_HISTORY_SELECTED" "$SESSION_HISTORY_SCROLL" 'Flechas mover | Enter detalle | Esc volver' "${UI_MESSAGE:-}" "${#SESSION_HISTORY_ROWS[@]} entradas | Archivo: ${SESSION_LOG_FILE:-registro no iniciado}"
    SESSION_HISTORY_SELECTED=$PANEL_SELECTED SESSION_HISTORY_SCROLL=$PANEL_SCROLL
}

app_session_history_screen() {
    local event key redraw=1 result=0 previous_preferences=$PREFERENCES_ACTIVE
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    SESSION_HISTORY_ACTIVE=1 PREFERENCES_ACTIVE=1 SESSION_HISTORY_CHECK_AT=0
    session_history_refresh || true
    SESSION_HISTORY_SELECTED=$((${#SESSION_HISTORY_ROWS[@]} > 0 ? ${#SESSION_HISTORY_ROWS[@]} - 1 : 0))
    while true; do
        ((redraw)) && session_history_draw
        input_read || break
        event=$INPUT_EVENT key=$INPUT_KEY redraw=1
        case "$event" in
            TICK)
                redraw=0; panel_poll && redraw=1
                session_history_refresh && redraw=1 ;;
            RESIZE) ;;
            ESC|LEFT) break ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$event" "$SESSION_HISTORY_SELECTED" "${#SESSION_HISTORY_ROWS[@]}" "$PANEL_VISIBLE"
                SESSION_HISTORY_SELECTED=$PANEL_SELECTED ;;
            ENTER)
                local -a PANEL_ROWS=()
                session_history_build_panel
                panel_detail 'HISTORIAL DE SESIÓN' "$SESSION_HISTORY_SELECTED" ;;
            KEY)
                case "$key" in
                    s|S) break ;;
                    '?')
                        local -a PANEL_ROWS=()
                        session_history_build_panel
                        panel_detail 'HISTORIAL DE SESIÓN' "$SESSION_HISTORY_SELECTED" ;;
                    q|Q) result=2; break ;;
                    *) redraw=0 ;;
                esac ;;
        esac
    done
    SESSION_HISTORY_ACTIVE=0 PREFERENCES_ACTIVE=$previous_preferences
    if ((!previous_preferences && result != 2)); then ui_draw; fi
    return "$result"
}
