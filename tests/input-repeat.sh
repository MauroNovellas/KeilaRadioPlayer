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
exec 4<&-

# Dentro del buscador las letras son contenido de la consulta, no acciones de
# navegación/volumen, por lo que nunca deben agruparse aunque sean iguales.
SEARCH_ACTIVE=1
exec 5< <(printf 'dddd')
input_read <&5 || fail 'no leyó texto de búsqueda'
assert_eq 'KEY' "$INPUT_EVENT" 'texto de búsqueda sigue siendo KEY'
assert_eq 'd' "$INPUT_KEY" 'letra de búsqueda correcta'
assert_eq '1' "$INPUT_REPEAT_COUNT" 'texto repetido no se coalesce en búsqueda'
exec 5<&-
SEARCH_ACTIVE=0

# Prueba los wrappers finales que convierten el contador agrupado en un único
# movimiento/cambio de volumen por frame.
ui_enter() { return 0; }
ui_suspend() { return 0; }
ui_resume() { return 0; }
ui_leave() { return 0; }

UI_MOVE_TOTAL=0
PLAYER_VOLUME_TOTAL=50
SEARCH_MOVE_TOTAL=0

ui_move_selection() {
    UI_MOVE_TOTAL=$((UI_MOVE_TOTAL + $1))
}

player_change_volume() {
    PLAYER_VOLUME_TOTAL=$((PLAYER_VOLUME_TOTAL + $1))
}

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
