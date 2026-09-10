#!/usr/bin/env bash

# Interfaz de terminal de Keila Radio Player.
# Este módulo solo dibuja y gestiona estado visual; la lógica de reproducción,
# entrada y persistencia vive en sus módulos correspondientes.

if ! declare -F tr_ui >/dev/null 2>&1; then
    # shellcheck source=lib/i18n.sh
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/i18n.sh"
fi

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

ui_shortcut() {
    local key=$1
    if declare -p PREF_KEYS >/dev/null 2>&1; then key=${PREF_KEYS[$key]:-$key}; fi
    printf '%s' "${key^^}"
}

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
    ((${PREF_COLOR:-1})) || return 1
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
        comment) printf '%s%s' "$UI_DIM" "$UI_GREEN" ;;
        accent) printf '%s' "$UI_CYAN" ;;
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
    if ((max <= 0)); then
        UI_TRUNCATED_TEXT=''
    elif ((${#text} <= max)); then
        UI_TRUNCATED_TEXT=$text
    elif ((max <= 3)); then
        UI_TRUNCATED_TEXT=${text:0:max}
    else
        UI_TRUNCATED_TEXT="${text:0:max-3}..."
    fi
    # Los helpers de dibujo reutilizan el resultado sin crear un subshell
    # por cada celda. El modo predeterminado conserva la salida pública.
    [[ "${3:-}" == state ]] || printf '%s' "$UI_TRUNCATED_TEXT"
    return 0
}

ui_repeat_char() {
    local char="$1"
    local count="$2"
    local output=''
    ((count > 0)) || return 0
    printf -v output '%*s' "$count" ''
    output=${output// /"$char"}
    printf '%s' "$output"
}

ui_print_padded() {
    local width="$1"
    local text="${2:-}"
    ui_truncate "$text" "$width" state
    text=$UI_TRUNCATED_TEXT
    local padding=$((width - ${#text}))
    printf '%s' "$text"
    if ((padding > 0)); then ui_repeat_char ' ' "$padding"; fi
    return 0
}

ui_print_styled_padded() {
    local width="$1"
    local text="${2:-}"
    local style="${3:-}"
    ui_truncate "$text" "$width" state
    text=$UI_TRUNCATED_TEXT
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
    ui_truncate "$left" "$left_max" state
    left=$UI_TRUNCATED_TEXT
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

# Dos listas paralelas dentro de un mismo panel. Cada mitad conserva su propio
# estilo para que el foco no pinte la fila de la otra sección.
ui_print_columns_styled() {
    local width="$1"
    local left="${2:-}"
    local right="${3:-}"
    local left_style="${4:-}"
    local right_style="${5:-}"
    local left_width=$((width / 2))
    local right_width=$((width - left_width - 1))

    ui_print_styled_padded "$left_width" "$left" "$left_style"
    ui_style_begin muted
    printf '%s' "$UI_V"
    ui_style_end
    ui_print_styled_padded "$right_width" "$right" "$right_style"
}

ui_print_navigation_columns() {
    local width="$1" left_name="$2" left_comment="$3" left_style="$4"
    local right_name="$5" right_comment="$6" right_style="$7"
    local left_comment_style="${8:-comment}" right_comment_style="${9:-comment}"
    local left_width right_width left_name_width right_name_width
    left_width=$((width / 2))
    right_width=$((width - left_width - 1))
    left_name_width=$((left_width / 2))
    right_name_width=$((right_width / 2))
    # Conservar el nombre de sección completo antes que el contador opcional.
    if [[ "$left_name" == *' FAVORITAS ('* ]] && ((${#left_name} > left_name_width)); then left_name=${left_name% (*}; fi
    if [[ "$right_name" == *' RECIENTES ('* ]] && ((${#right_name} > right_name_width)); then right_name=${right_name% (*}; fi
    ui_print_styled_padded "$left_name_width" "$left_name" "$left_style"
    ui_print_styled_padded "$((left_width - left_name_width))" "$left_comment" "$left_comment_style"
    ui_style_begin muted; printf '%s' "$UI_V"; ui_style_end
    ui_print_styled_padded "$right_name_width" "$right_name" "$right_style"
    ui_print_styled_padded "$((right_width - right_name_width))" "$right_comment" "$right_comment_style"
}

# Cabecera y filas de resultados de búsqueda: cada dato ocupa su propia
# columna, evitando que el texto de metadatos parezca un badge sin título.
ui_print_search_columns() {
    local width="$1" name="$2" ambit="$3" country="$4" format="$5" comment="$6" style="${7:-}"
    local usable=$((width - 8))
    local name_width=$((usable * 40 / 100))
    local ambit_width=$((usable * 15 / 100))
    local country_width=$((usable * 15 / 100))
    local format_width=$((usable * 15 / 100))
    local comment_width=$((usable - name_width - ambit_width - country_width - format_width))
    ((name_width < 10)) && name_width=10
    ((ambit_width < 5)) && ambit_width=5
    ((country_width < 5)) && country_width=5
    ((format_width < 5)) && format_width=5
    ((comment_width < 5)) && comment_width=5
    ui_print_styled_padded "$name_width" "$name" "$style"
    ui_repeat_char ' ' 2
    ui_print_styled_padded "$ambit_width" "$ambit" "$style"
    ui_repeat_char ' ' 2
    ui_print_styled_padded "$country_width" "$country" "$style"
    ui_repeat_char ' ' 2
    ui_print_styled_padded "$format_width" "$format" "$style"
    ui_repeat_char ' ' 2
    local comment_style=comment
    [[ "$style" == accent ]] && comment_style=accent
    ui_print_styled_padded "$comment_width" "$comment" "$comment_style"
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
    if [[ "$text" == *'KEILA RADIO PLAYER'* ]]; then
        if ((${ALARM_AT:-0} > 0)); then text+=" · ALARMA ${ALARM_LABEL:-}"; fi
        if ((${PLAYER_MUTED:-0})); then text+=' · MUTE'; fi
    fi
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

ui_equalizer_summary() {
    declare -F equalizer_summary >/dev/null 2>&1 || return 1
    printf '[Z] %s %s' "$(tr_ui ui.equalizer ECUALIZADOR)" "$(equalizer_summary)"
}

ui_recording_status_display() {
    if declare -F recording_status_display >/dev/null 2>&1; then
        recording_status_display
    elif declare -F recording_elapsed_display >/dev/null 2>&1; then
        recording_elapsed_display
    else
        printf 'REC'
    fi
}

ui_equalizer_mini_graph() {
    local mode="${1:-labels}" i gain height glyph
    local -a bars=('▁' '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')

    printf '[%s] %s ' "$(ui_shortcut z)" "$(tr_ui ui.equalizer ECUALIZADOR)"
    for ((i=0; i<5; i++)); do
        gain=${EQUALIZER_GAINS[i]}
        height=$(((gain + 12) * 8 / 24))
        if ((UI_UNICODE)); then glyph=${bars[height]}; else glyph=$height; fi
        printf '%s' "$glyph"
        ((i < 4)) && printf ' '
    done
}

ui_equalizer_bar_cells() {
    local direction="$1" threshold="$2" gain cell='' i
    for ((i=0; i<5; i++)); do
        gain=${EQUALIZER_GAINS[i]}
        cell=' '
        if [[ "$direction" == positive ]] && ((gain >= threshold)); then cell="$UI_BAR_FULL"; fi
        if [[ "$direction" == negative ]] && ((gain <= -threshold)); then cell="$UI_BAR_FULL"; fi
        printf '  %s  ' "$cell"
    done
}

ui_equalizer_editor_row() {
    local row="$1" gain label zero_axis cross i
    UI_EQ_TEXT=''
    UI_EQ_BADGE=''
    UI_EQ_STYLE='accent'
    case "$row" in
        0) UI_EQ_TEXT="[Z] $(tr_ui ui.equalizer ECUALIZADOR)" ;;
        1) UI_EQ_TEXT="$(ui_equalizer_bar_cells positive 9)" ;;
        2) UI_EQ_TEXT="$(ui_equalizer_bar_cells positive 5)" ;;
        3) UI_EQ_TEXT="$(ui_equalizer_bar_cells positive 1)" ;;
        4)
            zero_axis=''
            ((UI_UNICODE)) && zero_axis='──' || zero_axis='--'
            for ((i=0; i<5; i++)); do
                if ((UI_UNICODE)); then cross='┼'; else cross='+'; fi
                if ((${EQUALIZER_EDITOR_ACTIVE:-0} && i == EQUALIZER_SELECTED)); then
                    if ((UI_UNICODE)); then cross='╋'; else cross='#'; fi
                fi
                zero_axis+="$cross"
                if ((i < 4)); then
                    if ((UI_UNICODE)); then zero_axis+='────'; else zero_axis+='----'; fi
                fi
            done
            if ((UI_UNICODE)); then zero_axis+='──'; else zero_axis+='--'; fi
            UI_EQ_TEXT="$zero_axis"
            UI_EQ_STYLE='muted'
            ;;
        5) UI_EQ_TEXT="$(ui_equalizer_bar_cells negative 1)" ;;
        6) UI_EQ_TEXT="$(ui_equalizer_bar_cells negative 5)" ;;
        7) UI_EQ_TEXT="$(ui_equalizer_bar_cells negative 9)" ;;
        8) UI_EQ_TEXT='' ;;
        9)
            gain=${EQUALIZER_GAINS[EQUALIZER_SELECTED]}
            printf -v UI_EQ_TEXT '%s %+d dB' "$UI_SELECT" "$gain"
            ;;
        *) UI_EQ_TEXT='' ;;
    esac
}

# Renderiza el ecualizador con cinco columnas distribuidas por todo el ancho
# disponible. Conserva las ocho filas gráficas del editor normal, pero evita
# que el gráfico quede encajonado a la izquierda cuando comparte panel con
# otros datos de reproducción.
ui_equalizer_wide_row() {
    local row="$1" width="${2:-40}"
    local prefix threshold direction i segment_width remainder segment extra
    local label left right gain cell result=''
    local -a labels=(60 250 1k 4k 12k)

    [[ "$row" =~ ^[0-9]+$ && "$width" =~ ^[0-9]+$ ]] || return 1
    ((row >= 0 && row < 8 && width > 0)) || return 1
    local eq_key eq_shortcut=Z
    if declare -p PREF_KEYS >/dev/null 2>&1; then eq_shortcut=${PREF_KEYS[z]^^}; fi
    eq_key="$width|$UI_UNICODE|$UI_BAR_FULL|${EQUALIZER_GAINS[*]}|${EQUALIZER_EDITOR_ACTIVE:-0}|${EQUALIZER_SELECTED:-0}|$eq_shortcut"
    if [[ "$eq_key" != "${UI_EQ_CACHE_KEY:-}" ]]; then
        UI_EQ_CACHE_KEY=$eq_key
        UI_EQ_CACHE_ROWS=()
    fi
    if [[ -n "${UI_EQ_CACHE_ROWS[row]+present}" ]]; then
        UI_EQ_TEXT=${UI_EQ_CACHE_ROWS[row]}
        UI_EQ_STYLE=accent
        [[ "$row" == 4 ]] && UI_EQ_STYLE=muted
        printf '%s' "$UI_EQ_TEXT"
        return 0
    fi

    if ((row == 0)); then
        UI_EQ_TEXT="[$eq_shortcut] $(tr_ui ui.equalizer ECUALIZADOR)"
        UI_EQ_STYLE='accent'
        UI_EQ_CACHE_ROWS[row]=$(printf '%-*s' "$width" "$UI_EQ_TEXT")
        UI_EQ_TEXT=${UI_EQ_CACHE_ROWS[row]:0:width}
        printf '%s' "$UI_EQ_TEXT"
        return 0
    fi
    prefix=''
    case "$row" in
        1) direction='positive'; threshold=9 ;;
        2) direction='positive'; threshold=5 ;;
        3) direction='positive'; threshold=1 ;;
        4) direction='axis' ;;
        5) direction='negative'; threshold=1 ;;
        6) direction='negative'; threshold=5 ;;
        7) direction='negative'; threshold=9 ;;
    esac

    # El hueco entre bandas mejora la lectura sin perder el ancho completo.
    local graph_width=$((width - ${#prefix}))
    ((graph_width < 5)) && graph_width=5
    local gaps=4
    segment_width=$(((graph_width - gaps) / 5))
    ((segment_width < 1)) && segment_width=1
    remainder=$((graph_width - gaps - segment_width * 5))
    result="$prefix"

    for ((i = 0; i < 5; i++)); do
        segment=$segment_width
        ((i < remainder)) && ((segment += 1))

        case "$direction" in
            labels)
                label="${labels[i]}"
                if ((${#label} >= segment)); then
                    cell="${label:0:segment}"
                else
                    left=$(((segment - ${#label}) / 2))
                    right=$((segment - ${#label} - left))
                    printf -v cell '%*s%s%*s' "$left" '' "$label" "$right" ''
                fi
                ;;
            axis)
                if ((UI_UNICODE)); then
                    printf -v cell '%*s' "$segment" ''
                    cell=${cell// /─}
                    local axis_pos=$((segment / 2))
                    local cross='┼'
                    if ((${EQUALIZER_EDITOR_ACTIVE:-0} && i == EQUALIZER_SELECTED)); then cross='╋'; fi
                    cell="${cell:0:axis_pos}${cross}${cell:axis_pos+1}"
                else
                    printf -v cell '%*s' "$segment" ''
                    cell=${cell// /-}
                    local ascii_axis_pos=$((segment / 2))
                    local ascii_cross='+'
                    if ((${EQUALIZER_EDITOR_ACTIVE:-0} && i == EQUALIZER_SELECTED)); then ascii_cross='#'; fi
                    cell="${cell:0:ascii_axis_pos}${ascii_cross}${cell:ascii_axis_pos+1}"
                fi
                ;;
            positive|negative)
                gain=${EQUALIZER_GAINS[i]:-0}
                printf -v cell '%*s' "$segment" ''
                if [[ "$direction" == positive && "$gain" =~ ^-?[0-9]+$ ]] && ((gain >= threshold)); then
                    cell=${cell// /$UI_BAR_FULL}
                elif [[ "$direction" == negative && "$gain" =~ ^-?[0-9]+$ ]] && ((gain <= -threshold)); then
                    cell=${cell// /$UI_BAR_FULL}
                fi
                ;;
        esac

        result+="$cell"
        if ((i < 4)); then result+=' '; fi
    done

    # El cálculo de segmentos puede dejar una o dos celdas libres por redondeo.
    extra=$((width - ${#result}))
    if ((extra > 0)); then printf -v cell '%*s' "$extra" ''; result+="$cell"; fi
    UI_EQ_TEXT="${result:0:width}"
    UI_EQ_CACHE_ROWS[row]=$UI_EQ_TEXT
    UI_EQ_STYLE='accent'
    [[ "$row" == 4 ]] && UI_EQ_STYLE='muted'
    printf '%s' "$UI_EQ_TEXT"
}

ui_spectrum_row() {
    local threshold="$1" level
    local result=''
    local -a levels=("${SPECTRUM_LEVELS[@]:-}")
    ((${#levels[@]} == 16)) || levels=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
    for level in "${levels[@]}"; do
        if ((level >= threshold)); then result+="$UI_BAR_FULL"; else result+=' '; fi
    done
    printf '%s' "$result"
}

ui_spectrum_bars() {
    local level glyph
    local result=''
    local -a levels=("${SPECTRUM_LEVELS[@]:-}")
    local -a bars=('▁' '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
    ((${#levels[@]} == 16)) || levels=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
    for level in "${levels[@]}"; do
        if ((UI_UNICODE)); then
            local height=$((level * 8 / 16))
            ((height < 0)) && height=0
            ((height > 8)) && height=8
            glyph=${bars[height]}
        elif ((level > 0)); then
            glyph="$UI_BAR_FULL"
        else
            glyph="$UI_BAR_EMPTY"
        fi
        result+="$glyph"
    done
    printf '%s' "$result"
}

ui_spectrum_editor_row() {
    local row="$1" max_columns="${2:-16}" spaced="${3:-0}"
    local display_rows="${SPECTRUM_DISPLAY_ROWS:-8}" frame_rows="${SPECTRUM_FRAME_ROWS:-16}"
    local level height units full_units remainder result='' column start end max_level i
    local -a levels=("${SPECTRUM_LEVELS[@]:-}")
    local -a partial=(' ' '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')

    [[ "$row" =~ ^[0-9]+$ ]] || return 1
    [[ "$max_columns" =~ ^[0-9]+$ ]] || return 1
    [[ "$spaced" =~ ^[01]$ ]] || return 1
    [[ "$display_rows" =~ ^[0-9]+$ && "$frame_rows" =~ ^[0-9]+$ ]] || return 1
    ((display_rows > 0 && frame_rows > 0 && row < display_rows && max_columns > 0)) || return 1
    ((max_columns > 16)) && max_columns=16
    ((${#levels[@]} == 16)) || levels=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)

    for ((column = 0; column < max_columns; column++)); do
        start=$((column * 16 / max_columns))
        end=$(((column + 1) * 16 / max_columns))
        ((end <= start)) && end=$((start + 1))
        max_level=0
        for ((i = start; i < end && i < 16; i++)); do
            level="${levels[i]}"
            [[ "$level" =~ ^[0-9]+$ ]] || level=0
            ((level > max_level)) && max_level=$level
        done
        units=$((max_level * display_rows * 8 / frame_rows))
        full_units=$((units / 8))
        remainder=$((units % 8))
        height=$((display_rows - full_units))
        if ((row >= height)); then
            result+="$UI_BAR_FULL"
        elif ((remainder > 0 && row == height - 1)); then
            if ((UI_UNICODE)); then result+="${partial[remainder]}"; else result+="$UI_BAR_FULL"; fi
        else
            result+=' '
        fi
        if ((spaced && column < max_columns - 1)); then result+=' '; fi
    done
    printf '%s' "$result"
}

# Variante de ancho completo para el panel Ahora suena. Cada banda fuente se
# agrupa en columnas visibles y cada columna ocupa varias celdas, de modo que
# el analizador mantiene la misma anchura que el resto de la sección.
ui_spectrum_editor_row_wide() {
    local row="$1" width="${2:-40}"
    local display_rows="${SPECTRUM_DISPLAY_ROWS:-8}" frame_rows="${SPECTRUM_FRAME_ROWS:-16}"
    local columns gap cell_width segment_remainder column start end max_level level units full_units
    local height result='' i extra partial_units cells side_padding
    local peak_max_level peak_level peak_units peak_height current_top marker_row glyph
    local cache_key
    local -a levels=("${SPECTRUM_LEVELS[@]:-}")
    local -a peak_levels=("${SPECTRUM_PEAK_LEVELS[@]:-}")
    local -a partial=(' ' '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')

    [[ "$row" =~ ^[0-9]+$ && "$width" =~ ^[0-9]+$ ]] || return 1
    [[ "$display_rows" =~ ^[0-9]+$ && "$frame_rows" =~ ^[0-9]+$ ]] || return 1
    ((display_rows > 0 && frame_rows > 0 && row < display_rows && width > 0)) || return 1
    ((${#levels[@]} == 16)) || levels=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
    ((${#peak_levels[@]} == 16)) || peak_levels=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)

    cache_key="$width|$display_rows|$frame_rows|$UI_UNICODE|$UI_BAR_FULL|${levels[*]}|${peak_levels[*]}"
    if [[ "$cache_key" == "${UI_SPECTRUM_WIDE_CACHE_KEY:-}" && -n "${UI_SPECTRUM_TEXT_CACHE[row]+present}" ]]; then
        UI_SPECTRUM_ROW_TEXT=${UI_SPECTRUM_TEXT_CACHE[row]}
        [[ "${3:-}" == state ]] || printf '%s' "$UI_SPECTRUM_ROW_TEXT"
        return 0
    fi
    if [[ "$cache_key" != "${UI_SPECTRUM_WIDE_CACHE_KEY:-}" ]]; then
        UI_SPECTRUM_TEXT_CACHE=()
        gap=1
        columns=$(((width + 1) / 3))
        ((columns < 1)) && columns=1
        ((columns > 16)) && columns=16
        ((width < columns)) && columns=$width
        cell_width=$(((width - columns + 1) / columns))
        ((cell_width < 1)) && { cell_width=1; gap=0; }
        # Preparar cada glifo una vez por cuadro; antes se construía la misma
        # cadena para cada banda de cada fila (hasta 128 printf por cuadro).
        printf -v cells '%*s' "$cell_width" ''
        UI_SPECTRUM_CELLS=()
        for ((i=0; i<9; i++)); do
            glyph=${partial[i]}
            if ((i > 0 && !UI_UNICODE)); then glyph=$UI_BAR_FULL; fi
            UI_SPECTRUM_CELLS[i]=${cells// /$glyph}
        done
        UI_SPECTRUM_FULL_CELL=${cells// /$UI_BAR_FULL}
        if ((UI_UNICODE)); then glyph='▔'; else glyph='^'; fi
        UI_SPECTRUM_PEAK_CELL=${cells// /$glyph}
        segment_remainder=$((width - columns * cell_width - gap * (columns - 1)))
        # Las celdas extra se dejan como margen simétrico. Repartirlas desde la
        # primera columna hacía que las barras de la izquierda parecieran más
        # gruesas que las de la derecha.
        side_padding=$((segment_remainder / 2))
        UI_SPECTRUM_WIDE_LEVELS=()
        UI_SPECTRUM_WIDE_PEAKS=()
        for ((column = 0; column < columns; column++)); do
            start=$((column * 16 / columns))
            end=$(((column + 1) * 16 / columns))
            ((end <= start)) && end=$((start + 1))
            max_level=0
            peak_max_level=0
            for ((i = start; i < end && i < 16; i++)); do
                level="${levels[i]}"
                [[ "$level" =~ ^[0-9]+$ ]] || level=0
                ((level > max_level)) && max_level=$level
                peak_level="${peak_levels[i]}"
                [[ "$peak_level" =~ ^[0-9]+$ ]] || peak_level=0
                ((peak_level > peak_max_level)) && peak_max_level=$peak_level
            done
            UI_SPECTRUM_WIDE_LEVELS[column]=$max_level
            UI_SPECTRUM_WIDE_PEAKS[column]=$peak_max_level
            # Altura y pico dependen del cuadro, no de la fila que se dibuja.
            units=$((max_level * display_rows * 8 / frame_rows))
            full_units=$((units / 8))
            partial_units=$((units % 8))
            height=$((display_rows - full_units))
            current_top=$height
            ((max_level == 0)) && current_top=$display_rows
            ((partial_units > 0)) && current_top=$((height - 1))
            marker_row=-1
            if ((peak_max_level > max_level)); then
                peak_units=$((peak_max_level * display_rows * 8 / frame_rows))
                peak_height=$(((peak_units + 7) / 8))
                marker_row=$((display_rows - peak_height))
                ((marker_row >= current_top)) && marker_row=$((current_top - 1))
                ((marker_row < 0)) && marker_row=-1
            fi
            UI_SPECTRUM_WIDE_HEIGHTS[column]=$height
            UI_SPECTRUM_WIDE_PARTIALS[column]=$partial_units
            UI_SPECTRUM_WIDE_MARKERS[column]=$marker_row
        done
        UI_SPECTRUM_WIDE_COLUMNS=$columns
        UI_SPECTRUM_WIDE_GAP=$gap
        UI_SPECTRUM_WIDE_CELL_WIDTH=$cell_width
        UI_SPECTRUM_WIDE_SIDE_PADDING=$side_padding
        UI_SPECTRUM_WIDE_CACHE_KEY=$cache_key
    fi

    columns="${UI_SPECTRUM_WIDE_COLUMNS:-0}"
    gap="${UI_SPECTRUM_WIDE_GAP:-0}"
    cell_width="${UI_SPECTRUM_WIDE_CELL_WIDTH:-0}"
    side_padding="${UI_SPECTRUM_WIDE_SIDE_PADDING:-0}"
    ((columns > 0 && cell_width > 0)) || return 1
    if ((side_padding > 0)); then
        printf -v cells '%*s' "$side_padding" ''
        result+="$cells"
    fi

    for ((column = 0; column < columns; column++)); do
        height=${UI_SPECTRUM_WIDE_HEIGHTS[column]}
        partial_units=${UI_SPECTRUM_WIDE_PARTIALS[column]}
        marker_row=${UI_SPECTRUM_WIDE_MARKERS[column]}
        cells=${UI_SPECTRUM_CELLS[0]}
        if ((row >= height)); then
            cells=$UI_SPECTRUM_FULL_CELL
        elif ((partial_units > 0 && row == height - 1)); then
            cells=${UI_SPECTRUM_CELLS[partial_units]}
        fi
        if ((row == marker_row)); then
            cells=$UI_SPECTRUM_PEAK_CELL
        fi
        result+=$cells
        if ((gap && column < columns - 1)); then result+=' '; fi
    done

    extra=$((width - ${#result}))
    if ((extra > 0)); then printf -v cells '%*s' "$extra" ''; result+="$cells"; fi
    UI_SPECTRUM_ROW_TEXT="${result:0:width}"
    UI_SPECTRUM_TEXT_CACHE[row]=$UI_SPECTRUM_ROW_TEXT
    [[ "${3:-}" == state ]] || printf '%s' "$UI_SPECTRUM_ROW_TEXT"
    return 0
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
    UI_AUDIO_INFO=$output
    [[ "${1:-}" == state ]] || printf '%s' "$output"
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

ui_select_emisoras() {
    ui_navigation_refresh
    ((${#FAVORITE_NAMES[@]} > 0)) || {
        ui_set_message 'No tienes emisoras guardadas. Pulsa B para buscar una.' 5
        return 1
    }
    UI_SELECTED_INDEX=0
    ui_sync_selection
}

ui_select_recientes() {
    ui_navigation_refresh
    ((${#RECENT_NAMES[@]} > 0)) || {
        ui_set_message 'No hay emisoras recientes todavía.' 4
        return 1
    }
    UI_SELECTED_INDEX=${#FAVORITE_NAMES[@]}
    ui_sync_selection
}

ui_player_status() {
    if player_is_running; then
        if ((PLAYER_PAUSED)); then tr_ui ui.paused Pausado; elif ((PLAYER_BUFFERING)); then tr_ui ui.buffering Buffering; elif ((PLAYER_INFO_READY)); then tr_ui ui.playing Reproduciendo; else tr_ui ui.connecting Conectando; fi
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
    ui_box_rule "$width" "$UI_ML" "$UI_MR" "$(tr_ui ui.now_playing 'AHORA SUENA')" accent

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
        station=$(tr_ui ui.no_station_selected 'Ninguna emisora seleccionada')
        station_style='muted'
        favorite_badge=''
    fi

    if ((RECORDING_ACTIVE)); then recording_badge="[$UI_RECORD $(ui_recording_status_display)]"; else recording_badge=''; fi
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
        ui_audio_info state
        audio_info=$UI_AUDIO_INFO
        [[ -n "$audio_info" ]] && ui_box_line "$width" "  $audio_info" muted
    fi

    local volume_bar_width volume_left volume_hint
    volume_bar_width=$(ui_volume_bar_width "$width")
    volume_left="VOL $(printf '%3s' "$PLAYER_VOLUME")%  $(ui_volume_bar "$volume_bar_width")"
    volume_hint='A/D  ←/→'
    ui_box_split_line "$width" "$volume_left" "$volume_hint" 0 accent muted
    ui_box_rule "$width" "$UI_ML" "$UI_MR" "$(tr_ui ui.favorite_stations 'EMISORAS FAVORITAS') (${#FAVORITE_NAMES[@]})" accent

    local height
    height=$(ui_list_height)
    if ((${#FAVORITE_NAMES[@]} == 0)); then
        ui_box_line "$width" "  $(tr_ui ui.no_favorites_hint '(sin favoritos; pulsa B para buscar)')" muted
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
        ui_box_line "$width" 'F ir a Favoritas   X añadir/quitar actual   J/K reordenar' muted
        ui_box_line "$width" 'B buscar   G grabar   U actualizar   D diagnóstico   Q salir   H cerrar ayuda' muted
    else
        ui_box_line "$width" "↑↓ mover  $UI_SEP  Enter reproducir  $UI_SEP  B buscar  $UI_SEP  G grabar  $UI_SEP  D diag.  $UI_SEP  H ayuda  $UI_SEP  Q salir" muted
    fi

    if [[ -n "$UI_MESSAGE" ]]; then ui_box_line "$width" "$UI_MESSAGE"; else ui_box_line "$width" ''; fi
    ui_box_rule "$width" "$UI_BL" "$UI_BR"
    tput ed 2>/dev/null || true
}

# shellcheck source=lib/navigation.sh
source "$(dirname "${BASH_SOURCE[0]}")/navigation.sh"
