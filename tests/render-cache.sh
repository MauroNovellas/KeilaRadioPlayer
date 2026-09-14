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
printf 'ok   cachés de render y metadatos equivalentes\n'
