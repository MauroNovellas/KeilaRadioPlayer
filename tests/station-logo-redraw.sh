#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'LOGO_DRAWN=0 LOGO_UPLOADED=-1; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ui_refresh_size() { :; }
tput() {
    case $1 in
        cup) printf '\033[%d;%dH' "$(($2+1))" "$(($3+1))" ;;
        ed) printf '\033[0J' ;;
        clear) printf '\033[2J' ;;
        colors) printf 256 ;;
        sgr0) printf '\033[0m' ;;
        bold) printf '\033[1m' ;;
        dim) printf '\033[2m' ;;
        setaf) printf '\033[%dm' "$((30+$2))" ;;
    esac
}
player_is_running() { return 0; }
unset TERMUX_VERSION PREFIX TMUX STY
unset NO_COLOR KEILA_NO_COLOR
UI_ACTIVE=1 UI_SUSPENDED=0 UI_HELP_VISIBLE=0 PREFERENCES_ACTIVE=0
PREF_COLOR=1 PREF_LOGO=1 SPECTRUM_ENABLED=0
ui_configure_theme
FAVORITE_NAMES=('Radio One' 'Radio Two') FAVORITE_URLS=(https://radio.invalid/one https://radio.invalid/two)
RECENT_NAMES=('Recent One' 'Recent Two') RECENT_URLS=(https://recent.invalid/one https://recent.invalid/two)
HISTORY_NAMES=() HISTORY_URLS=() SEARCH_NAMES=() SEARCH_URLS=() SEARCH_MATCHES=()
TRACK_HISTORY_TITLES=('Current song' 'Previous song') TRACK_HISTORY_TIMES=('12:00' '11:59')
LOGO_PIXELS_BASE64=$(printf '%036864d' 0); LOGO_PIXELS_BASE64=${LOGO_PIXELS_BASE64//0/A}
LOGO_SIXEL_BODY='"1;1;96;96#0;2;0;0;0#0!96~'
for ((band=1; band<16; band++)); do LOGO_SIXEL_BODY+='-!96~'; done

has_image() {
    case $backend in
        sixel) [[ $1 == *$'\033P0;1;0q'* ]] ;;
        kitty) [[ $1 == *'a=p,'* ]] ;;
    esac
}
paint_new() {
    ui_draw > "$task_tmp/frame"
    frame=$(<"$task_tmp/frame")
    has_image "$frame" || fail "no repone $backend: $1"
    [[ $LOGO_DRAWN == 1 && -n $LOGO_DRAW_KEY && $UI_LOGO_PRESERVE == 0 ]] || fail 'no publica colocación nueva'
}
stable_frame() {
    ui_draw > "$task_tmp/frame"
    frame=$(<"$task_tmp/frame")
    [[ $frame != *$'\033P'* && $frame != *$'\033_G'* && $frame != *$'\033[16t'* ]] || fail "retransmite/borra $backend: $1"
    [[ $LOGO_DRAWN == 1 && $UI_LOGO_PRESERVE == 1 ]] || fail "pierde estado de colocación: $1"
    python3 "$ROOT_DIR/tests/fixtures/check-logo-preserved.py" "$task_tmp/frame" "$LOGO_DRAW_COLUMN" "$UI_COLS" "$UI_LINES" || fail "$backend/$unicode: $1"
    [[ -z $(logo_draw) ]] || fail 'dibujo redundante envía comandos de imagen'
}

for backend in sixel kitty; do
    LOGO_BACKEND=$backend
    TERM=foot; [[ $backend != kitty ]] || TERM=xterm-kitty
    for unicode in 0 1; do
        UI_COLS=132 UI_LINES=40 UI_UNICODE=$unicode PREF_UNICODE=$unicode
        ui_configure_glyphs
        PLAYER_PID=123 PLAYER_NAME='Radio One' PLAYER_URL=https://radio.invalid/one
        PLAYER_STREAM_TITLE='Current song' PLAYER_PAUSED=0 PLAYER_BUFFERING=0
        LOGO_READY_URL=$PLAYER_URL LOGO_GENERATION=1 LOGO_SIXEL_SIDE=96
        LOGO_DRAWN=0 LOGO_DRAW_KEY='' LOGO_UPLOADED=-1 UI_LOGO_PRESERVE=0
        UI_SELECTED_INDEX=0 SEARCH_ACTIVE=0 SEARCH_QUERY='' PREF_LOGO=1
        paint_new inicial
        for ((step=0; step<4; step++)); do
            ui_move_selection 1 || true
            stable_frame cursores
        done
        UI_MESSAGE='Estado actualizado' PLAYER_MUTED=1
        stable_frame estado
        PLAYER_PAUSED=1 PLAYER_VOLUME=35
        stable_frame pausa-volumen
        PLAYER_STREAM_TITLE='A different song' UI_HELP_VISIBLE=1
        stable_frame titulo-ayuda
        UI_HELP_VISIBLE=0 SEARCH_ACTIVE=1 SEARCH_QUERY=rock
        stable_frame busqueda
        SEARCH_ACTIVE=0 SEARCH_QUERY=''

        # Salir a menús y sus detalles invalida la colocación, no los píxeles.
        options_build_rows visual
        options_draw > "$task_tmp/menu"
        [[ $LOGO_DRAWN == 0 && $UI_LOGO_PRESERVE == 0 ]] || fail 'menú no oculta'
        paint_new volver-menu
        stable_frame tras-menu
        OPTIONS_SELECTED=0 OPTIONS_DETAIL_SCROLL=0
        options_detail_draw > "$task_tmp/menu"
        [[ $LOGO_DRAWN == 0 ]] || fail 'detalle no oculta'
        paint_new volver-detalle

        ui_suspend > "$task_tmp/suspend"
        [[ $LOGO_DRAWN == 0 && $UI_SUSPENDED == 1 ]] || fail 'suspender no invalida'
        ui_draw > "$task_tmp/suspended"
        [[ ! -s $task_tmp/suspended ]] || fail 'dibuja durante suspensión'
        ui_resume > "$task_tmp/resume"
        paint_new reanudar
        stable_frame tras-reanudar

        # El cambio de alto también invalida, aunque no cambie la columna.
        UI_LINES=41
        paint_new redimensionar-alto
        stable_frame tras-redimensionar
        UI_COLS=160
        paint_new redimensionar-ancho
        stable_frame nueva-columna
        LOGO_GENERATION=$((LOGO_GENERATION+1))
        paint_new imagen-actualizada
        stable_frame tras-actualizar-imagen

        PREF_LOGO=0
        ui_draw > "$task_tmp/hidden"
        [[ $LOGO_DRAWN == 0 && $UI_LOGO_LAYOUT == 0 ]] || fail 'desactivar deja imagen'
        PREF_LOGO=1
        paint_new reactivar

        PLAYER_NAME='New station' PLAYER_URL=https://new.invalid/stream
        ui_draw > "$task_tmp/changed"
        [[ $LOGO_DRAWN == 0 ]] || fail 'conserva imagen de otra emisora'
        LOGO_READY_URL=$PLAYER_URL LOGO_GENERATION=$((LOGO_GENERATION+1))
        paint_new nueva-emisora
        stable_frame tras-cambiar

        UI_COLS=119 UI_LINES=23
        ui_draw > "$task_tmp/small"
        [[ $LOGO_DRAWN == 0 && $UI_LOGO_LAYOUT == 0 && $UI_LOGO_PRESERVE == 0 ]] || fail 'logo en pantalla pequeña'
        UI_COLS=132 UI_LINES=40
        paint_new volver-desktop
        TERMUX_VERSION='test'
        ui_draw > "$task_tmp/termux"
        [[ $LOGO_DRAWN == 0 && $UI_LOGO_LAYOUT == 0 ]] || fail 'logo en Termux'
        unset TERMUX_VERSION
        LOGO_DRAWN=0 LOGO_UPLOADED=-1
    done
done
printf 'ok   logos estables: sin borrar/retransmitir ni escribir sobre SIXEL/Kitty; resize, menús, suspensión y fallback\n'
