#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
export KEILA_NOW_PLAYING=0
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ui_refresh_size() { :; }
tput() {
    case $1 in
        cup) printf '\033[%d;%dH' "$(($2+1))" "$(($3+1))" ;;
        ed) printf '\033[0J' ;;
    esac
}
player_is_running() { return 0; }
UI_ACTIVE=1 UI_SUSPENDED=0 UI_COLOR=0 PREFERENCES_ACTIVE=0 SPECTRUM_ENABLED=0
FAVORITE_NAMES=('Rock FM' 'Radio Nacional') FAVORITE_URLS=(https://radio.invalid/one https://radio.invalid/two)
HISTORY_NAMES=() HISTORY_URLS=() SEARCH_NAMES=() SEARCH_URLS=() SEARCH_MATCHES=()
PLAYER_PID=123 PLAYER_NAME='Rock FM' PLAYER_URL=https://radio.invalid/one
PLAYER_STREAM_READY=1 PLAYER_INFO_READY=1 PLAYER_CODEC=aac PLAYER_BITRATE_KBPS=128
TRACK_HISTORY_TITLES=('Programa actual' 'Entrevista anterior') TRACK_HISTORY_TIMES=('12:00' '11:59')
unset TERMUX_VERSION PREFIX TMUX STY
for TERM in foot xterm-kitty; do
    for geometry in '132 40' '112 20' '80 24' '62 16' '50 13' '42 11' '40 10'; do
        read -r UI_COLS UI_LINES <<< "$geometry"
        for UI_UNICODE in 0 1; do
            ui_configure_glyphs
            for UI_HELP_VISIBLE in 0 1; do
                for PREF_LOGO in 0 1; do
                    PLAYER_STREAM_TITLE='El matinal'
                    for ((frame=0; frame<4; frame++)); do
                        UI_SELECTED_INDEX=$((frame%2))
                        if ((frame==1)); then PLAYER_STREAM_TITLE='Noticias y entrevistas de esta tarde con un título bastante largo'; fi
                        if ((frame==2)); then PLAYER_STREAM_TITLE='🎵 東京のニュースと音楽番組・Entrevista internacional'; fi
                        if ((frame==3)); then
                            PLAYER_STREAM_TITLE=$'Cafe\u0301 - Entrevista de hoy'
                            TRACK_HISTORY_TITLES=("$PLAYER_STREAM_TITLE" '東京 FM 🎵 - Boletín anterior')
                            FAVORITE_NAMES=('🎵 東京 FM' 'Radio Nacional')
                        fi
                        ui_draw > "$task_tmp/frame"
                        python3 "$ROOT_DIR/tests/fixtures/check-frame-scroll.py" "$task_tmp/frame" "$UI_COLS" "$UI_LINES" || fail "$TERM/$geometry/logo$PREF_LOGO/help$UI_HELP_VISIBLE"
                        if ui_draw_player_info_only > "$task_tmp/partial"; then
                            python3 "$ROOT_DIR/tests/fixtures/check-frame-scroll.py" "$task_tmp/partial" "$UI_COLS" "$UI_LINES" || fail "parcial $TERM/$geometry"
                        fi
                    done
                done
            done
        done
    done
done
for ((i=0; i<600; i++)); do ui_fit_text "東京 $i" 20; done
((${#UI_TEXT_WIDTH_CACHE[@]} <= 256)) || fail 'caché de celdas ilimitada'
printf 'ok   frames completos y parciales sin scroll ni autowrap en foot/Kitty\n'
