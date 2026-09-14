#!/usr/bin/env bash
# Medición aislada: sin red, reproducción ni escritura en la terminal.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
player_is_running() { return 1; }
tput() { if [[ "$1" == cup ]]; then printf '\033[%d;%dH' "$(( $2 + 1 ))" "$(( $3 + 1 ))"; fi; }
ui_refresh_size() { UI_COLS=132; UI_LINES=40; }
UI_ACTIVE=1 UI_SUSPENDED=0 UI_COLOR=0 UI_UNICODE=1 UI_HELP_VISIBLE=0
ui_configure_glyphs
EQUALIZER_GAINS=(12 6 0 -6 -12)
SPECTRUM_LEVELS=(0 2 4 6 8 10 12 14 16 14 12 10 8 6 4 2)
FAVORITE_NAMES=('Radio de prueba') FAVORITE_URLS=('https://example.invalid/radio')
HISTORY_NAMES=() HISTORY_URLS=()
SEARCH_NAMES=() SEARCH_URLS=() SEARCH_MATCHES=()
for SPECTRUM_ENABLED in 0 1; do
    start=$EPOCHREALTIME
    start=${start//[.,]/}
    for ((frame=0; frame<10; frame++)); do ui_draw >/dev/null; done
    finish=$EPOCHREALTIME
    finish=${finish//[.,]/}
    printf 'Espectro %s: %d ms por dibujo (media de 10)\n' "$SPECTRUM_ENABLED" "$(((finish-start)/10000))"
done
start=$EPOCHREALTIME
start=${start//[.,]/}
for ((frame=0; frame<100; frame++)); do ui_draw_spectrum_only >/dev/null; done
finish=$EPOCHREALTIME
finish=${finish//[.,]/}
printf 'Solo espectro: %d microsegundos por dibujo (media de 100)\n' "$(((finish-start)/100))"

# Evita medir únicamente cuadros idénticos que aprovechan toda la caché.
start=${EPOCHREALTIME//[.,]/}
for ((frame=0; frame<100; frame++)); do
    for ((band=0; band<16; band++)); do
        SPECTRUM_LEVELS[band]=$(((frame + band) % 17))
        SPECTRUM_PEAK_LEVELS[band]=$(((frame + band * 3) % 17))
    done
    ui_draw_spectrum_only >/dev/null
done
finish=${EPOCHREALTIME//[.,]/}
printf 'Espectro cambiante: %d microsegundos por dibujo (media de 100)\n' "$(((finish-start)/100))"
start=${EPOCHREALTIME//[.,]/}
for ((frame=0; frame<100; frame++)); do
    PLAYER_BITRATE_KBPS=$((128 + frame))
    ui_draw_player_info_only >/dev/null || exit 1
done
finish=${EPOCHREALTIME//[.,]/}
printf 'Solo metadatos: %d microsegundos por dibujo (media de 100)\n' "$(((finish-start)/100))"

# Reproducción e historial: el caso vacío no ejercita las filas de canciones.
TERM=xterm-256color
unset TERMUX_VERSION PREFIX
player_is_running() { return 0; }
PLAYER_PID=$$ PLAYER_NAME='Radio de prueba' PLAYER_URL=https://example.invalid/radio
TRACK_HISTORY_TITLES=('Actual' 'Primera' 'Segunda' 'Tercera' 'Cuarta' 'Quinta' 'Sexta' 'Séptima' 'Octava')
TRACK_HISTORY_TIMES=('12:00' '11:59' '11:58' '11:57' '11:56' '11:55' '11:54' '11:53' '11:52')
for PREF_LOGO in 0 1; do
    ui_draw >/dev/null
    ((UI_LOGO_LAYOUT == PREF_LOGO)) || { printf 'No se ejercitó el espacio del logo\n' >&2; exit 1; }
    start=${EPOCHREALTIME//[.,]/}
    for ((frame=0; frame<20; frame++)); do ui_draw >/dev/null; done
    finish=${EPOCHREALTIME//[.,]/}
    printf 'Reproducción con historial, logo %d: %d us/dibujo\n' "$PREF_LOGO" "$(((finish-start)/20))"
    start=${EPOCHREALTIME//[.,]/}
    for ((frame=0; frame<20; frame++)); do
        PLAYER_STREAM_TITLE="Tema $frame"
        ui_draw_player_info_only >/dev/null || exit 1
    done
    finish=${EPOCHREALTIME//[.,]/}
    printf 'Metadatos con historial, logo %d: %d us/dibujo\n' "$PREF_LOGO" "$(((finish-start)/20))"
done
options_build_rows visual
start=${EPOCHREALTIME//[.,]/}
for ((frame=0; frame<20; frame++)); do
    OPTIONS_SELECTED=$((frame % ${#OPTIONS_ROWS[@]}))
    options_draw >/dev/null
done
finish=${EPOCHREALTIME//[.,]/}
printf 'Navegación Visualización: %d us/dibujo\n' "$(((finish-start)/20))"
