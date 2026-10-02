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
stations_tsv_valid() { return 0; }
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

# Atajos reales del bucle: X gestiona el resultado, F/R salen sin reproducir.
SEARCH_X_CALLS=0
search_toggle_selected_favorite() { ((SEARCH_X_CALLS+=1)); }
ui_select_emisoras() { TEST_SECTION=favorites; }
ui_select_recientes() { TEST_SECTION=recents; }
for TEST_EXIT_KEY in F R; do
    TEST_EVENT=0 TEST_SECTION=''
    input_read() {
        ((TEST_EVENT+=1))
        INPUT_EVENT=KEY
        if ((TEST_EVENT == 1)); then INPUT_KEY=X; else INPUT_KEY=$TEST_EXIT_KEY; fi
    }
    stations_select_fzf && fail 'cambio de sección solicita reproducción'
    ((SEARCH_ACTIVE == 0)) || fail 'búsqueda conserva foco'
    if [[ "$TEST_EXIT_KEY" == F ]]; then
        [[ "$TEST_SECTION" == favorites ]] || fail 'F no llega a favoritas'
    else
        [[ "$TEST_SECTION" == recents ]] || fail 'R no llega a recientes'
    fi
done
((SEARCH_X_CALLS == 2)) || fail 'X no gestiona el resultado'
input_read() { return 1; }
DRAW_CALLS=0

SEARCH_QUERY=rock
search_handle_key $'\x15' && fail 'Ctrl-U ya no debe limpiar la consulta de búsqueda'
assert_eq rock "$SEARCH_QUERY" 'Ctrl-U modificó la consulta'

# En pantallas pequeñas, dentro de la búsqueda las flechas izquierda/derecha
# alternan entre una lista limpia de nombres y la vista con detalles.
SEARCH_DETAILS_VISIBLE=0
TEST_EVENT=0
input_read() {
    ((TEST_EVENT+=1))
    case "$TEST_EVENT" in
        1) INPUT_EVENT=RIGHT ;;
        2) INPUT_EVENT=LEFT ;;
        *) return 1 ;;
    esac
    return 0
}
selector_status=0
stations_select_fzf || selector_status=$?
assert_eq 1 "$selector_status" 'EOF simulado cierra el buscador tras alternar detalles'
assert_eq 0 "$SEARCH_DETAILS_VISIBLE" 'LEFT no oculta los detalles de búsqueda'
[[ "$LAST_MESSAGE" == 'Detalles de búsqueda ocultos.' ]] || fail 'LEFT no informa de que oculta detalles'
input_read() { return 1; }
DRAW_CALLS=0

SEARCH_QUERY=rock
TEST_EVENT=0
input_read() {
    ((TEST_EVENT+=1))
    if ((TEST_EVENT == 1)); then
        INPUT_EVENT=DELETE
        return 0
    fi
    return 1
}
selector_status=0
stations_select_fzf || selector_status=$?
assert_eq 1 "$selector_status" 'EOF simulado cierra el buscador tras Supr'
assert_eq '' "$SEARCH_QUERY" 'Supr no limpia la consulta de búsqueda'
input_read() { return 1; }
DRAW_CALLS=0

selector_status=0
stations_select_fzf || selector_status=$?
assert_eq 1 "$selector_status" 'EOF simulado cierra el buscador integrado'
assert_eq 1 "$DRAW_CALLS" 'el buscador pinta una vez al entrar'
assert_eq 0 "$RESUME_CALLS" 'el selector integrado no ejecuta ui_resume'

# Si ya existe la copia JSON pero falta el índice rápido TSV, B debe reconstruir
# el índice en el momento y entrar al buscador, sin obligar al usuario a pulsar U.
eval "$INTEGRATED_SELECTOR_DEF"
KEILA_FZF_SEARCH=0
TSV_READY=0
REBUILD_CALLS=0
OPEN_CALLS=0
DRAW_CALLS=0
CATALOG_PID=''
CATALOG_STATUS=''
catalog_start() { fail 'B no debe lanzar actualización si puede reconstruir TSV desde JSON'; }
stations_tsv_valid() { if ((TSV_READY)); then return 0; fi; return 1; }
stations_json_valid() { return 0; }
stations_catalog_valid() { return 0; }
stations_rebuild_tsv() { ((REBUILD_CALLS += 1)); TSV_READY=1; return 0; }
search_open() { ((OPEN_CALLS += 1)); SEARCH_ACTIVE=1; return 0; }
search_draw_view() { ((DRAW_CALLS += 1)); return 0; }
input_read() { return 1; }
selector_status=0
stations_select_fzf || selector_status=$?
assert_eq 1 "$selector_status" 'EOF simulado cierra el buscador tras reconstruir'
assert_eq 1 "$REBUILD_CALLS" 'B no reconstruyó el TSV desde JSON'
assert_eq 1 "$OPEN_CALLS" 'B no abrió la búsqueda tras reconstruir TSV'
assert_eq 1 "$DRAW_CALLS" 'B no pintó la búsqueda tras reconstruir TSV'

