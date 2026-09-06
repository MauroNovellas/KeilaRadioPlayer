#!/usr/bin/env bash

# Interfaz de terminal de Keila Radio Player.
# Este módulo solo dibuja y gestiona estado visual; la lógica de reproducción,
# entrada y persistencia vive en sus módulos correspondientes.

UI_ACTIVE=0
UI_SUSPENDED=0
UI_SELECTED_INDEX=0
UI_SCROLL_OFFSET=0
UI_MESSAGE=""
UI_MESSAGE_EXPIRES=0
UI_HELP_VISIBLE=0
UI_COLS=80
UI_LINES=24
UI_UNICODE=0
UI_COLOR=0
UI_RESET=''
UI_BOLD=''
UI_DIM=''
UI_GREEN=''
UI_RED=''
UI_YELLOW=''
UI_CYAN=''

ui_locale_supports_unicode() {
    [[ "${KEILA_ASCII_UI:-0}" != '1' ]] || return 1
    local locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    case "$locale" in
        *UTF-8*|*utf8*|*UTF8*) return 0 ;;
        *) return 1 ;;
    esac
}

ui_configure_glyphs() {
    if ((UI_UNICODE)); then
        UI_TL='╭'; UI_TR='╮'; UI_BL='╰'; UI_BR='╯'
        UI_V='│'; UI_H='─'; UI_ML='├'; UI_MR='┤'
        UI_PLAY='▶'; UI_PAUSE='Ⅱ'; UI_BUFFER='◌'; UI_STOP='■'
        UI_FAVORITE='★'; UI_RECORD='●'; UI_NOTE='♪'; UI_SELECT='›'
        UI_BAR_FULL='█'; UI_BAR_EMPTY='░'; UI_SEP='·'
    else
        UI_TL='+'; UI_TR='+'; UI_BL='+'; UI_BR='+'
        UI_V='|'; UI_H='-'; UI_ML='+'; UI_MR='+'
        UI_PLAY='>'; UI_PAUSE='||'; UI_BUFFER='~'; UI_STOP='x'
        UI_FAVORITE='*'; UI_RECORD='o'; UI_NOTE='>'; UI_SELECT='>'
        UI_BAR_FULL='#'; UI_BAR_EMPTY='-'; UI_SEP='|'
    fi
}

ui_color_supported() {
    [[ "${KEILA_NO_COLOR:-0}" != '1' ]] || return 1
    [[ -z "${NO_COLOR:-}" ]] || return 1
    [[ "${TERM:-}" != 'dumb' ]] || return 1
    command -v tput >/dev/null 2>&1 || return 1

    local colors
    colors=$(tput colors 2>/dev/null || printf '0')
    [[ "$colors" =~ ^[0-9]+$ ]] || return 1
    ((colors >= 8))
}

ui_configure_theme() {
    UI_COLOR=0
    UI_RESET=''
    UI_BOLD=''
    UI_DIM=''
    UI_GREEN=''
    UI_RED=''
    UI_YELLOW=''
    UI_CYAN=''

    ui_color_supported || return 0

    UI_COLOR=1
    UI_RESET=$(tput sgr0 2>/dev/null || true)
    UI_BOLD=$(tput bold 2>/dev/null || true)
    UI_DIM=$(tput dim 2>/dev/null || true)
    UI_GREEN=$(tput setaf 2 2>/dev/null || true)
    UI_RED=$(tput setaf 1 2>/dev/null || true)
    UI_YELLOW=$(tput setaf 3 2>/dev/null || true)
    UI_CYAN=$(tput setaf 6 2>/dev/null || true)
}

ui_style_begin() {
    local style="${1:-}"
    ((UI_COLOR)) || return 0

    case "$style" in
        title|selected) printf '%s%s' "$UI_BOLD" "$UI_CYAN" ;;
        playing) printf '%s%s' "$UI_BOLD" "$UI_GREEN" ;;
        record) printf '%s%s' "$UI_BOLD" "$UI_RED" ;;
        favorite|warning) printf '%s' "$UI_YELLOW" ;;
        accent) printf '%s' "$UI_CYAN" ;;
        separator) printf '%s' "$UI_GREEN" ;;
        muted) printf '%s' "$UI_DIM" ;;
    esac
}

