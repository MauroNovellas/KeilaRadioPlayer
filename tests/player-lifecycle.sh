#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

# shellcheck source=lib/player.sh
source "$ROOT_DIR/lib/player.sh"

PLAYER_RUNTIME_DIR="$TMP_ROOT/runtime"
PLAYER_SOCKET="$PLAYER_RUNTIME_DIR/mpv-test.sock"
mkdir -p "$PLAYER_RUNTIME_DIR"

# Simula un mpv que sigue vivo pero nunca crea el socket IPC. Antes del fix,
# player_start hacía wait directamente y podía quedar bloqueado hasta que ese
# proceso terminara por su cuenta.
mpv() {
    exec sleep 30
}
player_wait_for_socket() { return 1; }

SECONDS=0
status=0
player_start 'Radio Test' 'https://example.invalid/stream' 2>/dev/null || status=$?
elapsed=$SECONDS

[[ "$status" -eq 1 ]] || fail 'player_start no informó fallo al faltar el socket IPC'
((elapsed < 3)) || fail "player_start tardó demasiado en abortar: ${elapsed}s"
[[ -z "$PLAYER_PID" ]] || fail 'player_start dejó PLAYER_PID tras abortar'
[[ -n "$PLAYER_LAST_EXIT_STATUS" ]] || fail 'player_start no conservó estado de salida del proceso abortado'
[[ ! -e "$PLAYER_SOCKET" ]] || fail 'player_start dejó socket residual tras abortar'

# Comprueba también la escalada a SIGKILL cuando el proceso ignora SIGTERM.
bash -c 'trap "" TERM; exec sleep 30' &
stubborn_pid=$!
SECONDS=0
player_terminate_pid_bounded "$stubborn_pid" || fail 'terminación acotada devolvió error'
wait "$stubborn_pid" 2>/dev/null || true
elapsed=$SECONDS

((elapsed < 3)) || fail "proceso resistente no fue terminado de forma acotada: ${elapsed}s"
if kill -0 "$stubborn_pid" 2>/dev/null; then
    fail 'proceso resistente sigue vivo después de la terminación acotada'
fi

printf 'ok   player: fallo de arranque y terminación quedan acotados\n'

# Verificar los argumentos reales de arranque, sin audio ni conexión.
mpv() { printf '%s\n' "$@" > "$TMP_ROOT/args"; }
player_wait_for_socket() { wait "$PLAYER_PID"; }
PLAYER_VOLUME=37 PLAYER_MUTED=1 APP_RECONNECT_AUTOMATIC_START=1
player_start Radio https://example.invalid/radio || fail 'arranque automático'
args=$(<"$TMP_ROOT/args")
[[ "$args" == *'--mute=yes'* && "$args" == *'--volume=37'* ]] || fail 'reconexión pierde silencio/volumen'
APP_RECONNECT_AUTOMATIC_START=0
player_start Otra https://example.invalid/otra || fail 'cambio manual'
args=$(<"$TMP_ROOT/args")
[[ "$args" == *'--mute=no'* ]] || fail 'selección manual queda silenciada'
player_stop
