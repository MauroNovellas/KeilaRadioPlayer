#!/usr/bin/env bash
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
player_is_running() { return 1; }
tput() { if [[ "$1" == cup ]]; then printf '<%s,%s>' "$2" "$3"; fi; }
ui_refresh_size() { UI_COLS=132; UI_LINES=$test_lines; }
UI_ACTIVE=1 UI_SUSPENDED=0 UI_COLOR=0 UI_HELP_VISIBLE=0
FAVORITE_NAMES=() FAVORITE_URLS=() HISTORY_NAMES=() HISTORY_URLS=()
SPECTRUM_LEVELS=(16 14 12 10 8 6 4 2 0 0 0 0 0 0 0 0)
for UI_UNICODE in 0 1; do
    ui_configure_glyphs
    for test_lines in 40 24 20; do
        ui_draw >/dev/null
        expected=''
        for ((row=0; row<8 && row<test_lines-20; row++)); do
            expected+="<$((row+16)),2>$(ui_spectrum_editor_row_wide "$row" "$UI_DESKTOP_LEFT_WIDTH")"
        done
        actual=$(ui_draw_spectrum_only)
        [[ "$actual" == "$expected" ]] || fail "rectángulo incorrecto en $test_lines filas"
        wide_row=$(ui_spectrum_editor_row_wide 7 "$UI_DESKTOP_LEFT_WIDTH")
        [[ "$wide_row" != *"$UI_BAR_FULL$UI_BAR_FULL$UI_BAR_FULL"* ]] || fail 'barras de ancho desigual'
        # Un frame vacío debe borrar por completo las barras anteriores.
        saved=("${SPECTRUM_LEVELS[@]}")
        SPECTRUM_LEVELS=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
        actual=$(ui_draw_spectrum_only)
        [[ "$actual" != *"$UI_BAR_FULL"* ]] || fail 'restos de barras anteriores'
        SPECTRUM_LEVELS=("${saved[@]}")
    done
done
UI_SUSPENDED=1
[[ -z "$(ui_draw_spectrum_only)" ]] || fail 'dibujo con TUI suspendida'

# Un cambio exclusivo de niveles no solicita un redibujado completo; un cambio
# de disponibilidad sí, porque afecta al encabezado fuera del rectángulo.
player_is_running() { return 0; }
player_refresh_info() { return 1; }
history_observe() { return 1; }
recording_tick_changed() { return 1; }
spectrum_tick() { return 0; }
ui_draw_spectrum_only() { printf partial; }
SPECTRUM_NOTICE_PENDING=0
actual=$(app_poll_player)
status=$?
[[ "$actual" == partial && "$status" == 1 ]] || fail 'el tick del espectro solicita dibujo completo'
spectrum_tick() { SPECTRUM_AVAILABLE=no; return 0; }
SPECTRUM_AVAILABLE=yes
actual=$(app_poll_player)
status=$?
[[ -z "$actual" && "$status" == 0 ]] || fail 'cambio de disponibilidad sin dibujo completo'
printf 'ok   refresco parcial: coordenadas, tamaño, silencio y suspensión\n'
