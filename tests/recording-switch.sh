#!/usr/bin/env bash

# shellcheck disable=SC2317
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok() { printf 'ok   %s\n' "$1"; ((PASS += 1)); }
not_ok() { printf 'FAIL %s\n' "$1" >&2; ((FAIL += 1)); }

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    if [[ "$expected" == "$actual" ]]; then return 0; fi
    printf '  esperado: %q\n  obtenido: %q\n  %s\n' "$expected" "$actual" "$message" >&2
    return 1
}

# Cargamos el launcher sin iniciar dependencias ni TUI. Después anulamos el
# trap de cleanup porque estas pruebas sustituyen las funciones de runtime.
set -- --version
# shellcheck source=../keila-radio
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT

LAST_MESSAGE=''
LAST_TTL=''
START_CALLS=0
STOP_CALLS=0
SAVE_CALLS=0
START_NAME=''
START_URL=''

app_message() {
    LAST_MESSAGE="$1"
    LAST_TTL="${2:-5}"
}

save_player_state() {
    ((SAVE_CALLS += 1))
    return 0
}

player_start() {
    ((START_CALLS += 1))
    START_NAME="$1"
    START_URL="$2"
    PLAYER_NAME="$1"
    PLAYER_URL="$2"
    PLAYER_LAST_EXIT_STATUS=''
    return 0
}

recording_filename() { printf 'Radio_A_2026-09-06_12-20-14.ts'; }
recording_size_human() { printf '1.2 MiB'; }

reset_case() {
    LAST_MESSAGE=''
    LAST_TTL=''
    START_CALLS=0
    STOP_CALLS=0
    SAVE_CALLS=0
    START_NAME=''
    START_URL=''
    PLAYER_NAME='Radio A'
    PLAYER_URL='https://example.invalid/a'
    PLAYER_LAST_EXIT_STATUS=''
    RECORDING_LAST_ERROR=''
}

test_successful_switch_closes_recording() {
    reset_case
    RECORDING_ACTIVE=1

    recording_stop() {
        ((STOP_CALLS += 1))
        RECORDING_ACTIVE=0
        RECORDING_LAST_ERROR=''
        return 0
    }

    app_play 'Radio B' 'https://example.invalid/b' || return 1

    assert_eq '1' "$STOP_CALLS" 'la grabación se cierra una sola vez' || return 1
    assert_eq '1' "$START_CALLS" 'la nueva emisora se inicia después del cierre' || return 1
    assert_eq 'Radio B' "$START_NAME" 'se inicia la emisora solicitada' || return 1
    assert_eq '0' "$RECORDING_ACTIVE" 'la nueva emisora no empieza a grabarse automáticamente' || return 1
    assert_eq '1' "$SAVE_CALLS" 'se persiste el nuevo estado de reproducción' || return 1
    assert_eq 'Grabación guardada: Radio_A_2026-09-06_12-20-14.ts (1.2 MiB) · Conectando: Radio B' "$LAST_MESSAGE" 'el usuario ve cierre y cambio en un único mensaje' || return 1
}

test_failed_recording_close_blocks_switch() {
    reset_case
    RECORDING_ACTIVE=1

    recording_stop() {
        ((STOP_CALLS += 1))
        RECORDING_ACTIVE=0
        RECORDING_LAST_ERROR='El archivo de grabación está vacío.'
        return 1
    }

    local status=0
    app_play 'Radio B' 'https://example.invalid/b' || status=$?

    assert_eq '1' "$status" 'el cambio informa fallo si la grabación no se valida' || return 1
    assert_eq '1' "$STOP_CALLS" 'se intentó cerrar la grabación' || return 1
    assert_eq '0' "$START_CALLS" 'no se inicia otra emisora tras un cierre inválido' || return 1
    assert_eq 'Radio A' "$PLAYER_NAME" 'la emisora actual no se sustituye' || return 1
    assert_eq '0' "$SAVE_CALLS" 'no se persiste un cambio que no ocurrió' || return 1
    assert_eq 'Grabación incompleta: El archivo de grabación está vacío. No se cambia de emisora.' "$LAST_MESSAGE" 'el mensaje explica por qué se abortó el cambio' || return 1
}

test_conserved_recording_allows_switch() {
    reset_case
    RECORDING_ACTIVE=1

    recording_stop() {
        ((STOP_CALLS += 1))
        RECORDING_ACTIVE=0
        RECORDING_LAST_ERROR='mpv no confirmó el cierre, pero el archivo contiene datos.'
        return 0
    }

    app_play 'Radio B' 'https://example.invalid/b' || return 1

    assert_eq '1' "$START_CALLS" 'un archivo validado permite continuar aunque mpv no confirmase el cierre' || return 1
    assert_eq '0' "$RECORDING_ACTIVE" 'la nueva emisora sigue sin grabarse automáticamente' || return 1
    assert_eq 'Grabación conservada: Radio_A_2026-09-06_12-20-14.ts (1.2 MiB) · Conectando: Radio B' "$LAST_MESSAGE" 'el aviso distingue una grabación conservada' || return 1
}

test_normal_switch_unchanged() {
    reset_case
    RECORDING_ACTIVE=0

    recording_stop() {
        ((STOP_CALLS += 1))
        return 1
    }

    app_play 'Radio B' 'https://example.invalid/b' || return 1

    assert_eq '0' "$STOP_CALLS" 'sin grabación no se intenta cerrar nada' || return 1
    assert_eq '1' "$START_CALLS" 'el cambio normal sigue funcionando' || return 1
    assert_eq 'Conectando: Radio B' "$LAST_MESSAGE" 'el mensaje normal no cambia' || return 1
}

run_test() {
    local name="$1" fn="$2"
    if "$fn"; then ok "$name"; else not_ok "$name"; fi
}

printf 'Keila Radio Player - cambio de emisora durante grabación\n\n'
run_test 'cambio guarda la grabación y no graba la nueva emisora' test_successful_switch_closes_recording
run_test 'grabación inválida bloquea el cambio de emisora' test_failed_recording_close_blocks_switch
run_test 'grabación conservada permite el cambio' test_conserved_recording_allows_switch
run_test 'cambio normal sin grabación permanece igual' test_normal_switch_unchanged
printf '\n%d ok, %d fallos\n' "$PASS" "$FAIL"
((FAIL == 0))
