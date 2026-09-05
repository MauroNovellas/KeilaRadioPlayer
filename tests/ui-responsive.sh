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

assert_eq wide "$(ui_layout_mode 100 30)" 'modo wide'
assert_eq standard "$(ui_layout_mode 70 20)" 'modo standard'
assert_eq compact "$(ui_layout_mode 55 15)" 'modo compact'
assert_eq minimal "$(ui_layout_mode 45 12)" 'modo minimal'
assert_eq tiny "$(ui_layout_mode 40 10)" 'modo tiny'

UI_LAYOUT_MODE=wide
assert_eq 119 "$(ui_layout_width 120)" 'wide aprovecha todo el ancho útil de PC'
assert_eq 199 "$(ui_layout_width 200)" 'wide escala con terminales muy anchas'
assert_eq 79 "$(ui_layout_width 80)" 'wide conserva columna física de seguridad'
assert_eq 48 "$(ui_volume_bar_width 119)" 'wide amplía la barra de volumen con límite legible'
assert_eq 31 "$(ui_volume_bar_width 79)" 'wide adapta la barra en el umbral de escritorio'
UI_LAYOUT_MODE=standard
assert_eq 78 "$(ui_layout_width 90)" 'standard conserva ancho clásico'
assert_eq 69 "$(ui_layout_width 70)" 'standard evita autowrap al usar todo el terminal'
assert_eq 28 "$(ui_volume_bar_width 78)" 'standard conserva barra clásica'
UI_LAYOUT_MODE=compact
assert_eq 54 "$(ui_layout_width 55)" 'compact reserva una columna de seguridad'
UI_LAYOUT_MODE=minimal
assert_eq 44 "$(ui_layout_width 45)" 'minimal reserva una columna de seguridad'

# Las reglas intermedias deben avanzar de fila, pero el borde inferior no puede
# emitir un salto final: hacerlo cuando ocupa la última fila provoca scroll y
# deja restos del frame anterior en la parte superior de la terminal.
top_render="$(ui_box_rule 12 "$UI_TL" "$UI_TR"; printf 'X')"
[[ "$top_render" == *$'\nX' ]] || fail 'el borde superior dejó de avanzar de fila'
bottom_render="$(ui_box_rule 12 "$UI_BL" "$UI_BR"; printf 'X')"
[[ "$bottom_render" != *$'\nX' ]] || fail 'el borde inferior todavía provoca scroll vertical'

UI_HELP_VISIBLE=1
UI_LAYOUT_MODE=wide
assert_eq 4 "$(ui_control_line_count)" 'ayuda wide'
UI_LAYOUT_MODE=compact
assert_eq 2 "$(ui_control_line_count)" 'ayuda compact'
UI_LAYOUT_MODE=minimal
assert_eq 1 "$(ui_control_line_count)" 'ayuda minimal'
UI_HELP_VISIBLE=0

player_is_running() { return 0; }
PLAYER_STREAM_TITLE='Artista - Canción'
PLAYER_CODEC='aac'
PLAYER_BITRATE_KBPS=128
PLAYER_SAMPLE_RATE=44100
PLAYER_CHANNELS='stereo'

UI_LAYOUT_MODE=standard
assert_eq 2 "$(ui_stream_info_line_count)" 'standard conserva título y audio'
UI_LAYOUT_MODE=compact
assert_eq 1 "$(ui_stream_info_line_count)" 'compact conserva solo el título'
UI_LAYOUT_MODE=minimal
assert_eq 0 "$(ui_stream_info_line_count)" 'minimal oculta metadatos secundarios'

UI_LAYOUT_MODE=compact
UI_LINES=13
assert_eq 2 "$(ui_list_height)" 'compact mantiene dos favoritos visibles en su mínimo'
UI_LAYOUT_MODE=minimal
UI_LINES=11
assert_eq 1 "$(ui_list_height)" 'minimal mantiene un favorito visible'

recording_elapsed_display() { printf '00:42'; }
UI_LAYOUT_MODE=compact
ui_responsive_badges '[● REC 00:42]' '[★ FAVORITA]' ''
assert_eq '[● 00:42]' "$UI_RESP_RECORDING" 'compact acorta REC'
assert_eq '[★]' "$UI_RESP_FAVORITE" 'compact acorta favorito'
UI_LAYOUT_MODE=minimal
ui_responsive_badges '[● REC 00:42]' '[★ FAVORITA]' '[PAUSA]'
assert_eq '' "$UI_RESP_RECORDING" 'minimal prioriza estado sobre REC'
assert_eq '[PAUSA]' "$UI_RESP_STATE" 'minimal conserva el estado prioritario'

printf 'ok   composición TUI responsive, ancho completo y scroll seguros\n'
