#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail

ROOT_DIR=$1
gate_fd=$2

ui_enter() { :; }
ui_suspend() { :; }
ui_resume() { :; }
ui_leave() { :; }
ui_move_selection() { :; }
player_change_volume() { :; }
logo_hide() { :; }
logo_forget() { :; }

source "$ROOT_DIR/lib/input.sh"
source "$ROOT_DIR/lib/app-search.sh"
source "$ROOT_DIR/lib/ui-terminal-guard.sh"
source "$ROOT_DIR/lib/station-logo.sh"

# Selección real bajo PTY: foot no depende de Unicode y Kitty sigue separado.
unset TERMUX_VERSION KITTY_WINDOW_ID TMUX STY VTE_VERSION
PREFIX='' UI_COLOR=1 UI_UNICODE=0 TERM=foot COLORTERM=truecolor
logo_choose_backend
[[ $LOGO_BACKEND == sixel ]] || exit 1
TERM=foot-direct
logo_choose_backend
[[ $LOGO_BACKEND == sixel ]] || exit 1
TERM=xterm-kitty KITTY_WINDOW_ID=1
logo_choose_backend
[[ $LOGO_BACKEND == kitty ]] || exit 1
TERM=foot TMUX=test UI_UNICODE=1
logo_choose_backend
[[ $LOGO_BACKEND == blocks ]] || exit 1
unset TMUX
TERMUX_VERSION=test
logo_choose_backend
[[ $LOGO_BACKEND == initials ]] || exit 1
unset TERMUX_VERSION
TERM=xterm-256color

wait_gate() {
    # Esperar en un pipe, no en el TTY: reproduce el intervalo entre lecturas
    # durante el filtrado/repintado sin depender de sleeps o carreras de tiempo.
    local reply
    printf 'WAIT:%s\n' "$1"
    IFS= read -r -t 5 -u "$gate_fd" reply && [[ $reply == go ]]
}

next_event() {
    local attempt
    for ((attempt = 0; attempt < 150; attempt++)); do
        input_read || return 1
        [[ $INPUT_EVENT == TICK ]] || return 0
    done
    printf 'FAIL no llega el evento de teclado\n' >&2
    return 1
}

edit_event() {
    next_event && [[ $INPUT_EVENT == KEY ]] && search_handle_key "$INPUT_KEY"
}

input_init
SEARCH_ACTIVE=1 SEARCH_QUERY='rocká'
before=$(stty -g) || exit 1
ui_enter || exit 1

wait_gate enter && edit_event || exit 1
printf 'QUERY:%s\n' "$SEARCH_QUERY"
wait_gate erase-del && edit_event || exit 1
printf 'QUERY:%s\n' "$SEARCH_QUERY"
wait_gate erase-bs && edit_event || exit 1
printf 'QUERY:%s\n' "$SEARCH_QUERY"

wait_gate mixed-burst || exit 1
while next_event; do
    [[ $INPUT_EVENT != ENTER ]] || break
    [[ $INPUT_EVENT == KEY ]] && search_handle_key "$INPUT_KEY" || exit 1
done
[[ $INPUT_EVENT == ENTER ]] || exit 1
printf 'QUERY:%s\n' "$SEARCH_QUERY"

wait_gate delete && next_event && [[ $INPUT_EVENT == DELETE ]] && search_clear || exit 1
printf 'QUERY:%s\n' "$SEARCH_QUERY"
wait_gate cursor && next_event && [[ $INPUT_EVENT == DOWN ]] || exit 1
wait_gate geometry && edit_event || exit 1
[[ $INPUT_CELL_HEIGHT == 16 && $INPUT_CELL_WIDTH == 8 ]] || exit 1
printf 'QUERY:%s\n' "$SEARCH_QUERY"
wait_gate geometry-erase && edit_event || exit 1
printf 'QUERY:%s\n' "$SEARCH_QUERY"

ui_suspend || exit 1
[[ $(stty -g) == "$before" ]] || exit 1
wait_gate suspended || exit 1
ui_resume || exit 1
SEARCH_QUERY='ñ'
wait_gate resumed && edit_event || exit 1
printf 'QUERY:%s\n' "$SEARCH_QUERY"

ui_leave || exit 1
[[ $(stty -g) == "$before" ]] || exit 1
input_shutdown
printf 'DONE\n'