ui_style_end() {
    ((UI_COLOR)) || return 0
    printf '%s' "$UI_RESET"
}

if ui_locale_supports_unicode; then
    UI_UNICODE=1
fi
ui_configure_glyphs

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

ui_layout_width() {
    local cols="${1:-$UI_COLS}"
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    ((cols > 92)) && cols=92
    printf '%s\n' "$cols"
}

ui_volume_bar_width() {
    local width="$1"
    local bar=$((width - 42))
    ((bar < 12)) && bar=12
    ((bar > 28)) && bar=28
    printf '%s\n' "$bar"
}

ui_set_message() {
    local text="$1"
    local ttl="${2:-5}"

    UI_MESSAGE="$text"
    UI_MESSAGE_EXPIRES=0

    if [[ "$ttl" =~ ^[0-9]+$ ]] && ((ttl > 0)); then
        local now="${EPOCHSECONDS:-$(date +%s)}"
        UI_MESSAGE_EXPIRES=$((now + ttl))
    fi
}

ui_clear_message() {
    UI_MESSAGE=""
    UI_MESSAGE_EXPIRES=0
}

ui_message_tick() {
    [[ -n "$UI_MESSAGE" ]] || return 1
    ((UI_MESSAGE_EXPIRES > 0)) || return 1

    local now="${EPOCHSECONDS:-$(date +%s)}"
    if ((now >= UI_MESSAGE_EXPIRES)); then
        ui_clear_message
        return 0
    fi

    return 1
}

ui_toggle_help() {
    if ((UI_HELP_VISIBLE)); then
        UI_HELP_VISIBLE=0
    else
        UI_HELP_VISIBLE=1
    fi
}

ui_control_line_count() {
    if ((UI_HELP_VISIBLE)); then
        printf '4\n'
    else
        printf '1\n'
    fi
}

ui_enter() {
    ((UI_ACTIVE)) && return 0
    ui_configure_theme
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
    ui_configure_theme
    tput civis 2>/dev/null || true
    tput clear 2>/dev/null || true
    UI_SUSPENDED=0
}

