#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/ui.sh"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

KEILA_NO_COLOR=1
unset NO_COLOR
ui_configure_theme
((UI_COLOR == 0)) || fail 'KEILA_NO_COLOR=1 no desactivó colores'
[[ -z "$(ui_style_begin playing)" ]] || fail 'el estilo emitió ANSI con KEILA_NO_COLOR=1'

unset KEILA_NO_COLOR
NO_COLOR=1
ui_configure_theme
((UI_COLOR == 0)) || fail 'NO_COLOR no desactivó colores'
[[ -z "$(ui_style_begin record)" ]] || fail 'el estilo emitió ANSI con NO_COLOR'

KEILA_NO_COLOR=1
unset NO_COLOR
ui_configure_theme
plain=$(ui_print_split_styled 20 '› Radio Test' 'PLAY' selected playing)
[[ ${#plain} -eq 20 ]] || fail 'el render monocromo alteró la anchura de la fila'
[[ "$plain" == *'Radio Test'* && "$plain" == *'PLAY' ]] || fail 'el render monocromo perdió contenido'

printf 'ok   tema TUI y fallback monocromo\n'
