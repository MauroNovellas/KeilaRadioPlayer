#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
FAVORITE_NAMES=('Radio de nombre muy largo para comprobar la selección estable')
FAVORITE_URLS=('https://example.invalid/radio')
PLAYER_PID='' PLAYER_PAUSED=0 PLAYER_MUTED=0 PLAYER_VOLUME=50
PLAYER_NAME=$'Radio | Nombre muy largo\ncon salto\tde línea'
UI_COLOR=0 UI_MESSAGE=''
ui_refresh_size() { :; }
tput() { :; }

check_frame() {
    local frame=$1 label=$2 count=0 line
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((count += 1))
        ((${#line} < UI_COLS)) || fail "$label desborda horizontalmente: ${#line}/$UI_COLS"
    done <<< "$frame"
    ((count == UI_LINES)) || fail "$label cambia de altura: $count/$UI_LINES"
    [[ "$frame" != *$'\033'* && "$frame" != *$'\t'* ]] || fail "$label contiene controles sin limpiar"
}

for geometry in '160 45' '100 24' '97 16' '96 16' '80 24' '62 16' '50 13' '42 11' '40 10' '30 8' '20 6' '8 5' '2 1'; do
    read -r UI_COLS UI_LINES <<< "$geometry"
    for unicode in 0 1; do
        UI_UNICODE=$unicode
        ui_configure_glyphs
        for menu in main playback stations visual timer recordings session config data; do
            options_build_rows "$menu"
            for selected in 0 "$((${#OPTIONS_ROWS[@]} - 1))"; do
                OPTIONS_SELECTED=$selected OPTIONS_SCROLL=0
                frame=$(options_draw)
                check_frame "$frame" "$menu ${UI_COLS}x${UI_LINES}"
                if ((UI_LINES >= 6 && UI_COLS >= 20)); then
                    [[ "$frame" == *'> ['* ]] || fail "selección invisible en $menu $geometry"
                    [[ "$frame" == *'Esc volver'* ]] || fail "salida invisible en $menu $geometry"
                fi
            done
        done
    done
done

# Encoger y volver a ampliar mantiene la opción seleccionada y rellena huecos.
UI_COLS=40 UI_LINES=10 OPTIONS_SELECTED=8 OPTIONS_SCROLL=0
options_build_rows main
options_draw >/dev/null
((OPTIONS_SCROLL > 0)) || fail 'no hace scroll en pantalla pequeña'
UI_COLS=140 UI_LINES=32
options_draw >/dev/null
((OPTIONS_SELECTED == 8 && OPTIONS_SCROLL == 0)) || fail 'resize pierde selección o mantiene huecos'

# Detalle completo y desplazable para rutas y nombres largos en tiny.
UI_COLS=30 UI_LINES=8 OPTIONS_DETAIL_SCROLL=0 OPTIONS_SELECTED=0
SESSION_LOG_FILE='/ruta/muy/larga/con/varios/directorios/registro-de-esta-sesion.txt'
options_build_rows session
frame=$(options_detail_draw)
check_frame "$frame" 'detalle tiny'
options_detail_draw >/dev/null
OPTIONS_DETAIL_SCROLL=${#OPTIONS_DETAIL_LINES[@]}
frame=$(options_detail_draw)
check_frame "$frame" 'fin detalle tiny'
[[ "$frame" == *'.txt.'* ]] || fail 'no se puede leer el final de una ruta larga'

# Caracteres que ocupan dos celdas y acentos combinantes en los nombres.
options_fit_text '日本語放送' 8
[[ "$OPTIONS_FITTED" == '日本...' && "$OPTIONS_FITTED_WIDTH" == 7 ]] || fail 'trunca CJK como si ocupase una celda'
options_fit_text $'Cafe\u0301' 4
[[ "$OPTIONS_FITTED" == $'Cafe\u0301' && "$OPTIONS_FITTED_WIDTH" == 4 ]] || fail 'el acento combinante cambia la anchura'
options_fit_text '🎵🎵🎵🎵' 6
[[ "$OPTIONS_FITTED_WIDTH" -le 6 ]] || fail 'los emoji desbordan el ancho'

printf 'ok   opciones: 13 geometrías, ASCII/Unicode, selección, resize y detalle largo\n'
