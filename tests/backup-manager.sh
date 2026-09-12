#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'backup_manager_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
config_load "$task_tmp/recordings" || fail config
favorites_init '' || fail favoritas
favorites_add Original https://original.invalid || fail favorita
STATE_VOLUME=23 STATE_LAST_NAME=Guardada STATE_LAST_URL=https://guardada.invalid
state_save || fail estado
EQUALIZER_GAINS=(1 2 3 4 5)
equalizer_save || fail ecualizador
UI_COLS=80 UI_LINES=24
PLAYER_VOLUME=83 PLAYER_NAME=Sonando PLAYER_URL=https://sonando.invalid PLAYER_MUTED=1 ALARM_AT=123456
RECORDING_ACTIVE=0 PENDING_PREVIEW_PID=''
BACKUP_RESCAN=0 BACKUP_CREATED_PATH=''
polls=0
app_poll_player() { ((polls+=1)); return 1; }
catalog_poll() { return 1; }
pending_scan_poll() { return 1; }
ui_message_tick() { return 1; }
equalizer_apply() { return 0; }
wait_job() {
    local i
    for ((i=0; i<400; i++)); do
        panel_poll || true
        backup_job_poll && return 0
        sleep .01
    done
    fail 'trabajo no termina'
}
backup_job_start create || fail 'iniciar creación'
[[ -n "$BACKUP_JOB_PID" && $BACKUP_DATA_BUSY == 1 ]] || fail 'no es asíncrono'
wait_job
[[ -s "$BACKUP_CREATED_PATH" && $BACKUP_DATA_BUSY == 0 && $polls -gt 0 ]] || fail 'crear no conserva polling'
created=$BACKUP_CREATED_PATH
backup_job_start scan || fail búsqueda
wait_job
found=0
for file in "${BACKUP_FILES[@]}"; do [[ "$file" != "$created" ]] || found=1; done
((found)) || fail 'lista no muestra la copia nueva'
[[ $PLAYER_VOLUME == 83 && $PLAYER_NAME == Sonando && $PLAYER_MUTED == 1 && $ALARM_AT == 123456 ]] || fail 'crear altera reproducción'

favorites_add Nueva https://nueva.invalid || fail nueva
BACKUP_TARGET=$created
backup_job_start prepare "$created" || fail preparar
wait_job
[[ -n "$BACKUP_PREPARED_DIR" && ${#FAVORITE_URLS[@]} == 2 ]] || fail 'preparar ya restaura'
backup_discard_prepared
[[ ${#FAVORITE_URLS[@]} == 2 ]] || fail 'cancelar restaura'
BACKUP_TARGET=$created
backup_job_start prepare "$created" || fail preparar
wait_job
RECORDING_ACTIVE=1
if backup_manager_confirm; then fail 'restaura grabando'; fi
RECORDING_ACTIVE=0
touch "$created"
if backup_manager_confirm; then fail 'confirma una copia cambiada'; fi
[[ -z "$BACKUP_PREPARED_DIR" ]] || fail 'conserva confirmación obsoleta'
BACKUP_TARGET=$created
backup_job_start prepare "$created" || fail preparar
wait_job
backup_manager_confirm || fail confirmar
[[ $BACKUP_RESTORE_ACTIVE == 1 && $BACKUP_DATA_BUSY == 1 ]] || fail 'no bloquea escrituras'
HISTORY_PENDING_URL=https://pendiente.invalid
if history_observe; then fail 'historial escribe durante restauración'; fi
[[ $HISTORY_PENDING_URL == https://pendiente.invalid ]] || fail 'pierde escucha pendiente'
wait_job
[[ ${#FAVORITE_URLS[@]} == 1 && ${FAVORITE_URLS[0]} == https://original.invalid ]] || fail 'no recarga favoritas'
[[ $STATE_VOLUME == 23 && $PLAYER_VOLUME == 83 && $PLAYER_NAME == Sonando && $PLAYER_MUTED == 1 && $ALARM_AT == 123456 ]] || fail 'restaurar cambia audio o alarma'
[[ $BACKUP_NOTICE == 'Restauración terminada.'* && $BACKUP_NOTICE == *pre-restore-* ]] || fail 'sin resultado o respaldo'

# El gestor no puede dejar procesos externos huérfanos al cerrar.
backup_job_start scan || fail 'último escaneo'
job_pid=$BACKUP_JOB_PID
backup_manager_cleanup
if kill -0 "$job_pid" 2>/dev/null; then fail 'queda worker vivo'; fi
[[ -z "$BACKUP_JOB_DIR" && $BACKUP_DATA_BUSY == 0 ]] || fail 'cleanup incompleto'
printf 'ok   gestor: trabajos reales, polling, confirmación, archivo cambiado y audio conservado\n'