ui_leave() {
    ((UI_ACTIVE)) || return 0
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
    if ((max <= 0)); then return 0; fi
    if ((${#text} <= max)); then printf '%s' "$text"; return 0; fi
    if ((max <= 3)); then printf '%s' "${text:0:max}"; return 0; fi
    local cut=$((max - 3))
    printf '%s...' "${text:0:cut}"
}

ui_repeat_char() {
    local char="$1"
    local count="$2"
    local output=''
    while ((count > 0)); do
        output+="$char"
        ((count -= 1))
    done
    printf '%s' "$output"
}

ui_print_padded() {
    local width="$1"
    local text="${2:-}"
    text=$(ui_truncate "$text" "$width")
    local padding=$((width - ${#text}))
    printf '%s' "$text"
    if ((padding > 0)); then ui_repeat_char ' ' "$padding"; fi
    return 0
}

ui_print_styled_padded() {
    local width="$1"
    local text="${2:-}"
    local style="${3:-}"
    text=$(ui_truncate "$text" "$width")
    local padding=$((width - ${#text}))

    ui_style_begin "$style"
    printf '%s' "$text"
    ui_style_end
    if ((padding > 0)); then ui_repeat_char ' ' "$padding"; fi
}

ui_print_split_styled() {
    local width="$1"
    local left="${2:-}"
    local right="${3:-}"
    local left_style="${4:-}"
    local right_style="${5:-}"

    if [[ -z "$right" ]]; then
        ui_print_styled_padded "$width" "$left" "$left_style"
        return 0
    fi

    local right_len=${#right}
    if ((right_len >= width)); then
        ui_print_styled_padded "$width" "$right" "$right_style"
        return 0
    fi

    local left_max=$((width - right_len - 1))
    left=$(ui_truncate "$left" "$left_max")
    local gap=$((width - ${#left} - right_len))
    ((gap < 1)) && gap=1

    ui_style_begin "$left_style"
    printf '%s' "$left"
    ui_style_end
    ui_repeat_char ' ' "$gap"
    ui_style_begin "$right_style"
    printf '%s' "$right"
    ui_style_end
}

ui_box_rule() {
    local width="$1"
    local left="$2"
    local right="$3"
    local label="${4:-}"
    local label_style="${5:-muted}"
    local inner=$((width - 2))

    ui_style_begin muted
    printf '%s' "$left"
    if [[ -z "$label" ]]; then
        ui_repeat_char "$UI_H" "$inner"
    else
        printf '%s ' "$UI_H"
        ui_style_end
        local label_max=$((inner - 3))
        ((label_max < 1)) && label_max=1
        label=$(ui_truncate "$label" "$label_max")
        ui_style_begin "$label_style"
        printf '%s' "$label"
        ui_style_end
        ui_style_begin muted
        printf ' '
        ui_repeat_char "$UI_H" "$((inner - ${#label} - 3))"
    fi
    printf '%s' "$right"
    ui_style_end
    printf '\n'
}

ui_box_line() {
    local width="$1"
    local text="${2:-}"
    local style="${3:-}"
    local inner=$((width - 4))
    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf ' '
    ui_print_styled_padded "$inner" "$text" "$style"
    printf ' '
    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf '\n'
}

ui_box_center_line() {
    local width="$1"
    local text="$2"
    local style="${3:-}"
    local inner=$((width - 4))
    text=$(ui_truncate "$text" "$inner")
    local left_pad=$(((inner - ${#text}) / 2))
    local right_pad=$((inner - ${#text} - left_pad))

    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf ' '
    ui_repeat_char ' ' "$left_pad"
    ui_style_begin "$style"
    printf '%s' "$text"
    ui_style_end
    ui_repeat_char ' ' "$right_pad"
    printf ' '
    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf '\n'
}

ui_box_split_line() {
    local width="$1"
    local left="${2:-}"
    local right="${3:-}"
    local selected="${4:-0}"
    local left_style="${5:-}"
    local right_style="${6:-}"
    local inner=$((width - 4))

    if ((selected)); then
        left_style='selected'
        right_style='selected'
    fi

    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf ' '
    ui_print_split_styled "$inner" "$left" "$right" "$left_style" "$right_style"
    printf ' '
    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf '\n'
}

ui_print_badged_status() {
    local width="$1"
    local left="$2"
    local left_style="$3"
    local recording_badge="$4"
    local favorite_badge="$5"
    local state_badge="$6"
    local right=''

    [[ -n "$recording_badge" ]] && right+="$recording_badge"
    if [[ -n "$favorite_badge" ]]; then
        [[ -n "$right" ]] && right+='  '
        right+="$favorite_badge"
    fi
    if [[ -n "$state_badge" ]]; then
        [[ -n "$right" ]] && right+='  '
        right+="$state_badge"
    fi

    local right_len=${#right}
    local left_max=$width
    if ((right_len > 0)); then left_max=$((width - right_len - 1)); fi
    ((left_max < 1)) && left_max=1
    left=$(ui_truncate "$left" "$left_max")

    ui_style_begin "$left_style"
    printf '%s' "$left"
    ui_style_end

    if ((right_len > 0)); then
        local gap=$((width - ${#left} - right_len))
        ((gap < 1)) && gap=1
        ui_repeat_char ' ' "$gap"

        local printed=0
        if [[ -n "$recording_badge" ]]; then
            ui_style_begin record; printf '%s' "$recording_badge"; ui_style_end
            printed=1
        fi
        if [[ -n "$favorite_badge" ]]; then
            ((printed)) && printf '  '
            ui_style_begin favorite; printf '%s' "$favorite_badge"; ui_style_end
            printed=1
        fi
        if [[ -n "$state_badge" ]]; then
            ((printed)) && printf '  '
            ui_style_begin warning; printf '%s' "$state_badge"; ui_style_end
        fi
    fi
}

ui_box_player_line() {
    local width="$1"
    local left="$2"
    local left_style="$3"
    local recording_badge="$4"
    local favorite_badge="$5"
    local state_badge="$6"
    local inner=$((width - 4))

    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf ' '
    ui_print_badged_status "$inner" "$left" "$left_style" "$recording_badge" "$favorite_badge" "$state_badge"
    printf ' '
    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    printf '\n'
}

ui_volume_bar() {
    local width="${1:-20}"
    local filled=$((PLAYER_VOLUME * width / 100))
    local empty=$((width - filled))
    ui_repeat_char "$UI_BAR_FULL" "$filled"
    ui_repeat_char "$UI_BAR_EMPTY" "$empty"
}

ui_audio_info() {
    local -a parts=()
    [[ -n "${PLAYER_CODEC:-}" ]] && parts+=("${PLAYER_CODEC^^}")
    if [[ "${PLAYER_BITRATE_KBPS:-}" =~ ^[0-9]+$ ]] && ((PLAYER_BITRATE_KBPS > 0)); then parts+=("${PLAYER_BITRATE_KBPS} kbps"); fi
    if [[ "${PLAYER_SAMPLE_RATE:-}" =~ ^[0-9]+$ ]] && ((PLAYER_SAMPLE_RATE > 0)); then
        local whole=$((PLAYER_SAMPLE_RATE / 1000))
        local decimal=$(((PLAYER_SAMPLE_RATE % 1000) / 100))
        if ((decimal > 0)); then parts+=("${whole}.${decimal} kHz"); else parts+=("${whole} kHz"); fi
    fi
    [[ -n "${PLAYER_CHANNELS:-}" ]] && parts+=("$PLAYER_CHANNELS")
    local output="" part
    for part in "${parts[@]}"; do
        [[ -n "$output" ]] && output+=' · '
        output+="$part"
    done
    printf '%s' "$output"
}

ui_has_audio_info() {
    [[ -n "${PLAYER_CODEC:-}" ]] && return 0
    [[ "${PLAYER_BITRATE_KBPS:-}" =~ ^[0-9]+$ ]] && ((PLAYER_BITRATE_KBPS > 0)) && return 0
    [[ "${PLAYER_SAMPLE_RATE:-}" =~ ^[0-9]+$ ]] && ((PLAYER_SAMPLE_RATE > 0)) && return 0
    [[ -n "${PLAYER_CHANNELS:-}" ]] && return 0
    return 1
}

ui_stream_info_line_count() {
    local count=0
    if player_is_running; then
        [[ -n "${PLAYER_STREAM_TITLE:-}" ]] && ((count += 1))
        ui_has_audio_info && ((count += 1))
    fi
    printf '%s\n' "$count"
}

ui_list_height() {
    local info_lines control_lines
    info_lines=$(ui_stream_info_line_count)
    control_lines=$(ui_control_line_count)
    # Marco + cabecera + estado + volumen + secciones + mensaje + pie ocupan 10 filas.
    local height=$((UI_LINES - 10 - info_lines - control_lines))
    ((height < 3)) && height=3
    printf '%s\n' "$height"
}

ui_sync_selection() {
    ui_navigation_refresh
    ui_navigation_sync "$(ui_list_height)"
}

ui_select_url() {
    local url="$1" i
    [[ -n "$url" ]] || return 1
    for ((i = 0; i < ${#FAVORITE_URLS[@]}; i++)); do
        if [[ "${FAVORITE_URLS[$i]}" == "$url" ]]; then
            UI_SELECTED_INDEX=$i
            ui_sync_selection
            return 0
        fi
    done
    ui_navigation_refresh
    for ((i = 0; i < ${#RECENT_URLS[@]}; i++)); do
        if [[ "${RECENT_URLS[$i]}" == "$url" ]]; then
            UI_SELECTED_INDEX=$((${#FAVORITE_URLS[@]} + i))
            ui_sync_selection
            return 0
        fi
    done
    return 1
}

ui_move_selection() {
    local delta="$1"
    ui_navigation_refresh
    local count=$UI_NAV_COUNT
    ((count > 0)) || { ui_set_message "No tienes favoritos guardados. Pulsa B para buscar una emisora." 6; return 1; }
    UI_SELECTED_INDEX=$(((UI_SELECTED_INDEX + delta) % count))
    ((UI_SELECTED_INDEX < 0)) && UI_SELECTED_INDEX=$((UI_SELECTED_INDEX + count))
    ui_sync_selection
}

ui_select_first() { ui_navigation_refresh; ((UI_NAV_COUNT > 0)) || return 1; UI_SELECTED_INDEX=0; ui_sync_selection; }
ui_select_last() { ui_navigation_refresh; local count=$UI_NAV_COUNT; ((count > 0)) || return 1; UI_SELECTED_INDEX=$((count - 1)); ui_sync_selection; }

ui_player_status() {
    if player_is_running; then
        if ((PLAYER_PAUSED)); then printf 'Pausado'; elif ((PLAYER_BUFFERING)); then printf 'Buffering'; elif ((PLAYER_INFO_READY)); then printf 'Reproduciendo'; else printf 'Conectando'; fi
    else
        printf 'Detenido'
    fi
}

ui_player_marker() {
    if player_is_running; then
        if ((PLAYER_PAUSED)); then printf '%s' "$UI_PAUSE"; elif ((PLAYER_BUFFERING)); then printf '%s' "$UI_BUFFER"; else printf '%s' "$UI_PLAY"; fi
    else
        printf '%s' "$UI_STOP"
    fi
}

ui_draw() {
    ((UI_ACTIVE)) || return 0
    ((UI_SUSPENDED)) && return 0
    ui_refresh_size
    ui_sync_selection
    tput cup 0 0 2>/dev/null || true

    local width
    width=$(ui_layout_width "$UI_COLS")
    local info_lines control_lines min_lines
    info_lines=$(ui_stream_info_line_count)
    control_lines=$(ui_control_line_count)
    min_lines=$((13 + info_lines + control_lines))

    local version="${KEILA_VERSION:-dev}"

    if ((UI_COLS < 54 || UI_LINES < min_lines)); then
        ui_print_padded "$width" "Keila Radio Player $version"
        printf '\n\n'
        ui_print_padded "$width" "La terminal es demasiado pequeña (${UI_COLS}x${UI_LINES})."
        printf '\n'
        ui_print_padded "$width" "Necesito al menos 54 columnas y ${min_lines} filas."
        printf '\n\n'
        ui_print_padded "$width" 'Q = salir'
        printf '\n'
        tput ed 2>/dev/null || true
        return 0
    fi

    local title="KEILA RADIO PLAYER  $version"
    ui_box_rule "$width" "$UI_TL" "$UI_TR"
    ui_box_center_line "$width" "$title" title
    ui_box_rule "$width" "$UI_ML" "$UI_MR" 'AHORA SUENA' accent

    local station favorite_badge recording_badge state_badge marker station_style
    marker=$(ui_player_marker)
    if player_is_running; then
        station="$PLAYER_NAME"
        station_style='playing'
        if favorites_find_url "$PLAYER_URL" >/dev/null 2>&1; then favorite_badge="[$UI_FAVORITE FAVORITA]"; else favorite_badge=''; fi
    elif [[ -n "${STATE_LAST_NAME:-}" ]]; then
        station="Última: $STATE_LAST_NAME"
        station_style='muted'
        favorite_badge=''
    else
        station='Ninguna emisora seleccionada'
        station_style='muted'
        favorite_badge=''
    fi

    if ((RECORDING_ACTIVE)); then recording_badge="[$UI_RECORD REC $(recording_elapsed_display)]"; else recording_badge=''; fi
    state_badge=''
    if player_is_running && ((PLAYER_PAUSED)); then
        state_badge='[PAUSA]'
    elif player_is_running && ((PLAYER_BUFFERING)); then
        state_badge='[BUFFERING]'
    fi

    ui_box_player_line "$width" "$marker $station" "$station_style" "$recording_badge" "$favorite_badge" "$state_badge"

    if player_is_running; then
        [[ -n "${PLAYER_STREAM_TITLE:-}" ]] && ui_box_line "$width" "$UI_NOTE $PLAYER_STREAM_TITLE" accent
        local audio_info
        audio_info=$(ui_audio_info)
        [[ -n "$audio_info" ]] && ui_box_line "$width" "  $audio_info" muted
    fi

    local volume_bar_width volume_left volume_hint
    volume_bar_width=$(ui_volume_bar_width "$width")
    volume_left="VOL $(printf '%3s' "$PLAYER_VOLUME")%  $(ui_volume_bar "$volume_bar_width")"
    volume_hint='A/D  ←/→'
    ui_box_split_line "$width" "$volume_left" "$volume_hint" 0 accent muted
    ui_box_rule "$width" "$UI_ML" "$UI_MR" "FAVORITOS (${#FAVORITE_NAMES[@]})" accent

    local height
    height=$(ui_list_height)
    if ((${#FAVORITE_NAMES[@]} == 0)); then
        ui_box_line "$width" '  (sin favoritos; pulsa B para buscar)' muted
        local blank
        for ((blank = 1; blank < height; blank++)); do ui_box_line "$width" ''; done
    else
        local row index marker_prefix right_badge name_line selected left_style right_style
        for ((row = 0; row < height; row++)); do
            index=$((UI_SCROLL_OFFSET + row))
            if ((index >= ${#FAVORITE_NAMES[@]})); then ui_box_line "$width" ''; continue; fi

            marker_prefix='  '
            ((index == UI_SELECTED_INDEX)) && marker_prefix="$UI_SELECT "
            right_badge=''
            left_style=''
            right_style=''
            if player_is_running && [[ "${FAVORITE_URLS[$index]}" == "$PLAYER_URL" ]]; then
                right_badge='[PLAY]'
                left_style='playing'
                right_style='playing'
                [[ "$marker_prefix" == '  ' ]] && marker_prefix="$UI_PLAY "
            elif [[ -n "${STATE_LAST_URL:-}" && "${FAVORITE_URLS[$index]}" == "$STATE_LAST_URL" ]]; then
                right_badge='[ÚLTIMA]'
                right_style='muted'
            fi

            name_line="$marker_prefix${FAVORITE_NAMES[$index]}"
            selected=0
            ((index == UI_SELECTED_INDEX)) && selected=1
            ui_box_split_line "$width" "$name_line" "$right_badge" "$selected" "$left_style" "$right_style"
        done
    fi

    ui_box_rule "$width" "$UI_ML" "$UI_MR"
    if ((UI_HELP_VISIBLE)); then
        ui_box_line "$width" 'W/S o ↑/↓ mover   Home/End extremos   PgUp/PgDn saltar' muted
        ui_box_line "$width" 'Enter reproducir   A/D o ←/→ volumen   P pausa' muted
        ui_box_line "$width" 'F favorito actual   J/K reordenar   X quitar seleccionado' muted
        ui_box_line "$width" 'B buscar   R grabar   U actualizar   Q salir   H cerrar ayuda' muted
    else
        ui_box_line "$width" "↑↓ mover  $UI_SEP  Enter reproducir  $UI_SEP  B buscar  $UI_SEP  R grabar  $UI_SEP  H ayuda  $UI_SEP  Q salir" muted
    fi

    if [[ -n "$UI_MESSAGE" ]]; then ui_box_line "$width" "$UI_MESSAGE"; else ui_box_line "$width" ''; fi
    ui_box_rule "$width" "$UI_BL" "$UI_BR"
    tput ed 2>/dev/null || true
}

# shellcheck source=lib/navigation.sh
source "$(dirname "${BASH_SOURCE[0]}")/navigation.sh"
