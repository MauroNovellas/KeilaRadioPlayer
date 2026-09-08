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

player_is_running() { return 1; }
history_recent_refresh() { :; }

UI_UNICODE=1
UI_COLOR=0
UI_HELP_VISIBLE=0
UI_LINES=20
UI_LAYOUT_MODE=wide
ui_configure_glyphs
ui_desktop_pane_widths 119

FAVORITE_NAMES=(F1 F2 F3 F4 F5 F6 F7 F8)
FAVORITE_URLS=(u1 u2 u3 u4 u5 u6 u7 u8)
UI_SELECTED_INDEX=7
UI_SCROLL_OFFSET=0

SEARCH_NAMES=('Rock FM' 'Classic Rock' R3 R4 R5 R6 R7 R8 R9 R10)
SEARCH_AMBITS=(Madrid Barcelona A3 A4 A5 A6 A7 A8 A9 A10)
SEARCH_COUNTRIES=(España España ES ES ES ES ES ES ES ES)
SEARCH_FORMATS=(AAC MP3 AAC AAC AAC AAC AAC AAC AAC AAC)
SEARCH_URLS=(s1 s2 s3 s4 s5 s6 s7 s8 s9 s10)
SEARCH_MATCHES=(0 1 2 3 4 5 6 7 8 9)
SEARCH_SELECTED_INDEX=8
SEARCH_SCROLL_OFFSET=0
SEARCH_QUERY=''
SEARCH_FILTER_DIRTY=0
SEARCH_ACTIVE=0
PLAYER_URL='none'

ui_desktop_sync_selection 13
assert_eq 6 "$UI_DESKTOP_FAVORITES_HEIGHT" 'mitad superior de favoritos'
assert_eq 5 "$UI_DESKTOP_SEARCH_HEIGHT" 'mitad inferior de búsqueda'
assert_eq 3 "$UI_SCROLL_OFFSET" 'favoritos hacen scroll dentro de su mitad'
assert_eq 5 "$SEARCH_SCROLL_OFFSET" 'búsqueda hace scroll dentro de su mitad'

favorites_header=$(ui_desktop_header_rule 119 'AHORA SUENA' "FAVORITOS (${#FAVORITE_NAMES[@]})")
[[ "$favorites_header" == *"$UI_SELECT FAVORITOS"* ]] || fail 'Favoritos activo no muestra indicador de foco'

UI_UPDATE_DESKTOP_ROW=6
separator=$(ui_desktop_row '' '' '' '' 'favorito que debe desaparecer' '' '' '' 0)
[[ "$separator" == *'[B] BUSQUEDA EMISORAS'* ]] || fail 'falta cabecera de búsqueda en la línea divisoria'
[[ "$separator" != *'favorito que debe desaparecer'* ]] || fail 'el separador no sustituyó la fila de favoritos'

SEARCH_ACTIVE=1
SEARCH_QUERY='rock'
SEARCH_FILTER_DIRTY=0
SEARCH_MATCHES=(0 1)
SEARCH_SELECTED_INDEX=0
SEARCH_SCROLL_OFFSET=0

search_header=$(ui_desktop_header_rule 119 'AHORA SUENA' "FAVORITOS (${#FAVORITE_NAMES[@]})")
[[ "$search_header" != *"$UI_SELECT FAVORITOS"* ]] || fail 'Favoritos conserva el indicador al entrar en búsqueda'

UI_UPDATE_DESKTOP_ROW=6
active_separator=$(ui_desktop_row '' '' '' '' '' '' '' '' 0)
[[ "$active_separator" == *"$UI_SELECT [B] BUSQUEDA EMISORAS"* ]] || fail 'búsqueda activa no muestra indicador de foco'

UI_UPDATE_DESKTOP_ROW=8
query_line=$(ui_desktop_row '' '' '' '' '' '' '' '' 0)
[[ "$query_line" == *'Buscar: rock_'* ]] || fail 'campo de búsqueda no aparece en la mitad inferior'
[[ "$query_line" == *'2 resultados'* ]] || fail 'contador de resultados no aparece'

UI_UPDATE_DESKTOP_ROW=9
result_line=$(ui_desktop_row '' '' '' '' '' '' '' '' 0)
[[ "$result_line" == *'Rock FM'* ]] || fail 'primer resultado no aparece en la mitad inferior'
[[ "$result_line" == *"$UI_SELECT Rock FM"* ]] || fail 'resultado activo no muestra foco'

UI_UPDATE_DESKTOP_ROW=0
favorite_line=$(ui_desktop_row '' '' '' '' "$UI_SELECT F1" '' '' '' 1)
[[ "$favorite_line" != *"$UI_SELECT F1"* ]] || fail 'favorito conserva foco mientras se escribe en búsqueda'

SEARCH_ACTIVE=0
SEARCH_QUERY=''
RECENT_NAMES=(R1 R2 R3)
RECENT_URLS=(r1 r2 r3)
declare -A FAVORITE_LABELS=()
FAVORITE_LABELS['r1']='comentario reciente'
UI_SELECTED_INDEX=8
UI_SCROLL_OFFSET=0
UI_RECENT_SCROLL=0
ui_desktop_sync_selection 13
UI_UPDATE_DESKTOP_ROW=0
columns_header=$(ui_desktop_row '' '' '' '' '' '' '' '' 0)
[[ "$columns_header" == *'FAVORITAS'* && "$columns_header" == *'RECIENTES'* && "$columns_header" == *'COMENTARIOS'* ]] || fail 'desktop ancho no muestra encabezados y comentarios en paralelo'
UI_UPDATE_DESKTOP_ROW=1
columns_row=$(ui_desktop_row '' '' '' '' '' '' '' '' 0)
[[ "$columns_row" == *'1. F1'* && "$columns_row" == *'1. R1'* && "$columns_row" == *'comentario re'* ]] || fail 'las columnas no muestran presets, scroll y comentarios independientes'

SEARCH_ACTIVE=1
search_controls=$(ui_draw_responsive_controls 119)
[[ "$search_controls" == *'Esc favoritos'* ]] || fail 'el pie no anuncia cómo volver a Favoritos'
[[ "$search_controls" != *'Q salir'* ]] || fail 'el pie muestra atajos inactivos durante la búsqueda'

SEARCH_ACTIVE=0
SEARCH_QUERY=''
SEARCH_MATCHES=()
SEARCH_SCROLL_OFFSET=0
UI_UPDATE_DESKTOP_ROW=8
idle_line=$(ui_desktop_row '' '' '' '' '' '' '' '' 0)
[[ "$idle_line" != *'B  Buscar emisoras'* && "$idle_line" != *'Pulsa B'* ]] || fail 'instrucciones redundantes en búsqueda'
[[ "$idle_line" == *'Sin catálogo disponible'* ]] || fail 'falta estado sin catálogo'

normal_controls=$(ui_draw_responsive_controls 119)
[[ "$normal_controls" == *'Q salir'* ]] || fail 'el pie normal no vuelve al salir de búsqueda'

printf 'ok   TUI desktop: favoritos arriba, búsqueda abajo y foco visible\n'
