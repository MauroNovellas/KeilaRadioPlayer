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

# Carga el launcher sin arrancar TUI ni dependencias y conserva la definición
# real del selector integrado antes de sustituirla en las pruebas del wrapper.
set -- --version
# shellcheck source=../keila-radio
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT

INTEGRATED_SELECTOR_DEF=$(declare -f stations_select_fzf)

SUSPEND_CALLS=0
RESUME_CALLS=0
PLAY_CALLS=0
SELECT_STATUS=1
LAST_MESSAGE=''

# shellcheck disable=SC2317
ui_suspend() {
    ((SUSPEND_CALLS += 1))
    UI_SUSPENDED=1
}

# shellcheck disable=SC2317
ui_resume() {
    ((RESUME_CALLS += 1))
    UI_SUSPENDED=0
}

# shellcheck disable=SC2317
stations_select_fzf() {
    return "$SELECT_STATUS"
}

# shellcheck disable=SC2317
app_message() {
    LAST_MESSAGE="$1"
}

# shellcheck disable=SC2317
app_play() {
    ((PLAY_CALLS += 1))
    return 0
}

# El buscador integrado debe permanecer dentro de la TUI activa: ninguna
# suspensión, reanudación ni clear indirecto al pulsar B o volver con Esc.
KEILA_FZF_SEARCH=0
app_search_catalog || fail 'el wrapper integrado devolvió error'
assert_eq 0 "$SUSPEND_CALLS" 'B integrado no suspende la TUI'
assert_eq 0 "$RESUME_CALLS" 'B integrado no reanuda/limpia la TUI'
assert_eq 0 "$PLAY_CALLS" 'cancelar búsqueda no reproduce otra emisora'

# El fallback externo conserva el comportamiento clásico porque fzf sí necesita
# el control directo de la terminal.
SUSPEND_CALLS=0
RESUME_CALLS=0
KEILA_FZF_SEARCH=1
app_search_catalog || fail 'el wrapper fzf devolvió error'
assert_eq 1 "$SUSPEND_CALLS" 'fzf suspende la TUI'
assert_eq 1 "$RESUME_CALLS" 'fzf reanuda la TUI'

# Comprueba también la implementación real del selector integrado: el primer
# render no debe llamar por su cuenta a ui_resume cuando la TUI ya está activa.
eval "$INTEGRATED_SELECTOR_DEF"

DRAW_CALLS=0
RESUME_CALLS=0
UI_SUSPENDED=0
KEILA_FZF_SEARCH=0

# shellcheck disable=SC2317
stations_catalog_valid() { return 0; }
# shellcheck disable=SC2317
search_open() { SEARCH_ACTIVE=1; return 0; }
# shellcheck disable=SC2317
favorites_confirm_clear() { return 0; }
# shellcheck disable=SC2317
ui_clear_message() { return 0; }
# shellcheck disable=SC2317
search_draw_view() { ((DRAW_CALLS += 1)); return 0; }
# shellcheck disable=SC2317
input_read() { return 1; }
# shellcheck disable=SC2317
search_close() { SEARCH_ACTIVE=0; return 0; }

selector_status=0
stations_select_fzf || selector_status=$?
assert_eq 1 "$selector_status" 'EOF simulado cierra el buscador integrado'
assert_eq 1 "$DRAW_CALLS" 'el buscador pinta una vez al entrar'
assert_eq 0 "$RESUME_CALLS" 'el selector integrado no ejecuta ui_resume'

printf 'ok   búsqueda integrada: transición sin suspend/resume ni borrado completo\n'
