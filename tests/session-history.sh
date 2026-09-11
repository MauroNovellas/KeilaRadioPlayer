#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
export HOME="$task_tmp/home" XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"

source "$ROOT_DIR/lib/version.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/session-log.sh"
source "$ROOT_DIR/lib/session-history.sh"

fail() {
    printf 'FAIL %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

tput() { :; }
ui_refresh_size() { :; }
UI_COLS=100
UI_LINES=12
UI_COLOR=0
UI_UNICODE=1
ui_configure_glyphs

mkdir -p "$HOME"
keila_init_paths || fail paths
session_log_init || fail init
session_log_station 'Rock FM' 'https://radio.invalid/rock'
session_log_title 'Rock FM' 'https://radio.invalid/rock' 'Tema Uno'
session_log_title 'Rock FM' 'https://radio.invalid/rock' 'Tema Dos'

session_history_load || fail 'no carga historial'
assert_eq 3 "${#SESSION_HISTORY_ROWS[@]}" 'filas cargadas'
row=$(session_history_row_text 100 "${SESSION_HISTORY_ROWS[2]}")
[[ "$row" == *'Rock FM'* && "$row" == *'Tema Dos'* ]] || fail 'fila ancha incompleta'
row=$(session_history_row_text 50 "${SESSION_HISTORY_ROWS[1]}")
[[ "$row" == *'Rock FM'* && "$row" == *'Tema Uno'* ]] || fail 'fila estrecha incompleta'

output=$(session_history_draw)
[[ "$output" == *'KEILA · HISTORIAL DE SESIÓN'* ]] || fail 'título de pantalla'
[[ "$output" == *'Archivo:'* && "$output" == *'keila-session-'* ]] || fail 'ruta visible'
[[ "$output" == *'Tema Dos'* && "$output" == *'3 entradas'* ]] || fail 'contenido visible'

SESSION_HISTORY_SCROLL=999
session_history_clamp_scroll 2
assert_eq 1 "$SESSION_HISTORY_SCROLL" 'scroll se limita al final'
SESSION_HISTORY_SCROLL=-5
session_history_clamp_scroll 2
assert_eq 0 "$SESSION_HISTORY_SCROLL" 'scroll se limita al inicio'

printf 'ok   historial de sesión: carga, render y scroll\n'
