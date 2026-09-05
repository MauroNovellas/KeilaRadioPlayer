#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/ui-responsive.sh"
source "$ROOT_DIR/lib/ui-safe-width.sh"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

UI_LAYOUT_MODE=wide
ui_desktop_enabled 112 20 wide || fail 'desktop no se activa en su mínimo'
if ui_desktop_enabled 111 20 wide; then fail 'desktop se activa con poco ancho'; fi
if ui_desktop_enabled 140 19 wide; then fail 'desktop se activa con poca altura'; fi
if ui_desktop_enabled 140 30 standard; then fail 'desktop ignora el modo responsive'; fi

declare -F ui_draw_single_column >/dev/null || fail 'falta fallback de una columna'
declare -F ui_draw_desktop >/dev/null || fail 'falta render desktop'

ui_desktop_pane_widths 119
assert_eq 119 "$((UI_DESKTOP_LEFT_WIDTH + UI_DESKTOP_RIGHT_WIDTH + 7))" 'geometría desktop 119'
assert_eq 47 "$UI_DESKTOP_LEFT_WIDTH" 'ahora suena queda contenido en desktop normal'
assert_eq 65 "$UI_DESKTOP_RIGHT_WIDTH" 'favoritos domina en desktop normal'
((UI_DESKTOP_RIGHT_WIDTH > UI_DESKTOP_LEFT_WIDTH)) || fail 'favoritos no es el panel dominante'

ui_desktop_pane_widths 159
assert_eq 159 "$((UI_DESKTOP_LEFT_WIDTH + UI_DESKTOP_RIGHT_WIDTH + 7))" 'geometría desktop 159'
assert_eq 52 "$UI_DESKTOP_LEFT_WIDTH" 'ahora suena deja de crecer en ultrawide'
assert_eq 100 "$UI_DESKTOP_RIGHT_WIDTH" 'favoritos absorbe el ancho ultrawide'
((UI_DESKTOP_RIGHT_WIDTH > UI_DESKTOP_LEFT_WIDTH)) || fail 'favoritos no domina en ultrawide'

UI_UNICODE=0
ui_configure_glyphs
UI_COLOR=0
ui_desktop_pane_widths 119
header=$(ui_desktop_header_rule 119 'AHORA SUENA' 'FAVORITOS (8)')
first_line=${header%%$'\n'*}
assert_eq 119 "${#first_line}" 'cabecera desktop respeta ancho exacto'

PLAYER_PAUSED=0
PLAYER_BUFFERING=0
player_is_running() { return 0; }
assert_eq playing "$(ui_desktop_player_state_style)" 'estado reproduciendo'
PLAYER_PAUSED=1
assert_eq warning "$(ui_desktop_player_state_style)" 'estado pausado'
player_is_running() { return 1; }
assert_eq muted "$(ui_desktop_player_state_style)" 'estado detenido'

UI_HELP_VISIBLE=0
UI_LINES=20
assert_eq 13 "$(ui_desktop_body_height)" 'desktop llena altura mínima sin scroll'
UI_HELP_VISIBLE=1
assert_eq 10 "$(ui_desktop_body_height)" 'ayuda conserva altura del frame'

printf 'ok   TUI desktop: ahora suena contenido, favoritos dominante\n'
