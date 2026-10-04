#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
keila_init_paths; favorites_init; favorites_load; history_load
origin=https://radio.invalid/original
PLAYER_URL=$origin PLAYER_INPUT_URL=$origin PLAYER_HLS_RATE=0 PLAYER_PID=123 PLAYER_NAME='Radio larga de ejemplo'
player_is_running() { return 0; }
record_plan_busy() { return 1; }
quality_start_job() { QUALITY_JOB_PID=''; QUALITY_ROWS+=("https://radio.invalid/low|0|AAC|64000|catalog"); }
quality_cleanup() { :; }
quality_apply_choice() { applied=$((applied+1)); [[ $3 == https://radio.invalid/low && $4 == 0 ]] || fail 'selección incorrecta'; }
app_message() { UI_MESSAGE=$1; }
panel_poll() { ticks=$((ticks+1)); return 1; }
ui_refresh_size() { :; }
tput() { :; }
UI_COLS=80 UI_LINES=24 applied=0 ticks=0
options_build_rows playback; options_key_select C || fail ruta
[[ $OPTIONS_ROW_ACTION == quality ]] || fail acción
options_action_reason quality; [[ -z $OPTIONS_REASON ]] || fail 'acción disponible bloqueada'
RECORDING_ACTIVE=1
options_action_reason quality; [[ -n $OPTIONS_REASON ]] || fail 'acción durante grabación'
RECORDING_ACTIVE=0 SEARCH_COUNTRY_FILTER_ENABLED=0
options_action_reason filter_region; [[ -n $OPTIONS_REASON ]] || fail 'zona sin país'
SEARCH_COUNTRY_FILTER_ENABLED=1 SEARCH_REGION_FILTER=Madrid SEARCH_QUERY=rock SEARCH_TAG_FILTER=rock
search_country_filter_toggle
[[ $SEARCH_COUNTRY_FILTER_ENABLED == 0 && -z $SEARCH_REGION_FILTER && $SEARCH_QUERY == rock && $SEARCH_TAG_FILTER == rock ]] || fail 'quitar país deja zona global'
events=(DOWN TICK RESIZE ESC) event_i=0
input_read() { INPUT_EVENT=${events[event_i]:-ESC}; INPUT_KEY=''; event_i=$((event_i+1)); }
app_quality_menu >/dev/null || true
[[ $applied == 0 && $ticks == 1 && $PREFERENCES_ACTIVE == 0 ]] || fail 'navegación/cancelación aplica'
events=(DOWN ENTER) event_i=0
app_quality_menu >/dev/null || fail confirmar
[[ $applied == 1 && $event_i == 2 ]] || fail 'un Enter no aplica'
# Grabar o cambiar la emisora justo antes de Enter no autoriza una acción obsoleta.
(
    source "$ROOT_DIR/lib/quality.sh"
    quality_start_job() { QUALITY_JOB_PID=''; }
    quality_cleanup() { :; }
    quality_save_choice() { fail 'guardar durante grabación'; }
    event_i=0
    input_read() { event_i=$((event_i+1)); INPUT_EVENT=ENTER; RECORDING_ACTIVE=1; }
    app_quality_menu >/dev/null && fail 'confirma con grabación activa'
    [[ $UI_MESSAGE == *'grabación'* ]] || fail 'falta motivo de bloqueo'
) || fail protección
(
    source "$ROOT_DIR/lib/quality.sh"
    quality_start_job() { QUALITY_JOB_PID=''; }
    quality_cleanup() { :; }
    quality_save_choice() { fail 'guardar con proceso obsoleto'; }
    event_i=0
    input_read() { event_i=$((event_i+1)); INPUT_EVENT=ENTER; PLAYER_PID=456; }
    app_quality_menu >/dev/null || true
    [[ $applied == 1 ]] || fail 'proceso obsoleto aplica'
    [[ $UI_MESSAGE == *'reproducción cambió'* ]] || fail 'falta aviso de proceso obsoleto'
) || fail 'cambio de reproducción'
events=(ENTER ESC) event_i=0 UI_COLS=8 UI_LINES=5
app_quality_menu >/dev/null || true
[[ $applied == 1 ]] || fail 'terminal ilegible confirma'
QUALITY_ROWS=("$origin|0||0|original" 'https://radio.invalid/low|0|AAC|64000|catalog' "$origin|128000|AAC|128000|hls")
# shellcheck disable=SC2004
QUALITY_TARGETS[$origin]=https://radio.invalid/saved QUALITY_RATES[$origin]=0
quality_menu_rows "$origin" "$origin" 0
[[ ${#PANEL_ROWS[@]} == 4 && ${PANEL_ROWS[1]} == *'28.8 MB/h'* && ${QUALITY_MENU_CHOICES[3]} == *'|saved' ]] || fail 'consumo y elección desaparecida'
UI_COLOR=0
for geometry in '160 45' '100 24' '97 16' '96 16' '80 24' '62 16' '50 13' '42 11' '40 10' '30 8' '20 6' '8 5' '2 1'; do
    read -r UI_COLS UI_LINES <<< "$geometry"
    for UI_UNICODE in 0 1; do
        ui_configure_glyphs
        frame=$(panel_draw 'CALIDAD / VERSIONES' 3 0 'Enter elegir | Esc volver' 'Información de bitrate' 'Radio de ejemplo')
        rows=0
        while IFS= read -r line; do rows=$((rows+1)); ((${#line} < UI_COLS)) || fail "ancho $geometry"; done <<< "$frame"
        [[ $rows == "$UI_LINES" ]] || fail "alto $geometry"
    done
done
printf 'ok   selector de calidad: un Enter, cancelación, conflictos, consumo y 13 geometrías\n'
