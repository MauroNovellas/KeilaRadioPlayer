#!/usr/bin/env bash

set -uo pipefail
# Los stubs se invocan indirectamente desde wrappers creados con declare -f.
# shellcheck disable=SC2317

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/player.sh"
source "$ROOT_DIR/lib/player-events.sh"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

PLAYER_EVENTS_DIRTY=0
PLAYER_EVENTS_PROPERTY_CHANGES=0
PLAYER_EVENTS_LAST_AT=0
player_events_now() { printf '1234\n'; }

player_events_handle_line '{"event":"property-change","id":201,"name":"paused-for-cache","data":true}' || \
    fail 'property-change conocido no fue aceptado'
assert_eq '1' "$PLAYER_EVENTS_DIRTY" 'evento conocido marca snapshot pendiente'
assert_eq '1' "$PLAYER_EVENTS_PROPERTY_CHANGES" 'evento conocido incrementa contador'
assert_eq '1234' "$PLAYER_EVENTS_LAST_AT" 'evento conocido guarda instante'

PLAYER_EVENTS_DIRTY=0
if player_events_handle_line '{"error":"success","request_id":77}'; then
    fail 'respuesta normal de comando fue tratada como cambio de propiedad'
fi
assert_eq '0' "$PLAYER_EVENTS_DIRTY" 'respuesta normal no marca snapshot'

if player_events_handle_line '{"event":"property-change","name":"audio-pts","data":8.5}'; then
    fail 'audio-pts no debe observarse como evento discreto'
fi
assert_eq '0' "$PLAYER_EVENTS_DIRTY" 'audio-pts no marca snapshot por eventos'

if player_events_handle_line '{"event":"property-change","name":"unknown-property","data":1}'; then
    fail 'propiedad desconocida fue aceptada'
fi
if player_events_handle_line 'no-json'; then
    fail 'JSON malformado fue aceptado'
fi

PLAYER_EVENTS_DRAIN_LIMIT=1
player_events_configure
assert_eq '8' "$PLAYER_EVENTS_DRAIN_LIMIT" 'límite mínimo de drain'
PLAYER_EVENTS_DRAIN_LIMIT=999
player_events_configure
assert_eq '256' "$PLAYER_EVENTS_DRAIN_LIMIT" 'límite máximo de drain'
PLAYER_EVENTS_DRAIN_LIMIT=64

# Un evento invalida el throttle antes de delegar al snapshot existente.
TEST_REFRESH_LAST=''
TEST_DRAIN_DIRTY=1
player_events_drain() {
    if ((TEST_DRAIN_DIRTY)); then
        PLAYER_EVENTS_DIRTY=1
        return 0
    fi
    return 1
}
player_refresh_info_without_events() {
    TEST_REFRESH_LAST="$PLAYER_INFO_LAST_REFRESH"
    return 0
}

PLAYER_INFO_LAST_REFRESH=99
PLAYER_EVENTS_DIRTY=0
player_refresh_info || fail 'refresh envuelto falló con evento pendiente'
assert_eq '0' "$TEST_REFRESH_LAST" 'evento fuerza snapshot inmediato'
assert_eq '0' "$PLAYER_EVENTS_DIRTY" 'evento pendiente se consume una vez'

TEST_DRAIN_DIRTY=0
PLAYER_INFO_LAST_REFRESH=77
player_refresh_info || fail 'refresh envuelto falló sin evento'
assert_eq '77' "$TEST_REFRESH_LAST" 'sin evento conserva throttle existente'

# Arranque: los eventos son optimización. Nunca convierten un playback válido en
# fallo si el listener persistente no puede iniciar.
TEST_SEQUENCE=''
TEST_START_STATUS=0
TEST_EVENTS_START_STATUS=0
player_events_stop() {
    TEST_SEQUENCE+="stop-events>"
    PLAYER_EVENTS_ACTIVE=0
    return 0
}
player_start_without_events() {
    TEST_SEQUENCE+="start-player>"
    return "$TEST_START_STATUS"
}
player_events_start() {
    TEST_SEQUENCE+="start-events>"
    ((TEST_EVENTS_START_STATUS == 0)) && PLAYER_EVENTS_ACTIVE=1
    return "$TEST_EVENTS_START_STATUS"
}

TEST_SEQUENCE=''
TEST_START_STATUS=0
TEST_EVENTS_START_STATUS=0
player_start 'Radio Test' 'https://example.invalid/radio' || fail 'arranque válido falló'
assert_eq 'stop-events>start-player>start-events>' "$TEST_SEQUENCE" 'arranque inicia eventos después del player'
assert_eq '1' "$PLAYER_EVENTS_ACTIVE" 'listener activo tras arranque correcto'

TEST_SEQUENCE=''
TEST_START_STATUS=0
TEST_EVENTS_START_STATUS=1
player_start 'Radio Test' 'https://example.invalid/radio' || fail 'fallo opcional del listener rompió playback'
assert_eq 'stop-events>start-player>start-events>' "$TEST_SEQUENCE" 'intenta listener sin alterar playback'

TEST_SEQUENCE=''
TEST_START_STATUS=7
TEST_EVENTS_START_STATUS=0
if player_start 'Radio Test' 'https://example.invalid/radio'; then
    fail 'fallo del player fue ocultado por capa de eventos'
fi
assert_eq 'stop-events>start-player>' "$TEST_SEQUENCE" 'no inicia eventos si player falla'

# Stop cierra primero el cliente persistente y después detiene mpv.
player_stop_without_events() {
    TEST_SEQUENCE+="stop-player>"
    return 0
}
TEST_SEQUENCE=''
player_stop || fail 'stop envuelto falló'
assert_eq 'stop-events>stop-player>' "$TEST_SEQUENCE" 'stop cierra eventos antes de mpv'

printf 'ok   player: eventos mpv discretos aceleran snapshots con polling de respaldo\n'
