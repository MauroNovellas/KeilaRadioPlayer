#!/usr/bin/env bash

# Interfaz de terminal de Keila Radio Player v2.
# Este módulo solo dibuja y gestiona estado visual; la lógica de reproducción,
# entrada y persistencia vive en sus módulos correspondientes.

UI_ACTIVE=0
UI_SUSPENDED=0
UI_SELECTED_INDEX=0
UI_SCROLL_OFFSET=0
UI_MESSAGE=""
UI_COLS=80
UI_LINES=24

ui_require_dependencies() {
    if ! command -v tput >/dev/null 2>&1; then
        printf 'Falta la dependencia: tput\n' >&2
        printf 'En Debian puedes instalarla con: sudo apt install ncurses-bin\n' >&2
        return 1
    fi
}

ui_refresh_size() {
    UI_COLS=$(tput cols 2>/dev/null || printf '80')
    UI_LINES=$(tput lines 2>/dev/null || printf '24')

    [[ "$UI_COLS" =~ ^[0-9]+$ ]] || UI_COLS=80
    [[ "$UI_LINES" =~ ^[0-9]+$ ]] || UI_LINES=24
}

ui_enter() {
    ((UI_ACTIVE)) && return 0

    tput smcup 2>/dev/null || true
    tput civis 2>/dev/null || true
    tput clear 2>/dev/null || true
    UI_ACTIVE=1
    UI_SUSPENDED=0
}

ui_suspend() {
    ((UI_ACTIVE)) || return 0
    tput cnorm 2>/dev/null || true
    tput sgr0 2>/dev/null || true
    tput clear 2>/dev/null || true
    UI_SUSPENDED=1
}

ui_resume() {
    ((UI_ACTIVE)) || return 0
    tput civis 2>/dev/null || true
    tput clear 2>/dev/null || true
    UI_SUSPENDED=0
}

ui_leave() {
    ((UI_ACTIVE)) || return 0

    # Limpiamos la pantalla alternativa, la abandonamos y limpiamos también
    # la pantalla principal. Así al cerrar Keila no quedan restos de la TUI.
    tput cnorm 2>/dev/null || true
    tput sgr0 2>/dev/null || true
    tput clear 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    tput clear 2>/dev/null || true
    tput cup 0 0 2>/dev/null || true

    UI_ACTIVE=0
    UI_SUSPENDED=0
}

