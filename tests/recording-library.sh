#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Se usa primero el módulo cargado y después se sustituye para probar el menú.
# shellcheck disable=SC2317,SC2218
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
declare -A PENDING_DOUBTFUL
trap 'pending_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
recording_init "$task_tmp/recordings"
old="$RECORDINGS_DIR/Antigua.mp3" recent="$RECORDINGS_DIR/Reciente.OPUS"
odd="$RECORDINGS_DIR/Nombre"$'\n\t'"con|separadores.wav"
empty="$RECORDINGS_DIR/Vacía.ts" busy="$RECORDINGS_DIR/Activa.mp3"
unsafe="$RECORDINGS_DIR/Marcador inseguro.mp3"
for file in "$old" "$recent" "$odd" "$busy" "$unsafe"; do printf 'audio ficticio' > "$file"; done
: > "$empty"
printf 'closed\n' > "$recent.pending"
printf '%s\n' "$$" > "$busy.pending"
mkfifo "$unsafe.pending"
ln -s "$old" "$RECORDINGS_DIR/enlace.mp3"
mkdir "$RECORDINGS_DIR/directorio.mp3"
touch -d '2020-01-01' "$old"
touch -d '2030-01-01' "$recent"
app_message() { :; }
recording_probe_file() { fail 'el listado decodifica audio'; }
wait_scan() {
    local i
    for ((i=0; i<200; i++)); do
        pending_scan_poll || true
        [[ -n "$PENDING_SCAN_PID" ]] || return 0
        sleep .01
    done
    fail 'listado bloqueado'
}
pending_scan_start || fail inicio
wait_scan
[[ ${#PENDING_FILES[@]} == 6 && ${PENDING_FILES[0]} == "$recent" && ${PENDING_FILES[5]} == "$old" ]] || fail orden
[[ ${PENDING_METADATA[$odd]} == '14|'* && ${PENDING_STATES[$recent]} == Pendiente && ${PENDING_STATES[$empty]} == Vacía && ${PENDING_STATES[$busy]} == 'En curso' && ${PENDING_STATES[$unsafe]} == 'No disponible' ]] || fail metadatos
if pending_signature "$unsafe" || pending_probe_start "$unsafe" || pending_preview_start "$unsafe"; then fail 'acepta marcador FIFO'; fi
if pending_preview_start "$empty" || pending_preview_start "$busy"; then fail 'escucha vacío u ocupado'; fi
# Dibujar una lista ya escaneada no vuelve a consultar el disco por cada tecla.
stat() { fail 'stat durante render cacheado'; }
UI_COLS=80 UI_LINES=24
pending_build_panel 0 0
unset -f stat
[[ "${PANEL_ROWS[*]}" != *$'\n'* && "${PANEL_ROWS[*]}" != *$'\t'* ]] || fail 'filtra controles del nombre'

# Una verificación fallida se conserva como dudosa al refrescar en esta sesión.
PENDING_DOUBTFUL[$old]=$(pending_signature "$old")
pending_scan_start; wait_scan
[[ ${PENDING_STATES[$old]} == Dudosa ]] || fail 'pierde aviso al refrescar'
# Fallo de scan conserva la lista. Una solicitud durante otro scan se repite.
previous=${PENDING_FILES[*]}
pending_scan_start
pending_stop_child "$PENDING_SCAN_PID"
# La ruta se publica en pending_scan_start, dentro del módulo cargado.
# shellcheck disable=SC2153
printf '1\n' > "$PENDING_SCAN_DIR/done"
pending_scan_poll || fail 'no recoge error'
[[ ${PENDING_FILES[*]} == "$previous" && $PENDING_NOTICE == 'No se pudo actualizar'* ]] || fail 'error borra lista'
pending_scan_start; pending_scan_start
[[ $PENDING_SCAN_AGAIN == 1 ]] || fail 'pierde solicitud de refresco'
wait_scan
[[ $PENDING_SCAN_AGAIN == 0 ]] || fail 'refresco no termina'

# Refrescar y reordenar dentro de un detalle conserva el archivo seleccionado.
pending_scan_start() { return 0; }
ui_draw() { :; }; tput() { :; }; ui_refresh_size() { UI_COLS=62 UI_LINES=16; }
PENDING_FILES=("$recent" "$old")
step=0 opened=''
panel_detail() { PENDING_FILES=("$old" "$recent"); ((PENDING_SCAN_GENERATION+=1)); }
app_recording_preview() { opened=$1; }
input_read() {
    ((step+=1)); INPUT_KEY=''
    case "$step" in
        1) INPUT_EVENT=DOWN ;;
        2) INPUT_EVENT=ENTER ;;
        3) INPUT_EVENT=RESIZE ;;
        4) INPUT_EVENT=KEY; INPUT_KEY=e ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_pending_menu >/dev/null
[[ "$opened" == "$old" ]] || fail 'refresco cambia selección'
printf 'ok   biblioteca: orden, estados, metadatos privados, FIFO, refresco y selección estable\n'
