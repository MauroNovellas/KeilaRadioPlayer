#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Visor TUI del registro de canciones de la sesión actual.

SESSION_HISTORY_ACTIVE=0
SESSION_HISTORY_SCROLL=0
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
        timestamp=$(session_log_text "$timestamp" 32)
        station=$(session_log_text "$station" 120)
        title=$(session_log_text "$title" 240)
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

session_history_draw() {
    ui_refresh_size
    session_history_load >/dev/null 2>&1 || true

    local width=$((UI_COLS - 1)) visible row index count path line header
    ((width < 1)) && width=1
    visible=$((UI_LINES - 6))
    ((visible < 1)) && visible=1
    count=${#SESSION_HISTORY_ROWS[@]}
    session_history_clamp_scroll "$visible"
    path=$(session_history_file)
    if [[ -z "$path" ]]; then path='registro no iniciado'; fi

    tput cup 0 0 2>/dev/null || true
    ui_print_styled_padded "$width" 'KEILA · HISTORIAL DE SESIÓN' title
    printf '\n'
    ui_print_padded "$width" "Archivo: $(session_log_truncate_left "$path" "$((width - 9))")"
    printf '\n'

    if ((width >= 90)); then
        header=$(printf '%-8s  %-30s  %s' HORA EMISORA 'CANCIÓN / EVENTO')
    else
        header='HORA      EMISORA — CANCIÓN / EVENTO'
    fi
    ui_print_styled_padded "$width" "$header" accent
    printf '\n'

    if ((count == 0)); then
        ui_print_padded "$width" 'Aún no hay canciones registradas en esta sesión.'
        printf '\n'
        for ((row = 1; row < visible; row++)); do ui_print_padded "$width" ''; printf '\n'; done
    else
        for ((row = 0; row < visible; row++)); do
            index=$((SESSION_HISTORY_SCROLL + row))
            if ((index < count)); then
                line=$(session_history_row_text "$width" "${SESSION_HISTORY_ROWS[index]}")
                ui_print_padded "$width" "$line"
            else
                ui_print_padded "$width" ''
            fi
            printf '\n'
        done
    fi

    ui_print_padded "$width" "↑↓ mover · PgUp/PgDn saltar · Home/End extremos · S/Esc volver · $count entradas"
    printf '\n'
    ui_print_padded "$width" "${UI_MESSAGE:-}"
    tput ed 2>/dev/null || true
}

app_session_history_screen() {
    local event key redraw=1 previous_signature current_signature visible at_bottom=1 max_scroll=0
    local previous_preferences=$PREFERENCES_ACTIVE

    SESSION_HISTORY_ACTIVE=1
    PREFERENCES_ACTIVE=1
    session_history_load >/dev/null 2>&1 || true
    visible=$((UI_LINES - 6))
    ((visible < 1)) && visible=1
    max_scroll=$((${#SESSION_HISTORY_ROWS[@]} - visible))
    ((max_scroll < 0)) && max_scroll=0
    SESSION_HISTORY_SCROLL=$max_scroll
    SESSION_HISTORY_SIGNATURE=$(session_history_signature)

    while true; do
        ((redraw)) && session_history_draw
        previous_signature=$SESSION_HISTORY_SIGNATURE
        input_read || break
        event=$INPUT_EVENT
        key=$INPUT_KEY
        redraw=1

        case "$event" in
            TICK)
                redraw=0
                visible=$((UI_LINES - 6))
                ((visible < 1)) && visible=1
                session_history_load >/dev/null 2>&1 || true
                max_scroll=$((${#SESSION_HISTORY_ROWS[@]} - visible))
                ((max_scroll < 0)) && max_scroll=0
                if ((SESSION_HISTORY_SCROLL >= max_scroll)); then at_bottom=1; else at_bottom=0; fi
                app_poll_player && redraw=1
                catalog_poll && redraw=1
                pending_scan_poll && redraw=1
                ui_message_tick && redraw=1
                current_signature=$(session_history_signature)
                if [[ "$current_signature" != "$previous_signature" ]]; then
                    SESSION_HISTORY_SIGNATURE=$current_signature
                    session_history_load >/dev/null 2>&1 || true
                    max_scroll=$((${#SESSION_HISTORY_ROWS[@]} - visible))
                    ((max_scroll < 0)) && max_scroll=0
                    ((at_bottom)) && SESSION_HISTORY_SCROLL=$max_scroll
                    redraw=1
                fi
                ;;
            RESIZE)
                redraw=1
                ;;
            ESC)
                break
                ;;
            UP)
                ((SESSION_HISTORY_SCROLL > 0)) && ((SESSION_HISTORY_SCROLL -= 1))
                ;;
            DOWN)
                ((SESSION_HISTORY_SCROLL += 1))
                ;;
            PAGE_UP)
                SESSION_HISTORY_SCROLL=$((SESSION_HISTORY_SCROLL - visible))
                ;;
            PAGE_DOWN)
                SESSION_HISTORY_SCROLL=$((SESSION_HISTORY_SCROLL + visible))
                ;;
            HOME)
                SESSION_HISTORY_SCROLL=0
                ;;
            END)
                SESSION_HISTORY_SCROLL=999999
                ;;
            KEY)
                case "$key" in
                    s|S) break ;;
                    q|Q) SESSION_HISTORY_ACTIVE=0; PREFERENCES_ACTIVE=$previous_preferences; return 2 ;;
                    *) redraw=0 ;;
                esac
                ;;
        esac
        session_history_load >/dev/null 2>&1 || true
        session_history_clamp_scroll "$visible"
    done

    SESSION_HISTORY_ACTIVE=0
    PREFERENCES_ACTIVE=$previous_preferences
    ((${OPTIONS_ACTIVE:-0})) || ui_draw
}
