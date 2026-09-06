#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

# shellcheck source=lib/player.sh
source "$ROOT_DIR/lib/player.sh"

success_response='{"data":null,"request_id":1001,"error":"success"}'
player_ipc_response_success "$success_response" 1001 || fail 'respuesta success con request_id correcto fue rechazada'

error_response='{"data":null,"request_id":1001,"error":"property unavailable"}'
if player_ipc_response_success "$error_response" 1001; then
    fail 'respuesta de error de mpv fue aceptada como éxito'
fi

wrong_id_response='{"data":null,"request_id":9999,"error":"success"}'
if player_ipc_response_success "$wrong_id_response" 1001; then
    fail 'respuesta success de otro request_id fue aceptada'
fi

if player_ipc_response_success 'no-es-json' 1001; then
    fail 'respuesta IPC inválida fue aceptada'
fi

# player_ipc debe añadir su propio request_id al payload y exigir la respuesta
# que corresponde exactamente a ese ID.
PLAYER_IPC_REQUEST_ID=2000
player_ipc_exchange() {
    local payload="$1"
    jq -e '.command == ["cycle", "pause"] and .request_id == 2001' <<< "$payload" >/dev/null || return 1
    printf '%s\n' '{"data":null,"request_id":2001,"error":"success"}'
}
player_ipc '{"command":["cycle","pause"]}' || fail 'player_ipc no aceptó confirmación válida de mpv'
assert_eq '2001' "$PLAYER_IPC_REQUEST_ID" 'contador de request_id'

player_ipc_exchange() {
    local payload="$1"
    local request_id
    request_id=$(jq -r '.request_id' <<< "$payload") || return 1
    printf '{"data":null,"request_id":%s,"error":"command error"}\n' "$request_id"
}
if player_ipc '{"command":["cycle","pause"]}'; then
    fail 'player_ipc ocultó un rechazo explícito de mpv'
fi

player_ipc_exchange() { return 1; }
if player_ipc '{"command":["cycle","pause"]}'; then
    fail 'player_ipc ocultó un fallo de transporte'
fi

# Si mpv rechaza el volumen, el estado interno debe seguir representando el
# volumen que realmente estaba aplicado antes del intento.
player_is_running() { return 0; }
PLAYER_VOLUME=50
player_ipc() { return 1; }
if player_set_volume 75; then
    fail 'player_set_volume informó éxito aunque IPC falló'
fi
assert_eq '50' "$PLAYER_VOLUME" 'volumen interno tras fallo IPC'

player_ipc() { return 0; }
player_set_volume 75 || fail 'player_set_volume rechazó una confirmación válida'
assert_eq '75' "$PLAYER_VOLUME" 'volumen interno tras éxito IPC'

# Pausa ya aplicaba el mismo principio; queda cubierta para evitar regresiones.
PLAYER_PAUSED=0
player_ipc() { return 1; }
if player_toggle_pause; then
    fail 'player_toggle_pause informó éxito aunque IPC falló'
fi
assert_eq '0' "$PLAYER_PAUSED" 'estado de pausa tras fallo IPC'

player_ipc() { return 0; }
player_toggle_pause || fail 'player_toggle_pause rechazó una confirmación válida'
assert_eq '1' "$PLAYER_PAUSED" 'estado de pausa tras éxito IPC'

printf 'ok   player: valida respuesta IPC y conserva estado ante rechazos de mpv\n'
