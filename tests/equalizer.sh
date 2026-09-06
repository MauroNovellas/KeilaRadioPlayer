#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "$3: esperado '$1', obtenido '$2'"; }

source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/lock.sh"
source "$ROOT_DIR/lib/player.sh"
source "$ROOT_DIR/lib/equalizer.sh"

trap 'rm -rf "$task_tmp"' EXIT
config_load "$task_tmp/recordings" || fail 'configuración'
equalizer_load || fail 'carga inicial'
assert_eq 'Plano' "$(equalizer_summary)" 'ecualizador plano por defecto'
if equalizer_filter; then fail 'el perfil plano creó un filtro'; fi

PLAYER_PID=''
equalizer_set_gain 0 6 || fail 'guardar graves'
assert_eq '6' "${EQUALIZER_GAINS[0]}" 'ganancia de graves'
[[ "$(equalizer_filter)" == *'equalizer=f=60:t=q:w=1:g=6'* ]] || fail 'filtro de graves'
[[ "$(stat -c %a "$KEILA_EQUALIZER_FILE")" == 600 ]] || fail 'permisos de ecualizador'

EQUALIZER_GAINS=(0 0 0 0 0)
equalizer_load || fail 'recarga'
assert_eq '6' "${EQUALIZER_GAINS[0]}" 'persistencia de graves'

# La actualización en vivo es atómica: si mpv rechaza el filtro, la memoria y
# el archivo conservan el último ajuste que sí estaba aplicado.
PLAYER_PID=12345
player_is_running() { return 0; }
player_ipc() { return 1; }
if equalizer_set_gain 1 4; then fail 'aceptó ajuste rechazado por mpv'; fi
assert_eq '0' "${EQUALIZER_GAINS[1]}" 'rollback en memoria'

received_payload=''
player_ipc() { received_payload="$1"; return 0; }
equalizer_set_gain 1 4 || fail 'ajuste IPC válido'
jq -e '.command[0] == "af" and .command[1] == "set" and (.command[2] | contains("equalizer=f=250:t=q:w=1:g=4"))' <<< "$received_payload" >/dev/null || fail 'comando IPC de filtro'

EQUALIZER_SELECTED=1
equalizer_change_selected 20 || fail 'límite superior'
assert_eq '12' "${EQUALIZER_GAINS[1]}" 'máximo de 12 dB'
equalizer_change_selected -40 || fail 'límite inferior'
assert_eq '-12' "${EQUALIZER_GAINS[1]}" 'mínimo de -12 dB'
equalizer_reset || fail 'restablecer plano'
assert_eq 'Plano' "$(equalizer_summary)" 'resumen tras reset'

printf 'ok   ecualizador: persistencia, límites, IPC y restablecimiento\n'
