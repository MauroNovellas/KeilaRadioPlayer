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
keila_init_paths; favorites_init; favorites_load; history_load

# Mapas anteriores: conservar T para Buscar y todas las demás personalizaciones,
# sin reescribir el archivo al cargar. Calidad escoge la primera letra libre.
printf 'autoplay=0\nkey_b=t\nkey_q=n\n' > "$KEILA_CONFIG_DIR/preferences"
before=$(cksum "$KEILA_CONFIG_DIR/preferences")
data_validate "$KEILA_CONFIG_DIR/preferences" preferences || fail 'mapa antiguo no válido'
preferences_load
[[ ${PREF_KEYS[b]} == t && ${PREF_KEYS[q]} == n && ${PREF_KEYS[t]} == e && $PREF_AUTOPLAY == 0 ]] || fail 'migración pierde atajos'
[[ $(cksum "$KEILA_CONFIG_DIR/preferences") == "$before" ]] || fail 'cargar reescribe preferencias'
preferences_save || fail 'persistir migración'
preferences_load
[[ ${PREF_KEYS[t]} == e && ${PREF_KEYS[b]} == t ]] || fail 'migración no persiste'
preferences_defaults
PREF_KEYS[t]=y
preferences_save || fail 'guardar tecla nueva'
preferences_load
[[ ${PREF_KEYS[t]} == y && ${PREF_KEYS[b]} == b ]] || fail 'mapa nuevo se pierde'
(
    calls=0
    app_quality_menu() { calls=$((calls+1)); }
    app_handle_key T || true
    [[ $calls == 0 ]] || fail 'T antigua sigue activa'
    app_handle_key y; app_handle_key Y
    [[ $calls == 2 ]] || fail 'tecla personalizada no abre selector'
    preferences_defaults
    app_handle_key t; app_handle_key T
    [[ $calls == 4 ]] || fail 'T predeterminada no abre selector'
) || fail 'acción directa'

PLAYER_CODEC=aac PLAYER_BITRATE_KBPS=64 PLAYER_SAMPLE_RATE=48000 PLAYER_CHANNELS=stereo
ui_quality_info state
[[ $UI_QUALITY_INFO == '[Y] Calidad: AAC · 64 kbps · 48 kHz · stereo' ]] || fail 'metadatos o tecla incorrectos'
SEARCH_ACTIVE=1
ui_quality_info state
[[ $UI_QUALITY_INFO == '[T] Calidad:'* ]] || fail 'acceso local de búsqueda incorrecto'
SEARCH_ACTIVE=0
PLAYER_CODEC='' PLAYER_BITRATE_KBPS=0 PLAYER_SAMPLE_RATE=0 PLAYER_CHANNELS=''
ui_quality_info state
[[ $UI_QUALITY_INFO == '[Y] Calidad: Conectando…' ]] || fail 'metadatos ausentes inventados'
UI_UNICODE=1 UI_COLOR=1
UI_YELLOW=$'\033[33m' UI_DIM=$'\033[2m' UI_RESET=$'\033[0m'
ui_configure_glyphs
frame=$(ui_print_styled_padded 30 '[T] Calidad: AAC · 64 kb/s' quality)
[[ $frame == "${UI_YELLOW}[T]"* && $frame == *"${UI_DIM} Calidad:"* ]] || fail 'atajo no resaltado'
player_is_running() { return 0; }
UI_LAYOUT_MODE=compact
[[ $(ui_responsive_section_title now) == '[Y] Calidad' ]] || fail 'cabecera compacta sin acceso'

