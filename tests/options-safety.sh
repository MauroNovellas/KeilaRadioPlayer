#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ui_draw() { :; }
ui_refresh_size() { UI_COLS=80 UI_LINES=24; }
tput() { :; }
player_is_running() { return 0; }
ui_sync_selection() {
    ui_navigation_refresh
    ((UI_SELECTED_INDEX < UI_NAV_COUNT)) || UI_SELECTED_INDEX=$((UI_NAV_COUNT > 0 ? UI_NAV_COUNT - 1 : 0))
    return 0
}
favorites_init || fail inicialización
favorites_add Seleccionada https://example.invalid/selected || fail favorita
favorites_add Sonando https://example.invalid/playing || fail favorita
favorites_load || fail cargar
PLAYER_NAME=Sonando PLAYER_URL=https://example.invalid/playing
UI_SELECTED_INDEX=0
options_toggle_selected_favorite
((${#FAVORITE_NAMES[@]} == 2)) || fail 'se elimina sin confirmar'
[[ "$FAVORITES_CONFIRM_URL" == https://example.invalid/selected ]] || fail 'se prepara la emisora que suena, no la seleccionada'
options_toggle_selected_favorite
favorites_load
[[ "${#FAVORITE_NAMES[@]}:${FAVORITE_NAMES[0]}" == 1:Sonando ]] || fail 'se elimina la emisora incorrecta'

# Añadir desde Recientes es inmediato; quitar requiere repetir la acción.
HISTORY_NAMES=(Reciente) HISTORY_URLS=(https://example.invalid/recent)
history_recent_refresh
UI_SELECTED_INDEX=${#FAVORITE_NAMES[@]}
options_toggle_selected_favorite
favorites_load
((${#FAVORITE_NAMES[@]} == 2)) || fail 'no añade inmediatamente desde Recientes'
options_toggle_selected_favorite
((${#FAVORITE_NAMES[@]} == 2)) || fail 'quita desde Recientes sin confirmar'
options_toggle_selected_favorite
favorites_load
((${#FAVORITE_NAMES[@]} == 1)) || fail 'no confirma la baja desde Recientes'

# Una navegación entre confirmaciones obliga a confirmar de nuevo.
events=0 OPTIONS_SELECTIONS=() OPTIONS_OFFSETS=() UI_SELECTED_INDEX=0
input_read() {
    ((events += 1)); INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=KEY INPUT_KEY=E ;;
        2|5) INPUT_EVENT=KEY INPUT_KEY=X ;;
        3) INPUT_EVENT=UP ;;
        4) INPUT_EVENT=DOWN ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null
favorites_load
((${#FAVORITE_NAMES[@]} == 1)) || fail 'moverse no cancela la confirmación'
[[ -z "$FAVORITES_CONFIRM_URL" ]] || fail 'la confirmación sobrevive al menú'

# Guardado fallido: ni estado engañoso en memoria ni aplicación del cambio.
PREF_AUTOPLAY=1
preferences_save || fail 'no prepara preferencias'
apply_calls=0
preferences_apply() { ((apply_calls += 1)); }
preferences_save() { return 1; }
options_toggle_preference PREF_AUTOPLAY 'Inicio automático'
[[ "$PREF_AUTOPLAY" == 1 && "$apply_calls" == 0 ]] || fail 'aplica un cambio que no se guardó'
[[ "$UI_MESSAGE" == *'valor anterior'* ]] || fail 'no avisa del guardado fallido'
preferences_load
[[ "$PREF_AUTOPLAY" == 1 ]] || fail 'se modificaron las preferencias guardadas'

# Estado de catálogo ligero: verificar una vez y reutilizar al navegar.
printf 'Radio\tÁmbito\tPaís\tmp3\thttps://example.invalid/radio\n' > "$KEILA_STATIONS_TSV"
OPTIONS_CATALOG_CHECK_AT=0 CATALOG_PID='' CATALOG_LAST_ERROR=''
options_catalog_refresh
[[ "$OPTIONS_CATALOG_STATE" == 'Al día' ]] || fail 'no reconoce el índice fresco'
touch -d '3 days ago' "$KEILA_STATIONS_TSV"
OPTIONS_CATALOG_CHECK_AT=0
options_catalog_refresh
[[ "$OPTIONS_CATALOG_STATE" == 'Copia anterior' ]] || fail 'no reconoce índice caducado'
catalog_checks=0
stations_tsv_valid() { ((catalog_checks += 1)); return 1; }
for ((i=0; i<20; i++)); do options_catalog_refresh; done
((catalog_checks == 0)) || fail 'relee el catálogo en cada navegación'
CATALOG_PID=123
options_catalog_refresh
[[ "$OPTIONS_CATALOG_STATE" == Actualizando ]] || fail 'no detecta descarga en curso'
((catalog_checks == 0)) || fail 'analiza el catálogo mientras descarga'

printf 'ok   opciones: confirmaciones, Recientes, fallos de guardado y caché de estados\n'
