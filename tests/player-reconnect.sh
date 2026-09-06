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

assert_contains() {
    local text="$1" needle="$2" message="$3"
    [[ "$text" == *"$needle"* ]] || fail "$message: no aparece '$needle' en '$text'"
}

PLAYER_PID='1234'
PLAYER_NAME='Radio Test'
PLAYER_URL='https://example.invalid/radio'
PLAYER_PAUSED=0
PLAYER_STREAM_READY=0
PLAYER_STREAM_LAST_PROGRESS_AT=0
RECORDING_ACTIVE=0

RUNNING=1
START_SUCCESS=1
START_CALLS=0
STOP_CALLS=0
MESSAGE_CALLS=0
LAST_MESSAGE=''
TEST_NOW=100

player_is_running() { ((RUNNING)); }
player_start() {
    ((START_CALLS += 1))
    PLAYER_NAME="$1"
    PLAYER_URL="$2"
    if ((START_SUCCESS == 0)); then
        RUNNING=0
        PLAYER_PID=''
        PLAYER_STREAM_READY=0
        PLAYER_STREAM_LAST_PROGRESS_AT=0
        return 1
    fi
    RUNNING=1
    PLAYER_PID="$((5000 + START_CALLS))"
    PLAYER_STREAM_READY=0
    PLAYER_STREAM_LAST_PROGRESS_AT=0
    return 0
}
player_stop() {
    ((STOP_CALLS += 1))
    RUNNING=0
    PLAYER_PID=''
    PLAYER_STREAM_READY=0
    PLAYER_STREAM_LAST_PROGRESS_AT=0
}
player_toggle_pause() {
    if ((PLAYER_PAUSED)); then PLAYER_PAUSED=0; else PLAYER_PAUSED=1; fi
}
recording_start() { RECORDING_ACTIVE=1; }
recording_stop() { RECORDING_ACTIVE=0; }
recording_finalize_after_player_exit() { RECORDING_ACTIVE=0; }
ui_message_tick() { return 1; }
app_message() {
    LAST_MESSAGE="$1"
    ((MESSAGE_CALLS += 1))
}

# shellcheck source=lib/app-reconnect.sh
source "$ROOT_DIR/lib/app-reconnect.sh"

app_reconnect_now() { printf '%s\n' "$TEST_NOW"; }
APP_RECONNECT_STALL_TIMEOUT=5
APP_RECONNECT_START_TIMEOUT=5
APP_RECONNECT_MAX_ATTEMPTS=3
APP_RECONNECT_BASE_DELAY=2
app_reconnect_configure

reset_case() {
    TEST_NOW=100
    RUNNING=1
    START_SUCCESS=1
    START_CALLS=0
    STOP_CALLS=0
    MESSAGE_CALLS=0
    LAST_MESSAGE=''
    PLAYER_PID='1234'
    PLAYER_NAME='Radio Test'
    PLAYER_URL='https://example.invalid/radio'
    PLAYER_PAUSED=0
    PLAYER_STREAM_READY=0
    PLAYER_STREAM_LAST_PROGRESS_AT=0
    RECORDING_ACTIVE=0
    APP_RECONNECT_RECORDING_GUARD=0
    APP_RECONNECT_RECORDING_EXIT_EVENT=0
    APP_RECONNECT_AUTOMATIC_START=0
    app_reconnect_reset
}

test_never_ready_does_not_reconnect() {
    reset_case
    PLAYER_STREAM_READY=0
    PLAYER_STREAM_LAST_PROGRESS_AT=1

    if ui_message_tick; then
        fail 'un stream que nunca reprodujo provocó redibujado/reconexión'
    fi
    assert_eq '0' "$START_CALLS" 'no se reinicia una emisora que nunca estuvo lista'
    assert_eq '0' "$APP_RECONNECT_ELIGIBLE" 'no queda elegible sin reproducción real'
}

test_stall_starts_immediate_attempt() {
    reset_case
    PLAYER_STREAM_READY=1
    PLAYER_STREAM_LAST_PROGRESS_AT=90

    ui_message_tick || fail 'un estancamiento real no disparó cambio visible'
    assert_eq '1' "$START_CALLS" 'primer intento inmediato'
    assert_eq '1' "$APP_RECONNECT_ATTEMPTS" 'contador del primer intento'
    assert_eq '1' "$APP_RECONNECT_WAITING" 'queda esperando audio real del intento'
    assert_contains "$LAST_MESSAGE" 'Stream estancado' 'mensaje de estancamiento'
}

