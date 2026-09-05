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
plain=$(ui_print_split_styled 20 '› Radio Test' '[PLAY]' selected playing)
[[ ${#plain} -eq 20 ]] || fail 'el render monocromo alteró la anchura de la fila'
[[ "$plain" == *'Radio Test'* && "$plain" == *'[PLAY]' ]] || fail 'el render monocromo perdió contenido'

[[ "$(ui_layout_width 54)" == '54' ]] || fail 'el layout estrecho cambió de ancho'
[[ "$(ui_layout_width 78)" == '78' ]] || fail 'el layout medio cambió de ancho'
[[ "$(ui_layout_width 120)" == '92' ]] || fail 'el layout ancho no respetó el máximo de 92 columnas'
[[ "$(ui_volume_bar_width 54)" == '12' ]] || fail 'la barra estrecha no usa 12 columnas'
[[ "$(ui_volume_bar_width 78)" == '28' ]] || fail 'la barra media no escala a 28 columnas'
[[ "$(ui_volume_bar_width 120)" == '28' ]] || fail 'la barra ancha superó su máximo'

rule=$(ui_box_rule 54 "$UI_ML" "$UI_MR" 'AHORA SUENA' accent)
[[ ${#rule} -eq 54 ]] || fail 'el separador etiquetado alteró la anchura del marco'
[[ "$rule" == *'AHORA SUENA'* ]] || fail 'el separador perdió la etiqueta AHORA SUENA'

badges=$(ui_print_badged_status 50 '▶ Rock FM' playing '[● REC 00:12]' '[★ FAVORITA]' '')
[[ ${#badges} -eq 50 ]] || fail 'los badges alteraron la anchura de la línea de estado'
[[ "$badges" == *'[● REC 00:12]'* && "$badges" == *'[★ FAVORITA]'* ]] || fail 'los badges perdieron contenido'

printf 'ok   tema y composición adaptable de la TUI\n'
