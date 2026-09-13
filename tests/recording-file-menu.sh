#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'pending_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
recording_init "$task_tmp/recordings"
file="$RECORDINGS_DIR/Original.mp3"; printf AUDIO > "$file"
ui_refresh_size() { UI_COLS=40 UI_LINES=10; }
tput() { :; }; ui_draw() { :; }
app_poll_player() { ((polls+=1)); return 1; }
catalog_poll() { return 1; }; ui_message_tick() { return 1; }
step=0 polls=0
input_read() {
    ((step+=1)); INPUT_KEY=''
    case "$step" in
        1) INPUT_EVENT=DELETE ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=N ;;
        3) INPUT_EVENT=ENTER ;;
        4) [[ -e "$file" ]] || fail 'Enter del editor ya renombra'; INPUT_EVENT=KEY; INPUT_KEY='?' ;;
        5) INPUT_EVENT=ENTER ;;
        6|9) INPUT_EVENT=ESC ;;
        7) INPUT_EVENT=RESIZE ;;
        8) INPUT_EVENT=TICK ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_recording_rename "$file" >/dev/null
[[ -e "$file" && ! -e "$RECORDINGS_DIR/N.mp3" && $polls == 1 ]] || fail 'cancelación o polling'
step=0
input_read() {
    ((step+=1)); INPUT_KEY=''
    case "$step" in
        1) INPUT_EVENT=DELETE ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=N ;;
        3|5) INPUT_EVENT=ENTER ;;
        4) INPUT_EVENT=DOWN ;;
        *) fail 'no termina tras confirmar' ;;
    esac
}
app_recording_rename "$file" >/dev/null || fail renombrado
renamed="$RECORDINGS_DIR/N.mp3"
[[ -e "$renamed" && ! -e "$file" ]] || fail 'Enter no confirma destino'
pending_trash "$renamed" "$(pending_signature "$renamed")" || fail papelera
trashed=$RECORDING_FILES_RESULT
step=0
input_read() { ((step+=1)); INPUT_EVENT=ESC INPUT_KEY=''; }
app_recording_restore "$trashed" >/dev/null || true
[[ -e "$trashed" && ! -e "$renamed" ]] || fail 'cancelar restaura'
step=0
input_read() {
    ((step+=1)); INPUT_KEY=''
    case "$step" in 1) INPUT_EVENT=RESIZE ;; 2) INPUT_EVENT=TICK ;; *) INPUT_EVENT=ENTER ;; esac
}
app_recording_restore "$trashed" >/dev/null || fail restaurar
[[ -e "$renamed" && ! -e "$trashed" ]] || fail 'no recupera tras confirmar'

# Repetir la entrada T/Esc conserva la lista padre aunque haya escaneo pendiente.
pending_cleanup
PENDING_FILES=("$renamed")
step=0
input_read() {
    ((step+=1)); INPUT_KEY=''
    case "$step" in 1) INPUT_EVENT=KEY; INPUT_KEY=t ;; 2) INPUT_EVENT=TICK ;; *) INPUT_EVENT=ESC ;; esac
}
app_pending_menu >/dev/null
[[ ${PENDING_FILES[0]:-} == "$renamed" && $PREFERENCES_ACTIVE == 0 ]] || fail 'papelera altera lista/foco padre'
pending_cleanup

# El escaneo de papelera admite carpetas antiguas, sin seguir enlaces.
pending_trash "$renamed" "$(pending_signature "$renamed")" || fail 'preparar papelera'
trashed=$RECORDING_FILES_RESULT
pending_cleanup
PENDING_VIEW=trash
pending_scan_start
for ((i=0; i<200; i++)); do pending_scan_poll || true; [[ -n "$PENDING_SCAN_PID" ]] || break; sleep .01; done
[[ ${#PENDING_FILES[@]} == 1 && ${PENDING_FILES[0]} == "$trashed" ]] || fail 'no lista papelera'
PENDING_VIEW=library
printf 'ok   menús: editor, confirmación, cancelación, resize, polling y papelera aislada\n'