test_recovery_resets_budget() {
    reset_case
    APP_RECONNECT_ELIGIBLE=1
    APP_RECONNECT_ATTEMPTS=2
    APP_RECONNECT_WAITING=1
    APP_RECONNECT_ATTEMPT_STARTED_AT=98
    PLAYER_STREAM_READY=1
    PLAYER_STREAM_LAST_PROGRESS_AT=100

    ui_message_tick || fail 'la recuperación no provocó redibujado'
    assert_eq '0' "$APP_RECONNECT_ATTEMPTS" 'recuperación reinicia presupuesto'
    assert_eq '0' "$APP_RECONNECT_WAITING" 'recuperación cierra estado waiting'
    assert_eq '1' "$APP_RECONNECT_ELIGIBLE" 'emisora recuperada sigue siendo elegible'
    assert_contains "$LAST_MESSAGE" 'Conexión recuperada' 'mensaje de recuperación'
}

test_failed_start_uses_backoff() {
    reset_case
    APP_RECONNECT_ELIGIBLE=1
    RUNNING=0
    PLAYER_PID=''
    START_SUCCESS=0

    app_reconnect_start_attempt exit "$TEST_NOW" || fail 'fallo de arranque no fue gestionado'
    assert_eq '1' "$START_CALLS" 'primer intento ejecutado'
    assert_eq '1' "$APP_RECONNECT_ATTEMPTS" 'fallo conserva número de intento'
    assert_eq '0' "$APP_RECONNECT_WAITING" 'fallo síncrono sale de waiting'
    assert_eq '102' "$APP_RECONNECT_NEXT_AT" 'primer backoff es de dos segundos'

    TEST_NOW=101
    if ui_message_tick; then fail 'reintento ocurrió antes del backoff'; fi
    assert_eq '1' "$START_CALLS" 'no hay intento prematuro'

    TEST_NOW=102
    START_SUCCESS=1
    ui_message_tick || fail 'reintento programado no se ejecutó'
    assert_eq '2' "$START_CALLS" 'segundo intento tras backoff'
    assert_eq '2' "$APP_RECONNECT_ATTEMPTS" 'contador avanza al segundo intento'
    assert_eq '1' "$APP_RECONNECT_WAITING" 'segundo intento espera readiness'
}

test_attempt_timeout_exhausts_budget() {
    reset_case
    APP_RECONNECT_ELIGIBLE=1
    APP_RECONNECT_ATTEMPTS=3
    APP_RECONNECT_WAITING=1
    APP_RECONNECT_ATTEMPT_STARTED_AT=90
    PLAYER_STREAM_READY=0

    ui_message_tick || fail 'timeout final no provocó redibujado'
    assert_eq '1' "$STOP_CALLS" 'timeout detiene mpv acotadamente'
    assert_eq '1' "$APP_RECONNECT_EXHAUSTED" 'tercer intento agota presupuesto'
    assert_eq '0' "$APP_RECONNECT_NEXT_AT" 'no programa un cuarto intento'
    assert_contains "$LAST_MESSAGE" 'No se pudo recuperar' 'mensaje al agotar intentos'
}

test_recording_blocks_reconnect() {
    reset_case
    PLAYER_STREAM_READY=1
    PLAYER_STREAM_LAST_PROGRESS_AT=90
    RECORDING_ACTIVE=1

    ui_message_tick || fail 'estancamiento durante grabación no mostró aviso'
    assert_eq '0' "$START_CALLS" 'grabación impide reiniciar mpv'
    assert_eq '1' "$APP_RECONNECT_RECORDING_WARNED" 'aviso queda marcado para no repetirse'
    assert_contains "$LAST_MESSAGE" 'proteger el archivo' 'mensaje explica protección de grabación'

    local calls=$MESSAGE_CALLS
    if ui_message_tick; then fail 'el mismo aviso de grabación se repitió'; fi
    assert_eq "$calls" "$MESSAGE_CALLS" 'aviso de grabación solo aparece una vez'
}

