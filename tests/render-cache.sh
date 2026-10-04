#!/usr/bin/env bash
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
UI_COLOR=0 UI_UNICODE=1
ui_configure_glyphs
# Comparar un cache hit con un render sin caché, también tras cambiar los
# parámetros que pueden invalidar el resultado (no solo cuadros idénticos).
for width in 42 52; do
    for UI_UNICODE in 0 1; do
        ui_configure_glyphs
        for gain in 0 12 -12; do
            EQUALIZER_GAINS=("$gain" 6 0 -6 12)
            EQUALIZER_EDITOR_ACTIVE=1 EQUALIZER_SELECTED=2
            for ((row=0; row<8; row++)); do
                ui_equalizer_wide_row "$row" "$width" >/dev/null
                ui_equalizer_wide_row "$row" "$width" >/dev/null
                cached=$UI_EQ_TEXT
                UI_EQ_CACHE_KEY=''
                ui_equalizer_wide_row "$row" "$width" >/dev/null
                [[ "$cached" == "$UI_EQ_TEXT" ]] || fail 'caché EQ obsoleta'
                SPECTRUM_LEVELS=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 16)
                SPECTRUM_LEVELS[0]=$((gain + 12))
                ui_spectrum_editor_row_wide "$row" "$width" state
                ui_spectrum_editor_row_wide "$row" "$width" state
                cached=$UI_SPECTRUM_ROW_TEXT
                UI_SPECTRUM_WIDE_CACHE_KEY=''
                ui_spectrum_editor_row_wide "$row" "$width" state
                [[ "$cached" == "$UI_SPECTRUM_ROW_TEXT" ]] || fail 'caché espectro obsoleta'
            done
        done
    done
done
PLAYER_CODEC=mp3 PLAYER_BITRATE_KBPS=192 PLAYER_SAMPLE_RATE=44100 PLAYER_CHANNELS=stereo
expected=$(ui_audio_info)
ui_audio_info state
[[ "$expected" == "$UI_AUDIO_INFO" ]] || fail 'metadatos distintos en modo state'
# Un hit debe conservar tanto las celdas como la limpieza y el recorte Unicode.
for text in 'Comentarios' '東京 FM 🎵' $'Radio\tFM\nespañola' $'Cafe\u0301'; do
    for width in 1 4 12 40; do
        for ellipsis in 0 1; do
            options_fit_text_uncached "$text" "$width" "$ellipsis"
            expected=$OPTIONS_FITTED expected_width=$OPTIONS_FITTED_WIDTH
            options_fit_text "$text" "$width" "$ellipsis"
            options_fit_text "$text" "$width" "$ellipsis"
            [[ $OPTIONS_FITTED == "$expected" && $OPTIONS_FITTED_WIDTH == "$expected_width" ]] || fail 'caché texto cambia celdas'
        done
    done
done
for ((i=0; i<600; i++)); do options_fit_text "Título $i" 20; done
((${#OPTIONS_FIT_WIDTH_CACHE[@]} <= 256)) || fail 'caché de textos sin límite'
TRACK_HISTORY_TITLES=('Actual' 'Anterior con nombre largo') TRACK_HISTORY_TIMES=('12:00' '11:59')
for width in 12 40 120; do
    expected=$(track_history_line 0 "$width")
    track_history_line 0 "$width" state
    [[ $TRACK_HISTORY_LINE == "$expected" ]] || fail 'historial state distinto'
    expected=$(track_history_session_line "$width")
    track_history_session_line "$width" state
    [[ $TRACK_HISTORY_LINE == "$expected" ]] || fail 'ruta sesión state distinta'
done
# Geometría y barras sin subshells: misma salida que la API de texto, con
# reproducción detenida/activa, ayuda, móvil y escritorio. No fijar tamaños
# constantes que oculten una invalidación incorrecta al redimensionar.
player_is_running() { ((test_playing)); }
for test_playing in 0 1; do
    for dimensions in '132 40' '112 20' '80 24' '62 16' '50 13' '42 11' '40 10'; do
        read -r UI_COLS UI_LINES <<< "$dimensions"
        expected=$(ui_layout_mode "$UI_COLS" "$UI_LINES")
        ui_layout_mode "$UI_COLS" "$UI_LINES" state
        [[ $UI_LAYOUT_MODE_VALUE == "$expected" ]] || fail 'modo state distinto'
        UI_LAYOUT_MODE=$UI_LAYOUT_MODE_VALUE
        expected=$(ui_layout_width "$UI_COLS")
        ui_layout_width "$UI_COLS" state
        [[ $UI_LAYOUT_WIDTH == "$expected" ]] || fail 'ancho state distinto'
        for UI_HELP_VISIBLE in 0 1; do
            expected=$(ui_control_line_count)
            ui_control_line_count state
            [[ $UI_CONTROL_LINE_COUNT == "$expected" ]] || fail 'controles state distintos'
            expected=$(ui_stream_info_line_count)
            ui_stream_info_line_count state
            [[ $UI_STREAM_INFO_LINE_COUNT == "$expected" ]] || fail 'metadatos state distintos'
            expected=$(ui_list_height)
            ui_list_height state
            [[ $UI_LIST_HEIGHT == "$expected" ]] || fail 'altura state distinta'
            expected=$(ui_desktop_body_height)
            ui_desktop_body_height state
            [[ $UI_DESKTOP_BODY_HEIGHT == "$expected" ]] || fail 'cuerpo state distinto'
            expected=$(ui_desktop_track_history_slots "$UI_DESKTOP_BODY_HEIGHT")
            ui_desktop_track_history_slots "$UI_DESKTOP_BODY_HEIGHT" state
            [[ $UI_DESKTOP_TRACK_HISTORY_SLOTS == "$expected" ]] || fail 'huecos historial state distintos'
        done
    done
done
for UI_UNICODE in 0 1; do
    ui_configure_glyphs
    for PLAYER_VOLUME in 0 5 50 100; do
        for width in 0 4 48; do
            filled=$((PLAYER_VOLUME*width/100))
            expected=$(ui_repeat_char "$UI_BAR_FULL" "$filled"; ui_repeat_char "$UI_BAR_EMPTY" "$((width-filled))")
            ui_volume_bar "$width" state
            [[ $UI_VOLUME_BAR == "$expected" ]] || fail 'barra state distinta'
        done
    done
done
for INPUT_REPEAT_COUNT in 0 1 3 8 99 invalid; do
    expected=$(ui_input_repeat_count)
    ui_input_repeat_count state
    [[ $UI_INPUT_REPEAT_COUNT == "$expected" ]] || fail 'repetición state distinta'
done
printf 'ok   cachés de render y metadatos equivalentes\n'
