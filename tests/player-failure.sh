#!/usr/bin/env bash

set -uo pipefail
# Los stubs de esta regresión son invocados indirectamente por wrappers.
# shellcheck disable=SC2317

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT

source "$ROOT_DIR/lib/player.sh"
PLAYER_RUNTIME_DIR="$TMP_ROOT/runtime"
PLAYER_SOCKET="$PLAYER_RUNTIME_DIR/player.sock"
source "$ROOT_DIR/lib/player-failure.sh"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

player_failure_set stream_stalled 'prueba'
assert_eq 'stream_stalled' "$PLAYER_FAILURE_REASON" 'set conserva código estable'
[[ "$PLAYER_FAILURE_AT" =~ ^[0-9]+$ ]] || fail 'set no guardó timestamp'
assert_eq 'stream sin progreso' "$(player_failure_description)" 'descripción de código conocida'
player_failure_clear
assert_eq '' "$PLAYER_FAILURE_REASON" 'clear elimina motivo'
assert_eq '0' "$PLAYER_FAILURE_AT" 'clear elimina timestamp'

# Transporte IPC roto.
player_ipc_exchange() { return 1; }
if player_ipc '{"command":["quit"]}'; then
    fail 'IPC con transporte roto fue aceptado'
fi
assert_eq 'ipc_transport' "$PLAYER_FAILURE_REASON" 'clasifica transporte IPC'

# mpv responde al request correcto pero rechaza el comando.
player_ipc_exchange() {
    local payload="$1" request_id
    request_id=$(jq -r '.request_id' <<< "$payload")
    printf '{"error":"property unavailable","request_id":%s}\n' "$request_id"
}
if player_ipc '{"command":["get_property","does-not-exist"]}'; then
    fail 'IPC rechazado por mpv fue aceptado'
fi
assert_eq 'ipc_rejected' "$PLAYER_FAILURE_REASON" 'clasifica rechazo explícito de mpv'
assert_eq 'property unavailable' "$PLAYER_FAILURE_DETAIL" 'conserva detalle de rechazo'
assert_eq 'property unavailable' "$PLAYER_LAST_IPC_ERROR" 'conserva último error IPC'

# Respuesta válida como JSON pero para otro request_id.
player_ipc_exchange() {
    printf '%s\n' '{"error":"success","request_id":999999}'
}
if player_ipc '{"command":["get_property","pause"]}'; then
    fail 'respuesta con request_id incorrecto fue aceptada'
fi
assert_eq 'ipc_response' "$PLAYER_FAILURE_REASON" 'clasifica respuesta IPC no correlacionada'

# Una respuesta correcta limpia únicamente un fallo IPC previo.
player_ipc_exchange() {
    local payload="$1" request_id
    request_id=$(jq -r '.request_id' <<< "$payload")
    printf '{"error":"success","data":false,"request_id":%s}\n' "$request_id"
}
player_ipc '{"command":["get_property","pause"]}' || fail 'IPC correcto fue rechazado'
assert_eq '' "$PLAYER_FAILURE_REASON" 'IPC recuperado limpia fallo IPC'

# Arranque: precondiciones y fallo de socket reciben códigos distintos.
if player_start 'Radio Test' ''; then
    fail 'URL vacía fue aceptada'
fi
assert_eq 'invalid_url' "$PLAYER_FAILURE_REASON" 'clasifica URL vacía'

mkdir -p "$TMP_ROOT/block"
: > "$TMP_ROOT/block/file"
PLAYER_RUNTIME_DIR="$TMP_ROOT/block/file/child"
if player_start 'Radio Test' 'https://example.invalid/radio'; then
    fail 'runtime imposible fue aceptado'
fi
assert_eq 'runtime_dir' "$PLAYER_FAILURE_REASON" 'clasifica runtime no creable'

PLAYER_RUNTIME_DIR="$TMP_ROOT/runtime"
player_start_without_failure_state() {
    PLAYER_LAST_EXIT_STATUS=77
    return 1
}
if player_start 'Radio Test' 'https://example.invalid/radio'; then
    fail 'fallo simulado de arranque fue aceptado'
fi
assert_eq 'startup_socket' "$PLAYER_FAILURE_REASON" 'clasifica fallo de socket inicial'
assert_eq '77' "$PLAYER_FAILURE_EXIT_STATUS" 'conserva exit status de arranque'

player_start_without_failure_state() { return 0; }
player_failure_set startup_socket 'antiguo' 77
player_start 'Radio Test' 'https://example.invalid/radio' || fail 'arranque simulado correcto falló'
assert_eq '' "$PLAYER_FAILURE_REASON" 'arranque correcto limpia fallo anterior'

player_collect_exit_status_without_failure_state() {
    PLAYER_LAST_EXIT_STATUS=42
    return 0
}
player_collect_exit_status || fail 'collect simulado falló'
assert_eq 'process_exit' "$PLAYER_FAILURE_REASON" 'clasifica salida inesperada'
assert_eq '42' "$PLAYER_FAILURE_EXIT_STATUS" 'salida inesperada conserva exit status'

