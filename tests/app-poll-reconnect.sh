#!/usr/bin/env bash

# shellcheck disable=SC2317
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

set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT

RUNNING=0
PLAYER_PID=1234
PLAYER_LAST_EXIT_STATUS=7
PLAYER_NAME='Radio Test'
PLAYER_URL='https://example.invalid/radio'
RECORDING_ACTIVE=0
APP_RECONNECT_ELIGIBLE=0
LAST_MESSAGE=''

player_is_running() { ((RUNNING)); }
player_collect_exit_status() {
    PLAYER_PID=''
    return 0
}
history_observe() { return 1; }
spectrum_tick() { return 1; }
recording_tick_changed() { return 1; }
app_message() { LAST_MESSAGE="$1"; }

app_poll_player || true
[[ "$LAST_MESSAGE" == *'se detuvo inesperadamente'* ]] || fail 'una caída sin reconexión no mostró su error'

RUNNING=0
PLAYER_PID=1234
PLAYER_LAST_EXIT_STATUS=7
APP_RECONNECT_ELIGIBLE=1
PLAYER_PAUSED=0
LAST_MESSAGE=''
app_poll_player || true
assert_eq '' "$LAST_MESSAGE" 'la caída elegible no mostró un error genérico'

RUNNING=0
PLAYER_PID=1234
PLAYER_LAST_EXIT_STATUS=7
APP_RECONNECT_ELIGIBLE=1
PLAYER_PAUSED=1
LAST_MESSAGE=''
app_poll_player || true
[[ "$LAST_MESSAGE" == *'se detuvo inesperadamente'* ]] || fail 'una caída pausada ocultó su error'

printf 'ok   app: la reconexión evita el destello de error genérico\n'