# La edición solo repinta el campo. Un TICK temprano no filtra; navegar y
# reproducir sí deben actualizar resultados antes de usar la selección.
source "$ROOT_DIR/lib/search.sh"
search_load_catalog() {
    SEARCH_SOURCE_FILE=''
    SEARCH_SOURCE_ROWS=$'Rock FM\tMadrid\tEspaña\tMP3\thttps://example.invalid/rock\tES\trock fm\nJazz FM\tMadrid\tEspaña\tMP3\thttps://example.invalid/jazz\tES\tjazz fm'
}
search_open() { search_reset; search_load_catalog; search_filter; SEARCH_ACTIVE=1; }
FIELD_CALLS=0 DRAW_CALLS=0 TEST_EVENT=0
ui_draw_search_query_only() { ((FIELD_CALLS+=1)); return 0; }
catalog_poll() { return 1; }
app_poll_player() { return 1; }
ui_message_tick() { return 1; }
input_read() {
    ((TEST_EVENT+=1))
    INPUT_REPEAT_COUNT=1
    case "$TEST_EVENT" in
        1) INPUT_EVENT=KEY INPUT_KEY=j ;;
        2)
            INPUT_EVENT=TICK
            # Forzar un tick antes de vencer el plazo, sin depender del reloj.
            SEARCH_QUERY_EDIT_AT_US=$(( ${EPOCHREALTIME//[.,]/} + 1000000 )) ;;
        3)
            ((SEARCH_FILTER_DIRTY && ${#SEARCH_MATCHES[@]} == 2)) || fail 'tick temprano filtra'
            INPUT_EVENT=KEY INPUT_KEY=a ;;
        4) INPUT_EVENT=DELETE ;;
        5) INPUT_EVENT=KEY INPUT_KEY=j ;;
        6) INPUT_EVENT=KEY INPUT_KEY=a ;;
        7) INPUT_EVENT=DOWN ;;
        8)
            [[ ${#SEARCH_MATCHES[@]} == 1 && $SEARCH_FILTER_DIRTY == 0 && ${SEARCH_NAMES[0]} == 'Jazz FM' ]] || fail 'cursor usa resultados antiguos'
            INPUT_EVENT=KEY INPUT_KEY=z ;;
        9) INPUT_EVENT=ENTER ;;
        *) return 1 ;;
    esac
    return 0
}
stations_select_fzf || fail 'Enter no reproduce la consulta vigente'
[[ $SELECTED_NAME == 'Jazz FM' && $SEARCH_QUERY == jaz ]] || fail 'Enter conserva selección antigua'
((FIELD_CALLS == 6 && DRAW_CALLS == 2)) || fail 'editar redibuja toda la pantalla'

# Si no hay cursor parcial válido, se conserva el camino completo de dibujo.
FIELD_CALLS=0 DRAW_CALLS=0 TEST_EVENT=0
ui_draw_search_query_only() { ((FIELD_CALLS+=1)); return 1; }
stations_select_fzf || fail 'fallback impide reproducir'
((FIELD_CALLS == 6 && DRAW_CALLS == 8)) || fail 'fallback no repinta la pantalla'

# El filtro diferido se aplica una vez vencido el intervalo de escritura.
SEARCH_QUERY=rock SEARCH_FILTER_DIRTY=1
SEARCH_QUERY_EDIT_AT_US=$(( ${EPOCHREALTIME//[.,]/} + 1000000 ))
search_query_filter_due && fail 'sin pausa aplica filtro'
SEARCH_QUERY_EDIT_AT_US=0
search_query_filter_due || fail 'no aplica filtro vencido'
search_apply_pending_filter || fail 'no procesa consulta pendiente'
[[ ${SEARCH_NAMES[0]} == 'Rock FM' && $SEARCH_FILTER_DIRTY == 0 ]] || fail 'resultados diferidos incorrectos'

printf 'ok   búsqueda integrada: transición sin suspend/resume ni borrado completo\n'