player_stop_without_failure_state() { return 0; }
player_stop || fail 'stop simulado falló'
assert_eq '' "$PLAYER_FAILURE_REASON" 'stop intencional limpia fallo vivo'

# Observadores de reconexión. La política está cubierta por player-reconnect.sh;
# aquí solo verificamos que sus transiciones generen códigos estructurados.
APP_RECONNECT_WAITING=0
APP_RECONNECT_EXHAUSTED=0
APP_RECONNECT_RECORDING_WARNED=0
APP_RECONNECT_ATTEMPTS=0
APP_RECONNECT_NEXT_AT=0
APP_RECONNECT_MAX_ATTEMPTS=3
APP_RECONNECT_STALL_TIMEOUT=15
APP_RECONNECT_START_TIMEOUT=12
PLAYER_STREAM_READY=0
PLAYER_NAME='Radio Test'
TEST_PLAYER_RUNNING=1
TEST_MESSAGE_EXHAUSTED=0
TEST_TICK_MODE='none'

app_reconnect_now() { printf '100\n'; }
app_message() { return 0; }
player_is_running() { ((TEST_PLAYER_RUNNING)); }

app_reconnect_message_retry_or_exhausted() {
    if ((TEST_MESSAGE_EXHAUSTED)); then
        APP_RECONNECT_EXHAUSTED=1
    fi
    return 0
}

app_reconnect_start_attempt() {
    APP_RECONNECT_ATTEMPTS=$((APP_RECONNECT_ATTEMPTS + 1))
    APP_RECONNECT_WAITING=1
    return 0
}

app_reconnect_tick() {
    case "$TEST_TICK_MODE" in
        recover)
            APP_RECONNECT_WAITING=0
            APP_RECONNECT_ATTEMPTS=0
            APP_RECONNECT_NEXT_AT=0
            APP_RECONNECT_EXHAUSTED=0
            PLAYER_STREAM_READY=1
            TEST_PLAYER_RUNNING=1
            ;;
        timeout)
            APP_RECONNECT_WAITING=0
            APP_RECONNECT_NEXT_AT=150
            APP_RECONNECT_EXHAUSTED=0
            PLAYER_STREAM_READY=0
            TEST_PLAYER_RUNNING=0
            ;;
        recording_warn)
            APP_RECONNECT_RECORDING_WARNED=1
            ;;
    esac
    return 0
}

source "$ROOT_DIR/lib/app-reconnect-failure.sh"

APP_RECONNECT_WAITING=0
APP_RECONNECT_ATTEMPTS=0
TEST_PLAYER_RUNNING=1
app_reconnect_start_attempt stall 100 || fail 'wrapper stall falló'
assert_eq 'stream_stalled' "$PLAYER_FAILURE_REASON" 'estancamiento genera código estructurado'

APP_RECONNECT_WAITING=0
app_reconnect_start_attempt retry 100 || fail 'wrapper retry falló'
assert_eq 'reconnect_retry' "$PLAYER_FAILURE_REASON" 'retry genera código estructurado'

APP_RECONNECT_WAITING=0
APP_RECONNECT_EXHAUSTED=0
TEST_MESSAGE_EXHAUSTED=1
app_reconnect_message_retry_or_exhausted 'Radio Test' 100 || fail 'wrapper exhausted falló'
assert_eq 'reconnect_exhausted' "$PLAYER_FAILURE_REASON" 'agotamiento genera código estructurado'
TEST_MESSAGE_EXHAUSTED=0

APP_RECONNECT_WAITING=1
APP_RECONNECT_ATTEMPTS=2
APP_RECONNECT_NEXT_AT=0
APP_RECONNECT_EXHAUSTED=0
TEST_TICK_MODE='timeout'
app_reconnect_tick || fail 'tick timeout simulado falló'
assert_eq 'reconnect_start_timeout' "$PLAYER_FAILURE_REASON" 'timeout de audio genera código estructurado'

APP_RECONNECT_RECORDING_WARNED=0
TEST_TICK_MODE='recording_warn'
app_reconnect_tick || fail 'tick de grabación simulado falló'
assert_eq 'stream_stalled' "$PLAYER_FAILURE_REASON" 'estancamiento durante grabación conserva categoría stream'
[[ "$PLAYER_FAILURE_DETAIL" == *'grabación'* ]] || fail 'detalle no explica bloqueo por grabación'

APP_RECONNECT_WAITING=1
APP_RECONNECT_ATTEMPTS=2
APP_RECONNECT_NEXT_AT=0
APP_RECONNECT_EXHAUSTED=0
PLAYER_STREAM_READY=0
TEST_TICK_MODE='recover'
player_failure_set reconnect_retry 'pendiente'
app_reconnect_tick || fail 'tick de recuperación simulado falló'
assert_eq '' "$PLAYER_FAILURE_REASON" 'recuperación real limpia fallo estructurado'

printf 'ok   player: estado estructurado de fallos e integración con reconexión\n'
