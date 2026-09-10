#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
export HOME="$task_tmp/home" XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"

source "$ROOT_DIR/lib/version.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/session-log.sh"

fail() {
    printf 'FAIL %s\n' "$*" >&2
    exit 1
}

mkdir -p "$HOME"
keila_init_paths || fail paths
session_log_init || fail init
[[ -f "$SESSION_LOG_FILE" && ! -L "$SESSION_LOG_FILE" ]] || fail 'registro no creado'
[[ "$(stat -c %a "$SESSION_LOG_FILE")" == 600 ]] || fail 'permisos del registro'

track_history_start_station $'Rock\tFM' 'https://radio.invalid/rock'
if grep -F '(sintonizada)' "$SESSION_LOG_FILE" >/dev/null; then fail 'sintonía registrada antes de audio'; fi

PLAYER_NAME='Rock FM'
PLAYER_URL='https://radio.invalid/rock'
PLAYER_STREAM_READY=0
PLAYER_STREAM_TITLE='Tema Uno'
track_history_observe && fail 'registró antes de audio'
if grep -F 'Tema Uno' "$SESSION_LOG_FILE" >/dev/null; then fail 'título registrado antes de audio'; fi

PLAYER_STREAM_READY=1
track_history_observe || fail 'no registró primer título'
grep -F '(sintonizada)' "$SESSION_LOG_FILE" >/dev/null || fail 'sintonía no registrada'
grep -F $'Rock FM' "$SESSION_LOG_FILE" >/dev/null || fail 'emisora no saneada'
track_history_observe && fail 'duplicó título'
PLAYER_STREAM_TITLE='Tema Dos'
track_history_observe || fail 'no registró segundo título'
PLAYER_STREAM_TITLE='Tema Tres'
track_history_observe || fail 'no registró tercer título'
PLAYER_STREAM_TITLE='Tema Cuatro'
track_history_observe || fail 'no registró cuarto título'

[[ ${#TRACK_HISTORY_TITLES[@]} == 4 ]] || fail 'historial visible no se limita'
[[ "${TRACK_HISTORY_TITLES[0]}" == 'Tema Cuatro' ]] || fail 'canción actual'
[[ "${TRACK_HISTORY_TITLES[1]}" == 'Tema Tres' ]] || fail 'anterior 1'
[[ "${TRACK_HISTORY_TITLES[2]}" == 'Tema Dos' ]] || fail 'anterior 2'
[[ "${TRACK_HISTORY_TITLES[3]}" == 'Tema Uno' ]] || fail 'anterior 3'
[[ "$(track_history_visible_count)" == 3 ]] || fail 'conteo visible'

summary=$(track_history_summary 80) || fail 'sin resumen visible'
[[ "$summary" == *'Tema Tres'* && "$summary" == *'Tema Dos'* && "$summary" == *'Tema Uno'* ]] || fail 'resumen incompleto'
[[ "$summary" != *'Tema Cuatro'* ]] || fail 'el resumen duplica la canción actual'

title_lines=$(grep -c 'Tema ' "$SESSION_LOG_FILE")
[[ "$title_lines" == 4 ]] || fail 'líneas de canciones duplicadas o perdidas'

track_history_start_station 'Otra Radio' 'https://radio.invalid/otra'
[[ ${#TRACK_HISTORY_TITLES[@]} == 0 && "$(track_history_visible_count)" == 0 ]] || fail 'cambio de emisora no reinicia historial visual'
PLAYER_NAME='Otra Radio'
PLAYER_URL='https://radio.invalid/otra'
PLAYER_STREAM_READY=1
PLAYER_STREAM_TITLE=''
track_history_observe >/dev/null 2>&1 || true
grep -F 'Otra Radio' "$SESSION_LOG_FILE" >/dev/null || fail 'segunda emisora no registrada'

session_log_close
grep -F '# Ended:' "$SESSION_LOG_FILE" >/dev/null || fail 'cierre no registrado'

printf 'ok   registro de sesión e histórico visible de canciones\n'
