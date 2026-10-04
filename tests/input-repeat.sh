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

source "$ROOT_DIR/lib/input.sh"

SEARCH_ACTIVE=0
input_init

# Una ráfaga de muchas D debe consumirse en una sola lectura. Se aplican como
# máximo tres pasos y la tecla diferente posterior se conserva para la siguiente
# vuelta en vez de perderse al vaciar el buffer.
exec 3< <(printf 'ddddddddddx')
input_read <&3 || fail 'no leyó ráfaga de d'
assert_eq 'KEY' "$INPUT_EVENT" 'evento de volumen'
assert_eq 'd' "$INPUT_KEY" 'tecla de volumen'
assert_eq '3' "$INPUT_REPEAT_COUNT" 'ráfaga de d limitada a tres pasos'
assert_eq 'KEY' "$INPUT_PENDING_EVENT" 'evento posterior queda pendiente'
assert_eq 'x' "$INPUT_PENDING_KEY" 'tecla posterior conservada'

input_read <&3 || fail 'no devolvió evento pendiente'
assert_eq 'KEY' "$INPUT_EVENT" 'evento pendiente recuperado'
assert_eq 'x' "$INPUT_KEY" 'tecla pendiente recuperada'
assert_eq '1' "$INPUT_REPEAT_COUNT" 'evento distinto no hereda autorepeat'
exec 3<&-

# Las secuencias ANSI de cursor también deben agruparse sin dejar cola larga.
exec 4< <(printf '\033[B\033[B\033[B\033[B\033[Bq')
input_read <&4 || fail 'no leyó ráfaga de cursor abajo'
assert_eq 'DOWN' "$INPUT_EVENT" 'cursor abajo reconocido'
assert_eq '3' "$INPUT_REPEAT_COUNT" 'cursor abajo limitado a tres pasos'
assert_eq 'KEY' "$INPUT_PENDING_EVENT" 'tecla tras cursores queda pendiente'
assert_eq 'q' "$INPUT_PENDING_KEY" 'tecla tras cursores conservada'

input_read <&4 || fail 'no devolvió tecla tras cursores'
assert_eq 'KEY' "$INPUT_EVENT" 'evento tras cursores recuperado'
assert_eq 'q' "$INPUT_KEY" 'tecla tras cursores recuperada'
assert_eq '1' "$INPUT_REPEAT_COUNT" 'tecla distinta tras cursores no hereda repetición'
exec 4<&-

# Supr llega como ESC [ 3 ~ en los emuladores habituales y se usa para
# limpiar la búsqueda sin depender de Ctrl-U.
exec 6< <(printf '\033[3~')
input_read <&6 || fail 'no leyó Supr'
assert_eq 'DELETE' "$INPUT_EVENT" 'Supr no se traduce a DELETE'
assert_eq '' "$INPUT_KEY" 'Supr no debe dejar tecla textual'
assert_eq '1' "$INPUT_REPEAT_COUNT" 'Supr no hereda autorepeat'
exec 6<&-

# La geometría asíncrona de foot no roba cifras ni teclas de la búsqueda.
SEARCH_ACTIVE=1
exec 8< <(printf 'r\033[6;16;8to\177\033[6~\n')
input_read <&8 || fail 'no leyó letra antes de geometría'
assert_eq r "$INPUT_KEY" 'letra anterior al informe conservada'
input_read <&8 || fail 'no leyó informe de celda'
assert_eq TICK "$INPUT_EVENT" 'informe no se convierte en texto'
assert_eq 16 "$INPUT_CELL_HEIGHT" 'alto de celda'
assert_eq 8 "$INPUT_CELL_WIDTH" 'ancho de celda'
input_read <&8 || fail 'no leyó letra tras geometría'
assert_eq o "$INPUT_KEY" 'letra posterior conservada'
input_read <&8 || fail 'no leyó borrado tras geometría'
assert_eq $'\177' "$INPUT_KEY" 'Retroceso posterior conservado'
input_read <&8 || fail 'no leyó Page Down'
assert_eq PAGE_DOWN "$INPUT_EVENT" 'CSI 6 tilde sigue siendo Page Down'
input_read <&8 || fail 'no leyó Enter tras geometría'
assert_eq ENTER "$INPUT_EVENT" 'Enter posterior conservado'
exec 8<&-

# Dentro del buscador una misma tecla repetida se agrupa para reducir el
# filtrado/redibujado; la tecla sigue siendo contenido de la consulta.
SEARCH_ACTIVE=1
exec 5< <(printf 'dddd')
input_read <&5 || fail 'no leyó texto de búsqueda'
assert_eq 'KEY' "$INPUT_EVENT" 'texto de búsqueda sigue siendo KEY'
assert_eq 'd' "$INPUT_KEY" 'letra de búsqueda correcta'
assert_eq '4' "$INPUT_REPEAT_COUNT" 'texto repetido se conserva completo'
exec 5<&-
# Ejercicio de extremo a extremo: lectura real, Unicode, repetición, borrado
# y Enter. Un drenaje pequeño fuerza varias ráfagas sin perder ningún byte.
source "$ROOT_DIR/lib/app-search.sh"
SEARCH_ACTIVE=1 SEARCH_QUERY='' INPUT_REPEAT_DRAIN_LIMIT=2
exec 7< <(printf 'áááááááááááá\177\177\177\177\177rock\n')
search_reads=0
while input_read <&7; do
    ((search_reads += 1))
    [[ $INPUT_EVENT != ENTER ]] || break
    [[ $INPUT_EVENT != KEY ]] || search_handle_key "$INPUT_KEY" || true
