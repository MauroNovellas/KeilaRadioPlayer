#!/usr/bin/env bash

# shellcheck disable=SC2317
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/recording.sh
source "$ROOT_DIR/lib/recording.sh"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

tmp=$(mktemp -d) || fail 'no se pudo crear temporal'
trap 'rm -rf "$tmp"' EXIT

# Inexistente y vacío siguen siendo fallos reales.
missing="$tmp/no-existe.ts"
if recording_verify_file "$missing" >/dev/null 2>&1; then
    fail 'un archivo inexistente fue aceptado'
fi
assert_eq '0' "$RECORDING_LAST_VALID" 'inexistente no es válido'
assert_eq '0' "$RECORDING_LAST_VERIFIED" 'inexistente no queda verificado'

empty="$tmp/vacio.ts"
: > "$empty"
if recording_verify_file "$empty" >/dev/null 2>&1; then
    fail 'un archivo vacío fue aceptado'
fi
assert_eq '0' "$RECORDING_LAST_VALID" 'vacío no es válido'
assert_eq '0' "$RECORDING_LAST_VERIFIED" 'vacío no queda verificado'

# Un archivo con datos y probe correcto queda validado y verificado.
good="$tmp/bueno.ts"
printf 'datos simulados de audio\n' > "$good"
recording_probe_file() { return 0; }
recording_verify_file "$good" || fail 'un archivo reproducible fue rechazado'
assert_eq '1' "$RECORDING_LAST_VALID" 'archivo con datos es válido'
assert_eq '1' "$RECORDING_LAST_VERIFIED" 'probe correcto marca reproducible'
assert_eq '' "$RECORDING_LAST_ERROR" 'probe correcto no deja aviso'

# Un probe negativo no destruye ni rechaza un archivo con datos: se conserva,
# pero queda explícitamente como no verificado.
suspicious="$tmp/sospechoso.ts"
printf 'datos no confirmados\n' > "$suspicious"
recording_probe_file() { return 1; }
recording_verify_file "$suspicious" || fail 'un archivo con datos fue descartado por probe negativo'
assert_eq '1' "$RECORDING_LAST_VALID" 'probe negativo conserva archivo con datos'
assert_eq '0' "$RECORDING_LAST_VERIFIED" 'probe negativo no marca reproducible'
[[ "$RECORDING_LAST_ERROR" == *'no pudo confirmar audio reproducible'* ]] || fail 'probe negativo no explica el estado'

# Timeout/ausencia del probe también conserva el archivo, distinguiendo la falta
# de verificación de un fallo duro de grabación.
unverified="$tmp/no-verificado.ts"
printf 'datos pendientes de verificar\n' > "$unverified"
recording_probe_file() { return 2; }
recording_verify_file "$unverified" || fail 'un probe no disponible descartó un archivo con datos'
assert_eq '1' "$RECORDING_LAST_VALID" 'probe no disponible conserva archivo'
assert_eq '0' "$RECORDING_LAST_VERIFIED" 'probe no disponible no marca reproducible'
[[ "$RECORDING_LAST_ERROR" == *'no se pudo completar la verificación'* ]] || fail 'probe no disponible no deja aviso útil'

printf 'ok   grabación: tamaño mínimo + verificación reproducible conservadora\n'
