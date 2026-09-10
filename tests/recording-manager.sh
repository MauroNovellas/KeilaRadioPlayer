#!/usr/bin/env bash
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
file="$RECORDINGS_DIR/Radio con nombre largo para pantalla pequeña.mp3"
printf 'audio de prueba' > "$file"
printf '999999999\n' > "$file.pending"
active="$RECORDINGS_DIR/activa.mp3"
printf 'audio en curso' > "$active"
printf '%s\n' "$$" > "$active.pending"
app_message() { :; }
wait_scan() {
    local i
    for ((i=0;i<100;i++)); do pending_scan_poll && return 0; sleep .02; done
    fail 'scan bloqueado'
}
wait_probe() {
    local i
    for ((i=0;i<200;i++)); do pending_probe_poll && return 0; sleep .02; done
    fail 'probe bloqueado'
}
pending_scan_start || fail scan
wait_scan
[[ ${#PENDING_FILES[@]} == 1 && ${PENDING_FILES[0]} == "$file" ]] || fail listado
if pending_probe_start "$active"; then fail 'verifica grabación activa'; fi
if pending_trash "$active" "$(pending_signature "$active")"; then fail 'borra grabación activa'; fi

recording_probe_file() { return 1; }
pending_probe_start "$file" || fail probe
wait_probe
[[ -f "$file.pending" && -s "$file" && $PENDING_NOTICE == Dudosa* ]] || fail dudosa
recording_probe_file() { return 0; }
pending_probe_start "$file" || fail probe
printf 'cambio durante probe' >> "$file"
wait_probe
[[ -f "$file.pending" ]] || fail 'finaliza archivo modificado'
pending_probe_start "$file" || fail probe
wait_probe
[[ ! -e "$file.pending" && -s "$file" ]] || fail 'no finaliza verificada'
wait_scan

[[ ${#PENDING_FILES[@]} == 1 && ${PENDING_FILES[0]} == "$file" ]] || fail 'desaparece grabación finalizada'

printf '999999999\n' > "$file.pending"
signature=$(pending_signature "$file")
printf 'cambio' >> "$file"
if pending_trash "$file" "$signature"; then fail 'borra archivo cambiado'; fi

# El panel mantiene el sondeo, cabe en Termux y permite cancelar la eliminación.
ui_draw() { :; }
tput() { if [[ ${1:-} == ed ]]; then printf '\n'; fi; }
ui_refresh_size() { UI_COLS=45 UI_LINES=11; }
app_poll_player() { ((polls+=1)); return 0; }
ui_message_tick() { return 1; }; catalog_poll() { return 1; }
PENDING_FILES=("$file")
events=0 polls=0
input_read() {
    ((events+=1)); INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=TICK ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=x ;;
        3) INPUT_EVENT=ESC ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_pending_menu > "$task_tmp/render"
[[ -f "$file" && -f "$file.pending" && $polls == 1 ]] || fail 'cancelación o sondeo'
while IFS= read -r line || [[ -n "$line" ]]; do
    ((${#line}<45)) || fail 'autowrap en pantalla pequeña'
done < "$task_tmp/render"
# Detener la búsqueda del menú para que no publique una lista antigua.
pending_cleanup
events=0
input_read() {
    ((events+=1)); INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=x ;;
        2) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_pending_menu >/dev/null
[[ ! -e "$file" && ! -e "$file.pending" ]] || fail 'confirmación no elimina'
shopt -s nullglob
trashed=("$RECORDINGS_DIR"/.trash/*/*.mp3)
[[ ${#trashed[@]} == 1 && -s ${trashed[0]} && -f ${trashed[0]}.pending ]] || fail 'papelera no recuperable'
pending_cleanup

# Escucha separada: pausa/restaura solo la misma radio, sin tocar historial.
file=${trashed[0]}
player_is_running() { return 0; }
player_toggle_pause() { PLAYER_PAUSED=$((1-PLAYER_PAUSED)); }
mpv() { return 0; }
PLAYER_PID=$$ PLAYER_URL=https://radio.invalid PLAYER_PAUSED=0
HISTORY_PENDING_URL=sin-cambios RECORDING_ACTIVE=0
pending_preview_start "$file" || fail escucha
[[ $PLAYER_PAUSED == 1 ]] || fail 'radio no pausada'
pending_preview_stop
[[ $PLAYER_PAUSED == 0 && $HISTORY_PENDING_URL == sin-cambios ]] || fail 'radio o historial alterado'
printf 'ok   pendientes: scan, actividad, verificación, cambios, confirmación, papelera y escucha\n'
