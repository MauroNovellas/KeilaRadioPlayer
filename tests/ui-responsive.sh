#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/ui-responsive.sh"

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
assert_eq 92 "$(ui_layout_width 120)" 'wide limita el ancho máximo'
UI_LAYOUT_MODE=standard
assert_eq 78 "$(ui_layout_width 90)" 'standard conserva ancho clásico'
UI_LAYOUT_MODE=compact
assert_eq 55 "$(ui_layout_width 55)" 'compact usa todo el ancho disponible'

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

printf 'ok   composición TUI responsive\n'