done
exec 7<&-
assert_eq 'ááááááárock' "$SEARCH_QUERY" 'pegado y borrado conservan todo el texto'
assert_eq ENTER "$INPUT_EVENT" 'Enter posterior no se pierde'
((search_reads < 22)) || fail 'no reduce operaciones de edición'
INPUT_REPEAT_DRAIN_LIMIT=512
SEARCH_ACTIVE=0

# Los valores internos se validan sin command substitution por pulsación.
input_repeat_cap_value state
input_repeat_drain_limit_value state
assert_eq 3 "$INPUT_CAP_VALUE" 'límite de navegación por estado'
assert_eq 512 "$INPUT_DRAIN_LIMIT_VALUE" 'límite de drenaje por estado'
for setting in invalid 0 9999; do
    INPUT_REPEAT_CAP=$setting INPUT_REPEAT_DRAIN_LIMIT=$setting
    input_repeat_cap_value state
    input_repeat_drain_limit_value state
    case $setting in
        invalid) expected_cap=3 expected_limit=512 ;;
        0) expected_cap=1 expected_limit=1 ;;
        9999) expected_cap=8 expected_limit=4096 ;;
    esac
    assert_eq "$expected_cap" "$INPUT_CAP_VALUE" 'validación de cap sin fork'
    assert_eq "$expected_limit" "$INPUT_DRAIN_LIMIT_VALUE" 'validación de drenaje sin fork'
done
INPUT_REPEAT_CAP=3 INPUT_REPEAT_DRAIN_LIMIT=512
cap_definition=$(declare -f input_repeat_cap_value)
drain_definition=$(declare -f input_repeat_drain_limit_value)
eval "${cap_definition/input_repeat_cap_value ()/original_cap ()}"
eval "${drain_definition/input_repeat_drain_limit_value ()/original_drain ()}"
# Definiciones de prueba constantes: se sustituyen después de ejercitar las
# originales cargadas desde input.sh, igual que las clonaciones anteriores.
eval 'input_repeat_cap_value() { ((BASH_SUBSHELL == 0)) || fail "cap lanza un subshell por tecla"; original_cap "$@"; }'
eval 'input_repeat_drain_limit_value() { ((BASH_SUBSHELL == 0)) || fail "drenaje lanza un subshell por tecla"; original_drain "$@"; }'
exec 9< <(printf 'dd')
input_read <&9 || fail 'lectura sin forks'
exec 9<&-
assert_eq 3 "$INPUT_CAP_VALUE" 'estado modificado en el proceso principal'

# Prueba los wrappers finales que convierten el contador agrupado en un único
# movimiento/cambio de volumen por frame. Se invocan indirectamente al clonar
# sus definiciones con declare -f/eval, algo que ShellCheck no puede seguir.
# shellcheck disable=SC2317
ui_enter() { return 0; }
# shellcheck disable=SC2317
ui_suspend() { return 0; }
# shellcheck disable=SC2317
ui_resume() { return 0; }
# shellcheck disable=SC2317
ui_leave() { return 0; }

UI_MOVE_TOTAL=0
PLAYER_VOLUME_TOTAL=50
SEARCH_MOVE_TOTAL=0

# shellcheck disable=SC2317
ui_move_selection() {
    UI_MOVE_TOTAL=$((UI_MOVE_TOTAL + $1))
}

# shellcheck disable=SC2317
player_change_volume() {
    PLAYER_VOLUME_TOTAL=$((PLAYER_VOLUME_TOTAL + $1))
}

# shellcheck disable=SC2317
search_move() {
    SEARCH_MOVE_TOTAL=$((SEARCH_MOVE_TOTAL + $1))
}

source "$ROOT_DIR/lib/ui-terminal-guard.sh"

INPUT_REPEAT_COUNT=3
ui_move_selection 1
player_change_volume 5
search_move -1

assert_eq '3' "$UI_MOVE_TOTAL" 'tres repeticiones se aplican en un movimiento único'
assert_eq '65' "$PLAYER_VOLUME_TOTAL" 'volumen aplica tres pasos en una operación'
assert_eq '-3' "$SEARCH_MOVE_TOTAL" 'búsqueda aplica tres movimientos en una operación'

input_shutdown
printf 'ok   input: autorepeat se agrupa, limita y no deja cola atrasada\n'
