#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ui_refresh_size() { :; }
tput() { :; }
player_is_running() { return 0; }
TERM=xterm-256color
unset TERMUX_VERSION PREFIX
UI_ACTIVE=1 UI_SUSPENDED=0 UI_COLOR=0 UI_UNICODE=1 UI_HELP_VISIBLE=0
PLAYER_PID=123 PLAYER_NAME='Rock FM' PLAYER_URL=https://radio.invalid/stream
PLAYER_STREAM_TITLE='Nombre de canción muy largo que no debe invadir el logo'
FAVORITE_NAMES=('Radio test') FAVORITE_URLS=(https://test.invalid/)
HISTORY_NAMES=() HISTORY_URLS=() RECENT_NAMES=() RECENT_URLS=()
SEARCH_NAMES=() SEARCH_URLS=() SEARCH_MATCHES=()
TRACK_HISTORY_TITLES=('Tema actual' 'Tema anterior con un nombre muy largo para probar')
TRACK_HISTORY_TIMES=('12:00' '11:59')
PREF_LOGO=1
ui_configure_glyphs
for geometry in '160 40' '132 30' '120 24' '119 24' '120 23' '80 24' '40 10'; do
    read -r UI_COLS UI_LINES <<< "$geometry"
    frame=$(ui_draw)
    count=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        count=$((count+1))
        # tiny mantiene la compatibilidad de la vista de emergencia: puede
        # ocupar la última celda, aunque el layout normal deja una guarda.
        if ((UI_COLS <= 40)); then
            ((${#line} <= UI_COLS)) || fail "desborda $geometry: ${#line}"
        else
            ((${#line} < UI_COLS)) || fail "desborda $geometry: ${#line}"
        fi
    done <<< "$frame"
    ((count <= UI_LINES)) || fail "alto $geometry"
    if ((UI_COLS >= 120 && UI_LINES >= 24)); then
        [[ "$frame" == *'[RF]'* ]] || fail "no reserva logo $geometry"
    else [[ "$frame" != *'[RF]'* ]] || fail "logo en pantalla pequeña $geometry"; fi
done
UI_COLS=132 UI_LINES=30 TERMUX_VERSION=0.118
[[ $(ui_draw) != *'[RF]'* ]] || fail 'altera Termux'
unset TERMUX_VERSION
UI_UNICODE=0; ui_configure_glyphs
PREF_LOGO=0; before=$(ui_draw)
PREF_LOGO=1; after=$(ui_draw)
# ASCII conserva exactamente los anchos/alturas del layout previo.
mapfile -t before_lines <<< "$before"; mapfile -t after_lines <<< "$after"
(( ${#before_lines[@]} == ${#after_lines[@]} )) || fail 'altura ASCII distinta'
for i in "${!before_lines[@]}"; do (( ${#before_lines[i]} == ${#after_lines[i]} )) || fail 'ancho ASCII distinto'; done
UI_UNICODE=1; ui_configure_glyphs
PREF_LOGO=0
[[ $(ui_draw) != *'[RF]'* ]] || fail 'no oculta opción desactivada'
PREF_LOGO=1
ui_draw >/dev/null
[[ $UI_LOGO_LAYOUT == 1 ]] || fail 'layout no queda publicado'
logo_line_width 1; ((UI_PLAYER_LINE_WIDTH == UI_DESKTOP_LEFT_WIDTH-14)) || fail 'ancho del título'
logo_line_width 5; ((UI_PLAYER_LINE_WIDTH == UI_DESKTOP_LEFT_WIDTH-14)) || fail 'ancho del historial junto al logo'
logo_line_width 6; ((UI_PLAYER_LINE_WIDTH == UI_DESKTOP_LEFT_WIDTH)) || fail 'estrecha filas fuera del logo'
# Ningún dato del servidor puede llegar al terminal como escapes arbitrarios.
LOGO_PIXELS_HEX=$(printf '%0864d' 0)
LOGO_PIXELS_BASE64=$(printf '%036864d' 0); LOGO_PIXELS_BASE64=${LOGO_PIXELS_BASE64//0/A}
logo_build_rows
(( ${#LOGO_ROWS[@]} == 6 )) || fail 'filas de bloques'
LOGO_BACKEND=blocks LOGO_READY_URL=$PLAYER_URL
slot=$(logo_print_slot 0)
[[ $slot == *$'\033[38;2;0;0;0m'* ]] || fail 'bloques sin colores'
PLAYER_URL=https://otra.invalid/
[[ $(logo_print_slot 0) != *$'\033'* ]] || fail 'logo viejo al cambiar emisora'
PLAYER_URL=$LOGO_READY_URL
# Protocolo Kitty acotado, sin consultas que roben teclas y borrado por ID propio.
LOGO_BACKEND=kitty LOGO_GENERATION=1 LOGO_UPLOADED=-1 PREFERENCES_ACTIVE=0
output=$(logo_draw)
[[ $output == *'a=t,f=24,s=96,v=96'* && $output == *'p=1,c=12,r=6,C=1,q=2'* ]] || fail 'protocolo Kitty'
[[ $output != *'a=q'* ]] || fail 'consulta roba entrada'
LOGO_UPLOADED=1
[[ $(logo_draw) != *'a=t,'* ]] || fail 'reenvía píxeles en cada frame'
LOGO_DRAWN=1
hidden=$(logo_hide)
[[ "$hidden" == *"d=i,i=$LOGO_IMAGE_ID,p=1,q=2"* ]] || fail 'ocultación no limita la colocación'
LOGO_DRAWN=0
redraw=$(logo_draw)
[[ "$redraw" != *'a=t,'* && "$redraw" == *"a=p,i=$LOGO_IMAGE_ID,p=1,c=12,r=6,C=1,q=2"* ]] || fail 'el logo no sobrevive al redibujado'
LOGO_DRAWN=0 LOGO_UPLOADED=-1
printf 'ok   logos UI: espacio fijo, pantallas pequeñas, Termux, bloques y protocolo Kitty\n'
