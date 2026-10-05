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
    history_count=$(ui_desktop_track_history_slots "$(ui_desktop_body_height)")
    expected="<4,2>$(ui_print_styled_padded "$UI_DESKTOP_LEFT_WIDTH" "En antena: $PLAYER_STREAM_TITLE" accent)"
    if ((history_count > 0)); then
        expected+="<5,2>$(ui_print_styled_padded "$UI_DESKTOP_LEFT_WIDTH" '  Emisiones anteriores' accent)"
        for ((history_index = 0; history_index < history_count; history_index++)); do
            expected+="<$((6 + history_index)),2>$(ui_print_styled_padded "$UI_DESKTOP_LEFT_WIDTH" "$(track_history_line "$history_index" "$UI_DESKTOP_LEFT_WIDTH")" muted)"
        done
        expected+="<$((6 + history_count)),2>$(ui_print_styled_padded "$UI_DESKTOP_LEFT_WIDTH" "$(track_history_session_line "$UI_DESKTOP_LEFT_WIDTH")" muted)"
        expected+="<$((7 + history_count)),2>$(PLAYER_BITRATE_KBPS=192; ui_print_styled_padded "$UI_DESKTOP_LEFT_WIDTH" "$(ui_quality_info)" quality)"
    else
        expected+="<5,2>$(PLAYER_BITRATE_KBPS=192; ui_print_styled_padded "$UI_DESKTOP_LEFT_WIDTH" "$(ui_quality_info)" quality)"
    fi
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

# Los metadatos dejan intacto el espacio SIXEL y no retransmiten la imagen.
PREF_LOGO=1 PLAYER_PID=123 PLAYER_URL=https://radio.invalid/stream
PLAYER_STREAM_TITLE='Tema con logo' LOGO_READY_URL=$PLAYER_URL LOGO_BACKEND=sixel
LOGO_SIXEL_BODY='"1;1;96;96#0;2;0;0;0#0!96~-'
ui_draw >/dev/null
logo_line_width 1
expected="<4,2>$(ui_print_styled_padded "$UI_PLAYER_LINE_WIDTH" "En antena: $PLAYER_STREAM_TITLE" accent)<5,2>"
actual=$(ui_draw_player_info_only) || fail 'no permite metadatos con logo'
[[ $actual == "$expected"* && $actual != *$'\033P'* && $actual != *$'\033[16t'* ]] || fail 'metadatos invaden o retransmiten el logo'
LOGO_DRAWN=0
printf 'ok   metadatos parciales, borrado y fallback de estado/tamaño\n'
