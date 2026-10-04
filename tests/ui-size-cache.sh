#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/lib/input.sh"
source "$ROOT_DIR/lib/ui.sh"
task_tmp=$(mktemp -d) || exit 1
trap 'input_shutdown; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
terminal_cols=132 terminal_lines=40 terminal_invalid=0 resize_during_query=0
tput() {
    case $1 in
        cols|lines)
            printf '%s\n' "$1" >> "$task_tmp/calls"
            if [[ $1 == cols ]] && ((resize_during_query)); then kill -WINCH "$$"; fi
            ((terminal_invalid == 0)) || { printf 'invalid\n'; return 1; }
            if [[ $1 == cols ]]; then printf '%s\n' "$terminal_cols"; else printf '%s\n' "$terminal_lines"; fi ;;
    esac
}
TERM=xterm-256color
input_init
ui_refresh_size
[[ $UI_COLS == 132 && $UI_LINES == 40 ]] || fail 'primer tamaño incorrecto'
# Test sin depender de caer en el mismo segundo del reloj: la condición de hit
# es exactamente la que usa producción tras una consulta en ese segundo.
for ((index=0; index<100; index++)); do
    UI_SIZE_CHECK_AT=$((EPOCHSECONDS+1))
    ui_refresh_size
done
mapfile -t calls < "$task_tmp/calls"
((${#calls[@]} == 2)) || fail 'cada dibujo vuelve a invocar tput'

terminal_cols=40 terminal_lines=10
kill -WINCH "$$"
input_emit_resize_if_pending || fail 'no entrega resize'
[[ $INPUT_RESIZE_PENDING == 0 && $INPUT_EVENT == RESIZE ]] || fail 'evento resize no consumido'
ui_refresh_size
[[ $UI_COLS == 40 && $UI_LINES == 10 ]] || fail 'resize consumido conserva tamaño antiguo'
mapfile -t calls < "$task_tmp/calls"
((${#calls[@]} == 4)) || fail 'resize no invalida en el mismo segundo'

# Comprobación periódica sin WINCH y recuperación frente a errores de tput.
terminal_cols=80 terminal_lines=24 UI_SIZE_CHECK_AT=0
ui_refresh_size
[[ $UI_COLS == 80 && $UI_LINES == 24 ]] || fail 'no revisa tamaño sin señal'
terminal_cols=82 UI_SIZE_CHECK_AT=$((EPOCHSECONDS+3600))
ui_refresh_size
[[ $UI_COLS == 82 ]] || fail 'retraso del reloj prolonga la caché'
terminal_invalid=1 UI_SIZE_CHECK_AT=0
ui_refresh_size
[[ $UI_COLS == 80 && $UI_LINES == 24 ]] || fail 'fallback inválido'
terminal_invalid=0 terminal_cols=120 terminal_lines=30
kill -WINCH "$$"
input_emit_resize_if_pending || fail 'segundo resize'
ui_refresh_size
[[ $UI_COLS == 120 && $UI_LINES == 30 ]] || fail 'no recupera tamaño tras error'

terminal_cols=112 TERM=screen-256color
ui_refresh_size
[[ $UI_COLS == 112 ]] || fail 'cambio de terminal no invalida'
terminal_cols=100 UI_COLS=90
ui_refresh_size
[[ $UI_COLS == 100 ]] || fail 'tamaño sobrescrito se confunde con hit'
# Reanudar/entrar fuerza revisión, incluso dentro de la misma ventana temporal.
UI_ACTIVE=1 UI_SUSPENDED=1 terminal_cols=96
ui_resume
ui_refresh_size
[[ $UI_COLS == 96 ]] || fail 'resume conserva tamaño anterior'
UI_ACTIVE=0 terminal_cols=92
ui_enter
ui_refresh_size
[[ $UI_COLS == 92 ]] || fail 'enter conserva tamaño anterior'
terminal_cols=88 UI_SIZE_CHECK_AT=0 resize_during_query=1
ui_refresh_size
terminal_cols=84 resize_during_query=0
ui_refresh_size
[[ $UI_COLS == 84 ]] || fail 'WINCH durante tput se pierde'
printf 'ok   tamaño reutilizado y resize/resume inmediato\n'