# T es local a la búsqueda; t se escribe. Volver de la ventana no cambia consulta,
# emisora seleccionada ni resultados, incluso con otro atajo en el mapa principal.
(
    stations_tsv_valid() { return 0; }
    stations_catalog_valid() { return 0; }
    printf 'Radio test\tMadrid\tEspaña\tAAC\thttps://radio.invalid/test\tES\tradio test madrid españa aac es\tMadrid\trock\nRadio test dos\tMadrid\tEspaña\tMP3\thttps://radio.invalid/test2\tES\tradio test dos madrid españa mp3 es\tMadrid\trock\n' > "$KEILA_STATIONS_TSV"
    search_draw_view() { :; }
    ui_draw_search_query_only() { :; }
    search_open || fail 'abrir búsqueda'
    SEARCH_QUERY=tes
    search_query_changed
    search_apply_pending_filter || fail 'filtrar datos de prueba'
    [[ ${#SEARCH_MATCHES[@]} == 2 && ${SEARCH_URLS[1]} == https://radio.invalid/test2 ]] || fail 'catálogo de prueba vacío'
    snapshot="${SEARCH_MATCHES[*]}/$SEARCH_SELECTED_INDEX/$SEARCH_SCROLL_OFFSET"
    calls=0 event_i=0
    app_quality_menu() {
        [[ $SEARCH_QUERY == tes && "$snapshot" == "${SEARCH_MATCHES[*]}/$SEARCH_SELECTED_INDEX/$SEARCH_SCROLL_OFFSET" && $SEARCH_ACTIVE == 1 ]] || fail 'T pierde búsqueda'
        calls=$((calls+1)); return 1
    }
    input_read() {
        event_i=$((event_i+1)); INPUT_EVENT=KEY
        case $event_i in
            1) INPUT_KEY=T; SEARCH_SELECTED_INDEX=1 SEARCH_SCROLL_OFFSET=1; snapshot="${SEARCH_MATCHES[*]}/$SEARCH_SELECTED_INDEX/$SEARCH_SCROLL_OFFSET" ;;
            2) INPUT_KEY=t ;;
            *) INPUT_EVENT=ESC ;;
        esac
    }
    stations_select_fzf >/dev/null || true
    [[ $calls == 1 && $SEARCH_QUERY == test ]] || fail 'T/t se confunden'
) || fail 'selector desde búsqueda'

# Actual al abrir y misma elección por identidad tras la publicación asíncrona.
(
    origin=https://radio.invalid/original
    PLAYER_URL=$origin PLAYER_INPUT_URL=https://radio.invalid/low PLAYER_HLS_RATE=0 PLAYER_PID=123 PLAYER_NAME=Radio
    record_plan_busy() { return 1; }
    # shellcheck disable=SC2004
    quality_load() { QUALITY_TARGETS[$origin]=$PLAYER_INPUT_URL; QUALITY_RATES[$origin]=0; }
    quality_start_job() { QUALITY_JOB_PID=987; }
    quality_cleanup() { QUALITY_JOB_PID=''; }
    quality_poll_job() {
        QUALITY_ROWS=("$origin|0|MP3|128000|original" 'https://radio.invalid/high|0|AAC|192000|catalog' 'https://radio.invalid/low|0|AAC|64000|catalog')
        QUALITY_JOB_PID=''; return 0
    }
    quality_apply_choice() { fail 'navegar o resize aplica audio'; }
    panel_poll() { return 1; }
    ui_refresh_size() { :; }
    quality_draw() { seen+=("$1"); PANEL_SELECTED=$1 PANEL_SCROLL=$2 PANEL_VISIBLE=5; }
    UI_COLS=80 UI_LINES=24
    seen=() event_i=0
    input_read() { event_i=$((event_i+1)); case $event_i in 1) INPUT_EVENT=TICK ;; 2) INPUT_EVENT=RESIZE ;; *) INPUT_EVENT=ESC ;; esac; }
    app_quality_menu >/dev/null || true
    [[ ${seen[*]} == '1 2 2' && $PREFERENCES_ACTIVE == 0 && -z $QUALITY_JOB_PID ]] || fail 'elección actual cambia al publicar/resize'
    UI_COLS=30
    quality_menu_rows "$origin" "$PLAYER_INPUT_URL" 0
    [[ ${PANEL_ROWS[2]} == '|Actual · AAC'* && ${PANEL_ROWS[2]} == *'Consumo aproximado: 28.8 MB/h.'* ]] || fail 'Actual/consumo oculto en móvil'
    QUALITY_ROWS=("$origin|0||0|original")
    quality_menu_rows "$origin" "$PLAYER_INPUT_URL" 0
    quality_menu_notice
    [[ $QUALITY_MENU_NOTICE == 'Sin alternativas detectadas'* ]] || fail 'elección guardada inventa alternativas'
) || fail 'selección actual/publicación'