ui_truncate() {
    local text="$1"
    local max="$2"

    if ((max <= 0)); then
        return 0
    fi

    if ((${#text} <= max)); then
        printf '%s' "$text"
        return 0
    fi

    if ((max <= 3)); then
        printf '%s' "${text:0:max}"
        return 0
    fi

    local cut=$((max - 3))
    printf '%s...' "${text:0:cut}"
}

ui_print_line() {
    local width="$1"
    local text="${2:-}"

    text=$(ui_truncate "$text" "$width")
    printf '%-*s\n' "$width" "$text"
}

ui_separator() {
    local width="$1"
    local line
    printf -v line '%*s' "$width" ''
    ui_print_line "$width" "${line// /-}"
}

ui_volume_bar() {
    local width="${1:-20}"
    local filled=$((PLAYER_VOLUME * width / 100))
    local empty=$((width - filled))
    local left right

    printf -v left '%*s' "$filled" ''
    printf -v right '%*s' "$empty" ''
    left=${left// /#}
    right=${right// /-}

    printf '[%s%s]' "$left" "$right"
}

ui_list_height() {
    local height=$((UI_LINES - 12))
    ((height < 3)) && height=3
    printf '%s\n' "$height"
}

ui_sync_selection() {
    local count=${#FAVORITE_NAMES[@]}

    if ((count == 0)); then
        UI_SELECTED_INDEX=0
        UI_SCROLL_OFFSET=0
        return 0
    fi

    ((UI_SELECTED_INDEX < 0)) && UI_SELECTED_INDEX=0
    ((UI_SELECTED_INDEX >= count)) && UI_SELECTED_INDEX=$((count - 1))

    local height
    height=$(ui_list_height)

    if ((UI_SELECTED_INDEX < UI_SCROLL_OFFSET)); then
        UI_SCROLL_OFFSET=$UI_SELECTED_INDEX
    elif ((UI_SELECTED_INDEX >= UI_SCROLL_OFFSET + height)); then
        UI_SCROLL_OFFSET=$((UI_SELECTED_INDEX - height + 1))
    fi

    local max_scroll=$((count - height))
    ((max_scroll < 0)) && max_scroll=0
    ((UI_SCROLL_OFFSET > max_scroll)) && UI_SCROLL_OFFSET=$max_scroll
    ((UI_SCROLL_OFFSET < 0)) && UI_SCROLL_OFFSET=0
}

ui_select_url() {
    local url="$1"
    local i

    [[ -n "$url" ]] || return 1

    for ((i = 0; i < ${#FAVORITE_URLS[@]}; i++)); do
        if [[ "${FAVORITE_URLS[$i]}" == "$url" ]]; then
            UI_SELECTED_INDEX=$i
            ui_sync_selection
            return 0
        fi
    done

    return 1
}

ui_move_selection() {
    local delta="$1"
    local count=${#FAVORITE_NAMES[@]}

    ((count > 0)) || {
        UI_MESSAGE="No tienes favoritos guardados. Pulsa B para buscar una emisora."
        return 1
    }

    # Navegación circular incluso para saltos grandes (PageUp/PageDown).
    UI_SELECTED_INDEX=$(((UI_SELECTED_INDEX + delta) % count))
    ((UI_SELECTED_INDEX < 0)) && UI_SELECTED_INDEX=$((UI_SELECTED_INDEX + count))

    ui_sync_selection
}

ui_select_first() {
    ((${#FAVORITE_NAMES[@]} > 0)) || return 1
    UI_SELECTED_INDEX=0
    ui_sync_selection
}

ui_select_last() {
    local count=${#FAVORITE_NAMES[@]}
    ((count > 0)) || return 1
    UI_SELECTED_INDEX=$((count - 1))
    ui_sync_selection
}

ui_player_status() {
    if player_is_running; then
        if ((PLAYER_PAUSED)); then
            printf 'Pausado'
        else
            printf 'Reproduciendo'
        fi
    else
        printf 'Detenido'
    fi
}

ui_draw() {
    ((UI_ACTIVE)) || return 0
    ((UI_SUSPENDED)) && return 0

    ui_refresh_size
    ui_sync_selection

    # Reescribimos el frame desde la esquina superior sin limpiar antes para
    # evitar el flash visible que producía un clear/ed previo al redibujado.
    tput cup 0 0 2>/dev/null || true

    local width=$UI_COLS
    ((width > 78)) && width=78

    if ((UI_COLS < 54 || UI_LINES < 15)); then
        ui_print_line "$width" 'Keila Radio Player v2'
        ui_print_line "$width" ''
        ui_print_line "$width" "La terminal es demasiado pequeña (${UI_COLS}x${UI_LINES})."
        ui_print_line "$width" 'Necesito al menos 54 columnas y 15 filas.'
        ui_print_line "$width" ''
        ui_print_line "$width" 'Q = salir'
        tput ed 2>/dev/null || true
        return 0
    fi

    local title='KEILA RADIO PLAYER v2'
    local pad=$(((width - ${#title}) / 2))
    local title_line
    ((pad < 0)) && pad=0
    printf -v title_line '%*s%s' "$pad" '' "$title"
    ui_print_line "$width" "$title_line"
    ui_separator "$width"

    local status station favorite_status
    status=$(ui_player_status)

    if player_is_running; then
        station="$PLAYER_NAME"
        if favorites_find_url "$PLAYER_URL" >/dev/null 2>&1; then
            favorite_status=' [favorita]'
        else
            favorite_status=''
        fi
    elif [[ -n "${STATE_LAST_NAME:-}" ]]; then
        station="Ultima: $STATE_LAST_NAME"
        favorite_status=''
    else
        station='Ninguna emisora seleccionada'
        favorite_status=''
    fi

    local status_text="$status - $station$favorite_status"
    ui_print_line "$width" "$status_text"

    local volume_line
    volume_line="Volumen: $(printf '%3s' "$PLAYER_VOLUME")%  $(ui_volume_bar 20)"
    ui_print_line "$width" "$volume_line"
    ui_separator "$width"

    ui_print_line "$width" "FAVORITOS (${#FAVORITE_NAMES[@]})"

    local height
    height=$(ui_list_height)

    if ((${#FAVORITE_NAMES[@]} == 0)); then
        ui_print_line "$width" '  (sin favoritos; pulsa B para buscar)'
        local blank
        for ((blank = 1; blank < height; blank++)); do
            ui_print_line "$width" ''
        done
    else
        local row index marker suffix line max_name
        max_name=$((width - 3))

        for ((row = 0; row < height; row++)); do
            index=$((UI_SCROLL_OFFSET + row))

            if ((index >= ${#FAVORITE_NAMES[@]})); then
                ui_print_line "$width" ''
                continue
            fi

            marker=' '
            ((index == UI_SELECTED_INDEX)) && marker='>'

            suffix=''
            if player_is_running && [[ "${FAVORITE_URLS[$index]}" == "$PLAYER_URL" ]]; then
                suffix=' [PLAY]'
            elif [[ -n "${STATE_LAST_URL:-}" && "${FAVORITE_URLS[$index]}" == "$STATE_LAST_URL" ]]; then
                suffix=' [ULTIMA]'
            fi

            line="$marker ${FAVORITE_NAMES[$index]}$suffix"
            line=$(ui_truncate "$line" "$max_name")

            if ((index == UI_SELECTED_INDEX)); then
                tput rev 2>/dev/null || true
                printf '%-*s' "$width" "$line"
                tput sgr0 2>/dev/null || true
                printf '\n'
            else
                ui_print_line "$width" "$line"
            fi
        done
    fi

    ui_separator "$width"
    ui_print_line "$width" 'W/S o flechas mover   Enter reproducir   A/D o flechas volumen'
    ui_print_line "$width" 'F favorito actual     J/K reordenar      X quitar seleccionado'
    ui_print_line "$width" 'B buscar   P pausa   U actualizar catálogo   Q salir'

    if [[ -n "$UI_MESSAGE" ]]; then
        ui_print_line "$width" "$UI_MESSAGE"
    else
        ui_print_line "$width" ''
    fi

    # Borra únicamente restos de un frame anterior más alto, después de que el
    # nuevo ya esté visible. Así evitamos el parpadeo producido por clear/ed.
    tput ed 2>/dev/null || true
}
