#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$1
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null

# Solo presentación/entrada reales; no catálogo, radio, datos del usuario ni
# llamadas de red. El padre prepara rutas XDG privadas y desactiva updates.
catalog_start() { :; }
pending_scan_start() { :; }
catalog_poll() { return 1; }
pending_scan_poll() { return 1; }
ui_message_tick() { return 1; }
app_poll_player() { printf '\nTICK\n'; return 1; }
draws=0
ui_draw() {
    ((draws+=1))
    printf '\033[2J\033[H\nREADY:%s\n' "$draws"
}
original_panel=$(declare -f panel_draw)
eval "${original_panel/panel_draw ()/probe_panel_draw ()}"
panel_draw() {
    probe_panel_draw "$@"
    printf '\nPROMPT:%s\n' "$2"
}

# Comprobar también Ctrl-C desde un menú/editor: cancelar no pierde su estado.
app_options_menu() {
    local draft='texto conservado' redraw=1 PREFERENCES_ACTIVE=1 PANEL_FORM=1
    while true; do
        if ((redraw)); then printf '\033[2J\033[H\nEDITOR:%s\n' "$draft"; fi
        input_read || return 0
        redraw=0
        case "$INPUT_EVENT" in
            RESIZE) redraw=1 ;;
            ESC) return 0 ;;
            KEY) draft+=$INPUT_KEY; redraw=1 ;;
            TICK) app_poll_player || true ;;
        esac
    done
}
printf 'STARTING\n'
app_loop