# Ventana centrada: Unicode/ASCII y color, borde/posición y escrituras de tamaño
# fijo. Ningún borrado global ni subprocess tput durante cada pulsación.
UI_COLOR=0 UI_ACTIVE=0 previous_preferences=0 QUALITY_OVERLAY_GEOMETRY=''
QUALITY_ROWS=('https://radio.invalid/test|0|AAC|64000|original') QUALITY_RESULT_NOTICE=''
QUALITY_TARGETS=() QUALITY_RATES=()
quality_menu_rows https://radio.invalid/test https://radio.invalid/test 0
deps_is_termux() { return 1; }
ui_refresh_size() { :; }
logo_hide() { hides=$((hides+1)); }
hides=0
for geometry in '160 45' '120 24' '100 24' '97 16' '96 16'; do
    read -r UI_COLS UI_LINES <<< "$geometry"
    for UI_UNICODE in 0 1; do
        ui_configure_glyphs
        for UI_COLOR in 0 1; do
            quality_draw 0 0 'Sin alternativas detectadas' $'Radio 日本 Cafe\u0301 larga' | python3 "$ROOT_DIR/tests/fixtures/check-quality-popup.py" "$UI_COLS" "$UI_LINES" || fail "ventana $geometry/$UI_UNICODE/$UI_COLOR"
        done
    done
done
UI_ACTIVE=1 UI_COLS=120 UI_LINES=24 backgrounds=0 hides=0 QUALITY_OVERLAY_GEOMETRY=''
ui_draw() { backgrounds=$((backgrounds+1)); }
options_draw() { backgrounds=$((backgrounds+1)); }
quality_draw 0 0 'Información' Radio >/dev/null
quality_draw 0 0 'Información actualizada' Radio >/dev/null
[[ $backgrounds == 1 && $hides == 1 ]] || fail 'navegar repinta fondo/logo'
UI_COLS=132
quality_draw 0 0 'Resize' Radio >/dev/null
[[ $backgrounds == 2 && $hides == 2 ]] || fail 'resize no restaura fondo'
previous_preferences=1 QUALITY_OVERLAY_GEOMETRY=''
quality_draw 0 0 'Opciones' Radio >/dev/null
[[ $backgrounds == 3 ]] || fail 'ruta secundaria pierde fondo'
previous_preferences=0 SEARCH_ACTIVE=1 QUALITY_OVERLAY_GEOMETRY='' search_backgrounds=0
search_draw_view() { search_backgrounds=$((search_backgrounds+1)); }
quality_draw 0 0 'Búsqueda' Radio >/dev/null
[[ $search_backgrounds == 1 && $backgrounds == 3 ]] || fail 'fondo de búsqueda sustituido por principal'
SEARCH_ACTIVE=0
for ((i=1; i<=10; i++)); do QUALITY_ROWS+=("https://radio.invalid/version$i|0|AAC|64000|catalog"); done
quality_menu_rows https://radio.invalid/test https://radio.invalid/test 0
quality_draw 10 0 'Lista larga' Radio >/dev/null
[[ $PANEL_SELECTED == 10 && $PANEL_SCROLL == 6 && $PANEL_VISIBLE == 5 ]] || fail 'ventana no desplaza listas largas'
deps_is_termux() { return 0; }
panels=0
panel_draw() { panels=$((panels+1)); }
quality_draw 0 0 'Termux' Radio >/dev/null
[[ $panels == 1 && -z $QUALITY_OVERLAY_GEOMETRY ]] || fail 'Termux usa ventana de escritorio'
printf 'ok   calidad directa: atajos, migración, búsqueda, selección estable y ventana adaptativa\n'
