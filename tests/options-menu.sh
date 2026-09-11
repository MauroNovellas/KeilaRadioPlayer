#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
declare -A OPTIONS_SELECTIONS OPTIONS_OFFSETS
trap - EXIT
FAVORITE_NAMES=() FAVORITE_URLS=()
HISTORY_NAMES=() HISTORY_URLS=()

DRAW_CALLS=0
VISUAL_CALLS=0
ALARM_CALLS=0
PENDING_CALLS=0
SESSION_CALLS=0
SEARCH_CALLS=0
PAUSE_CALLS=0

ui_draw() { ((DRAW_CALLS += 1)); }
ui_refresh_size() { UI_COLS=80 UI_LINES=24; }
tput() { :; }
app_poll_player() { return 1; }
catalog_poll() { return 1; }
ui_message_tick() { return 1; }
pending_scan_poll() { return 1; }
app_preferences_menu() {
    [[ "${1:-}" == settings ]] && ((VISUAL_CALLS += 1))
}
app_edit_alarm() { ((ALARM_CALLS += 1)); }
app_pending_menu() { ((PENDING_CALLS += 1)); }
app_session_history_screen() { ((SESSION_CALLS += 1)); }
app_status_screen() { :; }
app_search_catalog() { ((SEARCH_CALLS += 1)); }
app_toggle_pause() { ((PAUSE_CALLS += 1)); }
player_is_running() { return 0; }
stations_tsv_valid() { return 1; }

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=G ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=R ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$PENDING_CALLS" 'G > R no abre el gestor de grabaciones desde opciones'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=S ;;
        2) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$SESSION_CALLS" 'S > Enter no abre historial de sesión desde opciones'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=T ;;
        2) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$ALARM_CALLS" 'T > Enter no abre temporizador/alarma desde opciones'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=V ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=A ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
OPTIONS_SELECTED=0
OPTIONS_SELECTIONS[main]=0
app_options_menu >/dev/null
assert_eq 1 "$VISUAL_CALLS" 'V > A no abre preferencias visuales'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=E ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=B ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$SEARCH_CALLS" 'E > B no abre búsqueda de emisoras'

events=0
input_read() {
    ((events += 1))
    INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=ENTER ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=P ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
OPTIONS_SELECTED=0
OPTIONS_SELECTIONS[main]=0
app_options_menu >/dev/null
assert_eq 1 "$PAUSE_CALLS" 'Enter > P no ejecuta pausa desde reproducción'

assert_eq 0 "$OPTIONS_ACTIVE" 'opciones no libera foco al salir'
((DRAW_CALLS >= 3)) || fail 'opciones no repinta al volver'

# Las flechas expanden el árbol, recuerdan cada nivel y no ejecutan acciones.
events=0 OPTIONS_SELECTIONS=() OPTIONS_OFFSETS=()
input_read() {
    ((events += 1)); INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=RIGHT ;;
        2) INPUT_EVENT=DOWN ;;
        3) INPUT_EVENT=RIGHT ;;
        4) INPUT_EVENT=LEFT ;;
        5) INPUT_EVENT=RIGHT ;;
        6) assert_eq 1 "$OPTIONS_SELECTED" 'el submenú pierde su selección'; INPUT_EVENT=LEFT ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$PAUSE_CALLS" 'derecha ejecuta una acción en lugar de explorar'
assert_eq 0 "${OPTIONS_SELECTIONS[main]}" 'volver pierde la categoría del padre'

# No ejecutar acciones deshabilitadas aunque se pulse su letra directamente.
player_is_running() { return 1; }
events=0
input_read() {
    ((events += 1)); INPUT_KEY=''
    case "$events" in
        1|2) INPUT_EVENT=KEY; INPUT_KEY=P ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$PAUSE_CALLS" 'se ejecutó pausa sin reproducción'
[[ "$UI_MESSAGE" == *'Primero reproduce'* ]] || fail 'falta explicación de acción no disponible'

# Detalle completo: navegar y pulsar Enter no cambia el ajuste explicado.
events=0 OPTIONS_SELECTIONS=() OPTIONS_OFFSETS=()
input_read() {
    ((events += 1)); INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY; INPUT_KEY=T ;;
        2) INPUT_EVENT=KEY; INPUT_KEY='?' ;;
        3) INPUT_EVENT=END ;;
        4) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
assert_eq 1 "$ALARM_CALLS" 'el detalle ejecuta la acción que está explicando'

# Un tick sigue atendiendo audio, alarma (dentro de app_poll_player), catálogo
# y grabaciones; no reconstruye la pantalla por cada frame del espectro.
polls=0 catalog_polls=0 scan_polls=0 frames=0
app_poll_player() { ((polls += 1)); ((polls == 3)) && PLAYER_MUTED=1; return 0; }
catalog_poll() { ((catalog_polls += 1)); return 1; }
pending_scan_poll() { ((scan_polls += 1)); return 1; }
eval "$(declare -f options_draw | sed '1s/options_draw/options_draw_original/')"
options_draw() { ((frames += 1)); options_draw_original; }
events=0 OPTIONS_SELECTIONS=() OPTIONS_OFFSETS=() PLAYER_MUTED=0
input_read() {
    ((events += 1)); INPUT_KEY=''
    if ((events <= 5)); then INPUT_EVENT=TICK; else INPUT_EVENT=ESC; fi
}
app_options_menu >/dev/null
assert_eq 5 "$polls" 'no se atiende el reproductor en cada tick'
assert_eq 5 "$catalog_polls" 'no se atiende el catálogo'
assert_eq 5 "$scan_polls" 'no se atienden las grabaciones'
assert_eq 2 "$frames" 'redibuja sin cambios o no actualiza el silencio'

# Ir a una lista devuelve el control al reproductor sin exigir dos Esc.
FAVORITE_NAMES=('Radio A') FAVORITE_URLS=('https://example.invalid/a')
ui_select_emisoras() { UI_SELECTED_INDEX=0; return 0; }
events=0 OPTIONS_SELECTIONS=() OPTIONS_OFFSETS=()
input_read() {
    ((events += 1)); INPUT_EVENT=KEY
    case "$events" in
        1) INPUT_KEY=E ;;
        2) INPUT_KEY=F ;;
        *) fail 'Ir a Favoritas no cerró Opciones' ;;
    esac
}
app_options_menu >/dev/null
assert_eq 0 "$OPTIONS_ACTIVE" 'no libera el menú al ir a Favoritas'

# La salida solicitada en una pantalla hija llega al bucle de la aplicación.
app_status_screen() { return 2; }
events=0 OPTIONS_SELECTIONS=() OPTIONS_OFFSETS=()
input_read() { ((events += 1)); INPUT_EVENT=KEY INPUT_KEY=D; ((events < 2)) || fail 'se perdió la salida del diagnóstico'; }
result=0
app_handle_key O >/dev/null || result=$?
assert_eq 2 "$result" 'la petición de salida queda atrapada en Opciones'
assert_eq 0 "$PREFERENCES_ACTIVE" 'no restaura el foco tras salir desde diagnóstico'

printf 'ok   opciones: navegación, memoria, detalle, estados, ticks y salida de pantallas hijas\n'