test_recording_start_cancels_pending() {
    reset_case
    APP_RECONNECT_ELIGIBLE=1
    APP_RECONNECT_ATTEMPTS=1
    APP_RECONNECT_WAITING=1
    APP_RECONNECT_ATTEMPT_STARTED_AT=99

    recording_start 'Radio Test' || fail 'stub de grabación falló'
    assert_eq '1' "$RECORDING_ACTIVE" 'grabación queda activa'
    assert_eq '0' "$APP_RECONNECT_WAITING" 'grabar cancela reconexión pendiente'
    assert_eq '0' "$APP_RECONNECT_ATTEMPTS" 'grabar limpia presupuesto pendiente'
    assert_eq '1' "$APP_RECONNECT_RECORDING_GUARD" 'guard de grabación se arma inmediatamente'
}

test_recording_exit_never_autorestarts() {
    reset_case
    APP_RECONNECT_ELIGIBLE=1
    RECORDING_ACTIVE=1
    APP_RECONNECT_RECORDING_GUARD=1
    RUNNING=0
    PLAYER_PID=''

    recording_finalize_after_player_exit || fail 'finalización simulada de grabación falló'
    assert_eq '1' "$APP_RECONNECT_RECORDING_EXIT_EVENT" 'se registra caída durante grabación'

    if ui_message_tick; then fail 'evento de grabación no debe sustituir el mensaje de app_poll'; fi
    assert_eq '0' "$START_CALLS" 'caída durante grabación no auto-reconecta'
    assert_eq '0' "$APP_RECONNECT_ELIGIBLE" 'caída durante grabación desarma política'
    assert_eq '0' "$APP_RECONNECT_RECORDING_EXIT_EVENT" 'evento se consume una vez'
}

test_manual_start_resets_cycle() {
    reset_case
    APP_RECONNECT_ELIGIBLE=1
    APP_RECONNECT_ATTEMPTS=2
    APP_RECONNECT_NEXT_AT=150
    APP_RECONNECT_EXHAUSTED=1

    player_start 'Radio Manual' 'https://example.invalid/manual' || fail 'arranque manual simulado falló'
    assert_eq '0' "$APP_RECONNECT_ATTEMPTS" 'arranque manual limpia intentos'
    assert_eq '0' "$APP_RECONNECT_NEXT_AT" 'arranque manual cancela reintento programado'
    assert_eq '0' "$APP_RECONNECT_EXHAUSTED" 'arranque manual permite un ciclo futuro'
    assert_eq '0' "$APP_RECONNECT_ELIGIBLE" 'la nueva reproducción debe demostrar readiness de nuevo'
}

test_pause_cancels_and_resume_grants_grace() {
    reset_case
    APP_RECONNECT_ELIGIBLE=1
    APP_RECONNECT_ATTEMPTS=1
    APP_RECONNECT_WAITING=1

    player_toggle_pause || fail 'pausa simulada falló'
    assert_eq '1' "$PLAYER_PAUSED" 'queda pausado'
    assert_eq '0' "$APP_RECONNECT_WAITING" 'pausa cancela reconexión'
    assert_eq '0' "$APP_RECONNECT_ATTEMPTS" 'pausa limpia intentos pendientes'

    PLAYER_STREAM_READY=1
    PLAYER_STREAM_LAST_PROGRESS_AT=50
    TEST_NOW=120
    player_toggle_pause || fail 'reanudación simulada falló'
    assert_eq '0' "$PLAYER_PAUSED" 'queda reanudado'
    assert_eq '120' "$PLAYER_STREAM_LAST_PROGRESS_AT" 'reanudación concede ventana completa'
    assert_eq '1' "$APP_RECONNECT_ELIGIBLE" 'reanudación conserva elegibilidad real'
}

printf 'Keila Radio Player - reconexión automática\n\n'
test_never_ready_does_not_reconnect
printf 'ok   no reconecta antes de readiness real\n'
test_stall_starts_immediate_attempt
printf 'ok   estancamiento real inicia intento inmediato\n'
test_recovery_resets_budget
printf 'ok   recuperación reinicia presupuesto\n'
test_failed_start_uses_backoff
printf 'ok   fallos respetan backoff 2s/4s\n'
test_attempt_timeout_exhausts_budget
printf 'ok   intentos quedan acotados\n'
test_recording_blocks_reconnect
printf 'ok   grabación bloquea reinicio automático\n'
test_recording_start_cancels_pending
printf 'ok   iniciar grabación cancela reconexión pendiente\n'
test_recording_exit_never_autorestarts
printf 'ok   caída durante grabación no auto-reinicia\n'
test_manual_start_resets_cycle
printf 'ok   acción manual reinicia la política\n'
test_pause_cancels_and_resume_grants_grace
printf 'ok   pausa tiene prioridad y reanudación recibe gracia\n'
