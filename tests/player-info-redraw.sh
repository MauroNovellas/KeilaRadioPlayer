#!/usr/bin/env bash
set -uo pipefail
# shellcheck disable=SC2317
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
tput() { if [[ "$1" == cup ]]; then printf '<%s,%s>' "$2" "$3"; fi; }
ui_refresh_size() { :; }
player_is_running() { return 0; }
history_observe() { return 1; }
spectrum_tick() { return 1; }
recording_tick_changed() { return 1; }
player_refresh_info() { PLAYER_BITRATE_KBPS=192; return 0; }
UI_ACTIVE=1 UI_SUSPENDED=0 UI_COLOR=0 UI_UNICODE=1 UI_HELP_VISIBLE=0
FAVORITE_NAMES=() FAVORITE_URLS=() HISTORY_NAMES=() HISTORY_URLS=()
SEARCH_NAMES=() SEARCH_URLS=() SEARCH_MATCHES=()
PLAYER_INFO_READY=1 PLAYER_BUFFERING=0
PLAYER_STREAM_TITLE='Título nuevo' PLAYER_CODEC=mp3
PLAYER_SAMPLE_RATE=44100 PLAYER_CHANNELS=stereo
ui_configure_glyphs
for dimensions in '132 40' '112 20'; do
    PLAYER_STREAM_TITLE='Título nuevo'
    TRACK_HISTORY_TITLES=('Título nuevo' 'Tema anterior' 'Tema previo')
    TRACK_HISTORY_TIMES=('12:00:02' '12:00:01' '12:00:00')
    read -r UI_COLS UI_LINES <<< "$dimensions"
    ui_draw >/dev/null
    expected="<4,2>$(ui_print_styled_padded "$UI_DESKTOP_LEFT_WIDTH" "$UI_NOTE $PLAYER_STREAM_TITLE" accent)<5,2>$(PLAYER_BITRATE_KBPS=192; ui_print_styled_padded "$UI_DESKTOP_LEFT_WIDTH" "$(ui_audio_info)" muted)<6,2>$(ui_print_styled_padded "$UI_DESKTOP_LEFT_WIDTH" "$(track_history_summary "$UI_DESKTOP_LEFT_WIDTH")" muted)"
    actual=$(app_poll_player); status=$?
    [[ "$status" == 1 && "$actual" == "$expected" ]] || fail 'metadatos no limitados a sus filas parciales'
    # La desaparición del título borra el anterior con el texto de sustitución.
    PLAYER_STREAM_TITLE=''
    actual=$(ui_draw_player_info_only)
    [[ "$actual" == *'Sin título de emisión disponible'* ]] || fail 'título anterior no borrado'
done
UI_SUSPENDED=1
actual=$(app_poll_player); status=$?
[[ "$status" == 0 && -z "$actual" ]] || fail 'dibujo parcial durante suspensión'
UI_SUSPENDED=0 INPUT_RESIZE_PENDING=1
actual=$(app_poll_player); status=$?
[[ "$status" == 0 && -z "$actual" ]] || fail 'dibujo parcial durante redimensionado'
INPUT_RESIZE_PENDING=0 UI_COLS=80 UI_LINES=24
ui_draw >/dev/null
actual=$(app_poll_player); status=$?
[[ "$status" == 0 && -z "$actual" ]] || fail 'modo compacto no solicita dibujo completo'
UI_COLS=132 UI_LINES=40
ui_draw >/dev/null
player_refresh_info() { PLAYER_BUFFERING=1; return 0; }
actual=$(app_poll_player); status=$?
[[ "$status" == 0 && -z "$actual" ]] || fail 'buffering no solicita dibujo completo'
printf 'ok   metadatos parciales, borrado y fallback de estado/tamaño\n'
