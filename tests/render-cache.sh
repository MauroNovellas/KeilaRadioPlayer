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
printf 'ok   cachés de render y metadatos equivalentes\n'
