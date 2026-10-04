#!/usr/bin/env bash

# Mantiene el terminal sin eco y no canónico durante toda la vida activa de la
# TUI. `read -sn1` cambia estos modos solo mientras lee y después los restaura.
# Si entre lecturas vuelve ICANON, el terminal absorbe Retroceso (VERASE) antes
# de que input_read lo reciba: escribir funciona, pero borrar parece lento.
# No usamos modo raw: las señales, incluido Ctrl-C, conservan su configuración.
# Guardamos el estado exacto para restaurarlo al suspender o salir.

UI_TTY_STATE=''
UI_TTY_GUARD_ACTIVE=0

ui_terminal_guard_capture() {
    [[ -t 0 ]] || return 1
    command -v stty >/dev/null 2>&1 || return 1

    if [[ -z "$UI_TTY_STATE" ]]; then
        UI_TTY_STATE=$(stty -g 2>/dev/null) || return 1
        [[ -n "$UI_TTY_STATE" ]] || return 1
    fi
}

ui_terminal_guard_enable() {
    ui_terminal_guard_capture || return 1
    stty -echo -icanon min 1 time 0 2>/dev/null || return 1
    UI_TTY_GUARD_ACTIVE=1
}

ui_terminal_guard_restore() {
    ((UI_TTY_GUARD_ACTIVE)) || return 0

    local status=0
    if [[ -n "$UI_TTY_STATE" ]]; then
        stty "$UI_TTY_STATE" 2>/dev/null || status=1
    fi
    UI_TTY_GUARD_ACTIVE=0
    return "$status"
}

# Envolvemos las versiones finales de estos helpers (incluido el hook del
# chequeo de actualizaciones). Esta capa debe cargarse al final de ui-safe-width.
if ! declare -F ui_enter_without_terminal_guard >/dev/null 2>&1; then
    UI_TERMINAL_GUARD_DEF=$(declare -f ui_enter)
    UI_TERMINAL_GUARD_DEF=${UI_TERMINAL_GUARD_DEF/ui_enter ()/ui_enter_without_terminal_guard ()}
    eval "$UI_TERMINAL_GUARD_DEF"

    UI_TERMINAL_GUARD_DEF=$(declare -f ui_suspend)
    UI_TERMINAL_GUARD_DEF=${UI_TERMINAL_GUARD_DEF/ui_suspend ()/ui_suspend_without_terminal_guard ()}
    eval "$UI_TERMINAL_GUARD_DEF"

    UI_TERMINAL_GUARD_DEF=$(declare -f ui_resume)
    UI_TERMINAL_GUARD_DEF=${UI_TERMINAL_GUARD_DEF/ui_resume ()/ui_resume_without_terminal_guard ()}
    eval "$UI_TERMINAL_GUARD_DEF"

    UI_TERMINAL_GUARD_DEF=$(declare -f ui_leave)
    UI_TERMINAL_GUARD_DEF=${UI_TERMINAL_GUARD_DEF/ui_leave ()/ui_leave_without_terminal_guard ()}
    eval "$UI_TERMINAL_GUARD_DEF"
    unset UI_TERMINAL_GUARD_DEF
fi

ui_enter() {
    ui_enter_without_terminal_guard || return $?
    ui_terminal_guard_enable >/dev/null 2>&1 || true
}

ui_suspend() {
    logo_hide
    ui_terminal_guard_restore >/dev/null 2>&1 || true
    ui_suspend_without_terminal_guard
}

ui_resume() {
    ui_resume_without_terminal_guard || return $?
    ui_terminal_guard_enable >/dev/null 2>&1 || true
}

ui_leave() {
    logo_forget
    # Restauramos primero: incluso si algún escape de terminal fallase después,
    # el shell del usuario no debe quedarse jamás sin eco.
    ui_terminal_guard_restore >/dev/null 2>&1 || true
    ui_leave_without_terminal_guard
}

# input.sh agrupa las repeticiones que ya estaban esperando en el buffer. Estas
# tres acciones son las únicas que deben aprovechar el contador agrupado. Al
# aplicar varios pasos en una sola operación evitamos un redibujado por byte y,
# sobre todo, eliminamos la larga "cola" visible después de soltar una tecla.
ui_input_repeat_count() {
    local count="${INPUT_REPEAT_COUNT:-1}"
    [[ "$count" =~ ^[0-9]+$ ]] || count=1
    ((count < 1)) && count=1
    ((count > 8)) && count=8
    UI_INPUT_REPEAT_COUNT=$count
    [[ ${1:-} == state ]] || printf '%s\n' "$count"
    return 0
}

if ! declare -F ui_move_selection_without_input_repeat >/dev/null 2>&1; then
    UI_INPUT_REPEAT_DEF=$(declare -f ui_move_selection)
    UI_INPUT_REPEAT_DEF=${UI_INPUT_REPEAT_DEF/ui_move_selection ()/ui_move_selection_without_input_repeat ()}
    eval "$UI_INPUT_REPEAT_DEF"

    UI_INPUT_REPEAT_DEF=$(declare -f player_change_volume)
    UI_INPUT_REPEAT_DEF=${UI_INPUT_REPEAT_DEF/player_change_volume ()/player_change_volume_without_input_repeat ()}
    eval "$UI_INPUT_REPEAT_DEF"

    UI_INPUT_REPEAT_DEF=$(declare -f search_move)
    UI_INPUT_REPEAT_DEF=${UI_INPUT_REPEAT_DEF/search_move ()/search_move_without_input_repeat ()}
    eval "$UI_INPUT_REPEAT_DEF"
    unset UI_INPUT_REPEAT_DEF
fi

ui_move_selection() {
    local delta="$1"
    local repeat
    ui_input_repeat_count state
    repeat=$UI_INPUT_REPEAT_COUNT
    ui_move_selection_without_input_repeat "$((delta * repeat))"
}

player_change_volume() {
    local delta="$1"
    local repeat
    ui_input_repeat_count state
    repeat=$UI_INPUT_REPEAT_COUNT
    player_change_volume_without_input_repeat "$((delta * repeat))"
}

search_move() {
    local delta="$1"
    local repeat
    ui_input_repeat_count state
    repeat=$UI_INPUT_REPEAT_COUNT
    search_move_without_input_repeat "$((delta * repeat))"
}
