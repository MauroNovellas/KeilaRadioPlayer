#!/usr/bin/env bash
# Medición aislada: sin red, reproducción ni escritura en la terminal.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
player_is_running() { return 1; }
tput() { :; }
ui_refresh_size() { UI_COLS=132; UI_LINES=40; }
UI_ACTIVE=1 UI_SUSPENDED=0 UI_COLOR=0 UI_UNICODE=1 UI_HELP_VISIBLE=0
ui_configure_glyphs
EQUALIZER_GAINS=(12 6 0 -6 -12)
SPECTRUM_LEVELS=(0 2 4 6 8 10 12 14 16 14 12 10 8 6 4 2)
FAVORITE_NAMES=('Radio de prueba') FAVORITE_URLS=('https://example.invalid/radio')
HISTORY_NAMES=() HISTORY_URLS=()
SEARCH_NAMES=() SEARCH_URLS=() SEARCH_MATCHES=()
for SPECTRUM_ENABLED in 0 1; do
    start=${EPOCHREALTIME/./}
    for ((frame=0; frame<10; frame++)); do ui_draw >/dev/null; done
    finish=${EPOCHREALTIME/./}
    printf 'Espectro %s: %d ms por dibujo (media de 10)\n' "$SPECTRUM_ENABLED" "$(((finish-start)/10000))"
done
