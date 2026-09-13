#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
keila_init_paths; favorites_init
ui_navigation_refresh() { :; }
ui_refresh_size() { UI_COLS=80 UI_LINES=24; }
tput() { :; }
ticks=0 plays=0
panel_poll() { ticks=$((ticks+1)); return 1; }
app_play() { plays=$((plays+1)); }
for url in 'file:///tmp/song' 'https://' 'https://user:pass@radio.invalid/a' 'https://radio.invalid/a b' 'https://radio.invalid/a|b' $'https://radio.invalid/\n' 'https://radio.invalid/a\b'; do
    station_manual_valid Radio "$url" && fail "acepta $url"
done
station_manual_valid $'Radio\nOtra' https://test.invalid && fail 'acepta control en nombre'
station_manual_valid 'Radio | Otra' https://test.invalid && fail 'acepta delimitador'
station_manual_valid '' https://test.invalid && fail 'acepta nombre vacío'
station_manual_valid Radio 'https://[::1]:8000/live?a=1&b=2' || fail IPv6
station_manual_save 'Radio personal' 'https://radio.invalid/live?a=1&b=2' || fail guardar
[[ ${#FAVORITE_URLS[@]} == 1 && $plays == 0 ]] || fail 'guardar reproduce o duplica'
status=0; station_manual_save 'Otro nombre' 'https://radio.invalid/live?a=1&b=2' || status=$?
[[ $status == 2 && ${FAVORITE_NAMES[0]} == 'Radio personal' ]] || fail duplicado
favorites_load
[[ ${FAVORITE_NAMES[0]} == 'Radio personal' ]] || fail persistencia
data_publish() { return 1; }
station_manual_save 'Fallida' 'https://fail.invalid/live' && fail 'acepta fallo de escritura'
[[ ${#FAVORITE_URLS[@]} == 1 ]] || fail 'fallo altera memoria'
unset -f data_publish
source "$ROOT_DIR/lib/data-safety.sh"
# El diálogo no guarda al editar, volver, redimensionar ni consultar detalles.
event_i=0
input_read() {
    event_i=$((event_i+1)); INPUT_KEY=''
    case $event_i in
        1) INPUT_EVENT=KEY; INPUT_KEY=n ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=A ;;
        3) INPUT_EVENT=TICK ;;
        4) INPUT_EVENT=RESIZE ;;
        5) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_station_manual >/dev/null
[[ ${#FAVORITE_URLS[@]} == 1 && $ticks == 1 && $plays == 0 ]] || fail cancelación
# Editor: Supr limpia, Escape no publica lo escrito.
event_i=0
input_read() {
    event_i=$((event_i+1)); INPUT_KEY=''
    case $event_i in 1) INPUT_EVENT=DELETE ;; 2) INPUT_EVENT=KEY; INPUT_KEY=Z ;; *) INPUT_EVENT=ENTER ;; esac
}
station_field_edit Nombre Anterior 'Ayuda' 160 >/dev/null
[[ $STATION_FIELD_RESULT == Z ]] || fail editor
# Selector conserva consulta libre; Enter elige, Escape no cambia el filtro.
printf 'Uno\tMadrid\tSpain\tMP3\thttps://test.invalid/1\tES\tuno madrid rock es\tMadrid\trock\nDos\tParis\tFrance\tMP3\thttps://test.invalid/2\tFR\tdos paris jazz fr\tParis\tjazz\n' > "$KEILA_STATIONS_TSV"
SEARCH_QUERY=rock
SEARCH_SOURCE_FILE=$KEILA_STATIONS_TSV
event_i=0
input_read() {
    event_i=$((event_i+1)); INPUT_KEY=''
    case $event_i in 1) INPUT_EVENT=KEY; INPUT_KEY=E ;; 2) INPUT_EVENT=KEY; INPUT_KEY=S ;; 3) INPUT_EVENT=DOWN ;; *) INPUT_EVENT=ENTER ;; esac
}
app_station_filter_picker country >/dev/null || fail elegir
[[ $SEARCH_COUNTRY_FILTER_ENABLED == 1 && $KEILA_CATALOG_COUNTRY_FILTER == ES && $SEARCH_QUERY == rock ]] || fail 'selector pierde estado'
input_read() { INPUT_EVENT=ESC; INPUT_KEY=''; }
app_station_filter_picker country >/dev/null && fail 'Esc aplica'
[[ $SEARCH_COUNTRY_FILTER_ENABLED == 1 && $SEARCH_QUERY == rock ]] || fail 'Esc modifica'
event_i=0
input_read() {
    event_i=$((event_i+1)); INPUT_KEY=''
    case $event_i in 1) INPUT_EVENT=KEY; INPUT_KEY=Z ;; 2) INPUT_EVENT=KEY; INPUT_KEY=Z ;; 3) INPUT_EVENT=ENTER ;; *) INPUT_EVENT=ESC ;; esac
}
app_station_filter_picker country >/dev/null && fail 'sin resultados aplica'
[[ $SEARCH_COUNTRY_FILTER_ENABLED == 1 && $KEILA_CATALOG_COUNTRY_FILTER == ES ]] || fail 'consulta sin resultados borra filtro'
# Una actualización que termina en el selector refresca sus valores sin hacer
# que Enter elija otra fila. El catálogo simulado añade un país por delante.
(
    event_i=0 CATALOG_PID=simulado
    panel_poll() {
        CATALOG_PID=''
        printf 'Drei\tBerlin\tDeutschland\tMP3\thttps://test.invalid/3\tDE\tdrei\tBerlin\trock\n' >> "$KEILA_STATIONS_TSV"
        return 0
    }
    input_read() {
        event_i=$((event_i+1)); INPUT_KEY=''
        case $event_i in 1|2) INPUT_EVENT=DOWN ;; 3) INPUT_EVENT=TICK ;; *) INPUT_EVENT=ENTER ;; esac
    }
    app_station_filter_picker country >/dev/null || fail 'refresco selector'
    [[ $KEILA_CATALOG_COUNTRY_FILTER == FR ]] || fail 'actualización cambia selección'
) || fail 'refresco selector'
# Flujo completo del formulario: probar explícitamente y guardar son acciones
# independientes; durante grabación y con terminal ilegible no se prueba audio.
(
    event_i=0 plays=0 RECORDING_ACTIVE=0
    station_field_edit() {
        if [[ $1 == 'NOMBRE DE LA EMISORA' ]]; then STATION_FIELD_RESULT='Nueva manual'
        else STATION_FIELD_RESULT='https://nueva.invalid/live'; fi
    }
    input_read() {
        event_i=$((event_i+1)); INPUT_EVENT=KEY
        case $event_i in 1) INPUT_KEY=n ;; 2) INPUT_KEY=d ;; 3) INPUT_KEY=p ;; 4) INPUT_KEY=g ;; *) INPUT_EVENT=ESC ;; esac
    }
    app_station_manual >/dev/null
    [[ $plays == 1 && ${#FAVORITE_URLS[@]} == 2 ]] || fail 'probar y guardar'
    RECORDING_ACTIVE=1 plays=0 event_i=0
    input_read() {
        event_i=$((event_i+1)); INPUT_EVENT=KEY
        case $event_i in 1) INPUT_KEY=n ;; 2) INPUT_KEY=d ;; 3) INPUT_KEY=p ;; *) INPUT_EVENT=ESC ;; esac
    }
    app_station_manual >/dev/null
    [[ $plays == 0 && $RECORDING_ACTIVE == 1 ]] || fail 'prueba interrumpe grabación'
    RECORDING_ACTIVE=0 event_i=0
    ui_refresh_size() { UI_COLS=8 UI_LINES=5; }
    app_station_manual >/dev/null
    [[ $plays == 0 ]] || fail 'prueba desde terminal ilegible'
) || fail 'flujo manual'
options_build_rows stations; options_key_select L || fail 'sin acceso desde Emisoras'
[[ $OPTIONS_ROW_ACTION == menu:filters ]] || fail 'ruta de filtros'
options_key_select N || fail 'sin alta manual desde Emisoras'
[[ $OPTIONS_ROW_ACTION == station_manual ]] || fail 'ruta de alta manual'
options_build_rows filters; options_key_select P || fail 'sin selector país'
[[ $OPTIONS_ROW_ACTION == filter_country ]] || fail 'ruta de país'
# Pantallas nuevas usan el mismo marco en 13 geometrías y ambos símbolos.
ui_refresh_size() { :; }
UI_COLOR=0
for geometry in '160 45' '100 24' '97 16' '96 16' '80 24' '62 16' '50 13' '42 11' '40 10' '30 8' '20 6' '8 5' '2 1'; do
    read -r UI_COLS UI_LINES <<< "$geometry"
    for UI_UNICODE in 0 1; do
        ui_configure_glyphs
        for screen in manual field picker; do
            case $screen in
                manual) station_manual_rows 'Radio personal de nombre muy largo' 'https://radio.invalid/una/ruta/muy/larga'; frame=$(panel_draw 'AÑADIR EMISORA MANUAL' 3 0 'Esc volver') ;;
                field) frame=$(station_field_draw DIRECCIÓN 'https://radio.invalid/una/dirección/extraordinariamente/larga/para/ver/el/cursor' Ayuda) ;;
                picker) station_picker_rows "$KEILA_STATIONS_TSV" ''; frame=$(panel_draw 'ELEGIR PAÍS' 1 0 'Esc volver') ;;
            esac
            rows=0
            while IFS= read -r line; do
                rows=$((rows+1))
                ((${#line} < UI_COLS)) || fail "$screen ancho $geometry"
            done <<< "$frame"
            [[ $rows == "$UI_LINES" ]] || fail "$screen alto $geometry"
        done
    done
done
printf 'ok   emisoras en Opciones: validación, duplicados, persistencia, cancelación, selector y 13 geometrías\n'
