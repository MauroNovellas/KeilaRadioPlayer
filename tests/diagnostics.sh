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

# shellcheck source=../lib/diagnostics.sh
source "$ROOT_DIR/lib/diagnostics.sh"

# Los contadores distinguen correctamente OK, avisos y fallos.
diagnostics_reset
diagnostics_ok 'prueba OK' >/dev/null
diagnostics_warn 'prueba aviso' >/dev/null
diagnostics_fail 'prueba fallo' >/dev/null
assert_eq '1' "$DIAGNOSTICS_OK" 'contador OK' 
assert_eq '1' "$DIAGNOSTICS_WARN" 'contador avisos'
assert_eq '1' "$DIAGNOSTICS_FAIL" 'contador fallos'

# La prueba de escritura crea y limpia su sonda sin dejar residuos.
tmp=$(mktemp -d) || fail 'no se pudo crear temporal'
trap 'rm -rf "$tmp"' EXIT

diagnostics_reset
diagnostics_check_write_dir 'Temporal' "$tmp/escribible" >/dev/null || fail 'directorio escribible rechazado'
assert_eq '1' "$DIAGNOSTICS_OK" 'directorio escribible suma OK'
[[ -d "$tmp/escribible" ]] || fail 'no se creó el directorio de prueba'
if find "$tmp/escribible" -maxdepth 1 -name '.keila-check.*' -print -quit | grep -q .; then
    fail 'la sonda de escritura dejó un archivo temporal'
fi

# Una ruta cuyo padre es un archivo debe producir fallo real.
printf 'archivo\n' > "$tmp/bloqueo"
diagnostics_reset
if diagnostics_check_write_dir 'Bloqueada' "$tmp/bloqueo/hija" >/dev/null 2>&1; then
    fail 'una ruta imposible fue aceptada como escribible'
fi
assert_eq '1' "$DIAGNOSTICS_FAIL" 'ruta imposible suma fallo'

# Probamos el orquestador sin depender de herramientas multimedia del runner.
KEILA_VERSION='2.1-test'
diagnostics_check_environment() { diagnostics_ok 'entorno simulado'; }
diagnostics_check_dependencies() { diagnostics_ok 'dependencias simuladas'; }
diagnostics_check_data() { diagnostics_ok 'datos simulados'; }
diagnostics_check_terminal() { diagnostics_warn 'terminal no interactivo simulado'; }
diagnostics_check_mpv_ipc() { diagnostics_ok 'IPC simulado'; }

status=0
output=$(diagnostics_run "$tmp") || status=$?
assert_eq '0' "$status" 'diagnóstico sin fallos devuelve éxito'
[[ "$output" == *'Resumen: 4 OK · 1 avisos · 0 fallos'* ]] || fail 'resumen de éxito incorrecto'
[[ "$output" == *'Keila está lista para ejecutarse'* ]] || fail 'mensaje final de éxito ausente'

# Un fallo inyectado debe cambiar tanto el resumen como el código de salida.
diagnostics_check_mpv_ipc() { diagnostics_fail 'IPC simulado roto'; }
status=0
output=$(diagnostics_run "$tmp") || status=$?
assert_eq '1' "$status" 'diagnóstico con fallo devuelve error'
[[ "$output" == *'1 fallos'* ]] || fail 'resumen de fallo incorrecto'
[[ "$output" == *'problemas que deben corregirse'* ]] || fail 'mensaje final de fallo ausente'

# El launcher debe despachar --check al motor nuevo, no al resumen antiguo.
set -- --version
# shellcheck source=../keila-radio
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT

CHECK_CALLED=0
diagnostics_run() {
    CHECK_CALLED=1
    return 0
}

main --check >/dev/null || fail '--check devolvió error con diagnóstico simulado'
assert_eq '1' "$CHECK_CALLED" '--check no llegó a diagnostics_run'

printf 'ok   diagnóstico de entorno, rutas y despacho de --check\n'
