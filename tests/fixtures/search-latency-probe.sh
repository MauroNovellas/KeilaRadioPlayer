#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Bucle real y dibujo real bajo PTY; solo audio/red y ritmo FFT son dobles.
set -uo pipefail
export KEILA_NOW_PLAYING=0
ROOT_DIR=$1 notify_fd=$2 fixture=$3 probe_cols=$4 probe_lines=$5 probe_mode=${6:-async}
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'search_async_cleanup; logo_cleanup; ui_leave; input_shutdown' EXIT
KEILA_NO_UPDATE_CHECK=1
KEILA_STATIONS_TSV=$fixture
stations_tsv_valid() { return 0; }
stations_catalog_valid() { return 0; }
catalog_poll() { return 1; }
player_is_running() { return 0; }
player_refresh_info() { return 1; }
history_observe() { return 1; }
PLAYER_PID=$$ PLAYER_NAME='Radio de prueba' PLAYER_URL=https://radio.invalid/0
PLAYER_INFO_READY=1 PLAYER_BUFFERING=0
FAVORITE_NAMES=('Radio de prueba') FAVORITE_URLS=("$PLAYER_URL")
PREF_LOGO=1 SPECTRUM_ENABLED=1 SPECTRUM_AVAILABLE=yes
SPECTRUM_LEVELS=(0 2 4 6 8 10 12 14 16 14 12 10 8 6 4 2)
SPECTRUM_PEAK_LEVELS=(0 2 4 6 8 10 12 14 16 14 12 10 8 6 4 2)
unset NO_COLOR KEILA_NO_COLOR KEILA_ASCII_UI
PREF_COLOR=1 UI_COLOR=1 UI_UNICODE=1
ui_refresh_size() { UI_COLS=$probe_cols UI_LINES=$probe_lines; }
tput() {
    case $1 in
        cup) printf '\033[%d;%dH' "$(($2+1))" "$(($3+1))" ;;
        colors) printf 256 ;;
        setaf) printf '\033[38;5;%sm' "$2" ;;
        bold) printf '\033[1m' ;; sgr0) printf '\033[0m' ;;
        clear) printf '\033[H\033[2J' ;;
        smcup) printf '\033[?1049h' ;; rmcup) printf '\033[?1049l' ;;
        civis) printf '\033[?25l' ;; cnorm) printf '\033[?25h' ;;
        cols) printf '%s' "$probe_cols" ;; lines) printf '%s' "$probe_lines" ;;
    esac
}
probe_notify() { printf '%s\t%s\n' "$1" "$SEARCH_QUERY" >&"$notify_fd"; }

# Solo clonar funciones de este repositorio, nunca contenido del catálogo.
for probe_fn in search_draw_view ui_draw_search_query_only search_async_start search_filter; do
    probe_definition=$(declare -f "$probe_fn")
    probe_definition=${probe_definition/"$probe_fn ()"/"probe_original_$probe_fn ()"}
    eval "$probe_definition"
done
search_draw_view() {
    probe_original_search_draw_view
    if ((probe_cols >= 120)); then
        if ! ((UI_LOGO_LAYOUT && LOGO_DRAWN)) || [[ $LOGO_BACKEND != sixel ]]; then
            printf '\nFAIL logo layout=%s drawn=%s backend=%s cells=%s/%s ready=%s request=%s signature=%s\n' \
                "$UI_LOGO_LAYOUT" "$LOGO_DRAWN" "$LOGO_BACKEND" "$INPUT_CELL_WIDTH" "$INPUT_CELL_HEIGHT" "$LOGO_READY_URL" "$LOGO_REQUEST" "$LOGO_SIGNATURE" >&2
            exit 1
        fi
    fi
    probe_notify frame
}
ui_draw_search_query_only() {
    probe_original_ui_draw_search_query_only || return $?
    probe_notify field
}
search_async_start() {
    probe_original_search_async_start || return $?
    probe_notify work
}
search_filter() {
    if [[ $probe_mode == foreground ]] && ((SEARCH_ACTIVE)); then
        probe_notify work
        sleep .35
    fi
    probe_original_search_filter
}
if [[ $probe_mode == foreground ]]; then
    search_async_tick() { search_apply_pending_filter; }
else
    SEARCH_WORKER=$ROOT_DIR/tests/fixtures/search-delayed-worker.sh
fi

# Las actualizaciones del espectro ejercitan el dibujo parcial a 20 Hz. No
# conectar una radio ni medir FFT, audio físico o render GPU del terminal.
probe_spectrum_at=0 probe_spectrum_frame=0
spectrum_tick() {
    local now=${EPOCHREALTIME//[.,]/} band
    ((now-probe_spectrum_at >= 50000)) || return 1
    probe_spectrum_at=$now
    ((probe_spectrum_frame+=1))
    for ((band=0; band<16; band++)); do
        SPECTRUM_LEVELS[band]=$(((probe_spectrum_frame+band)%17))
    done
    return 0
}
if ((probe_cols >= 120)); then
    unset TERMUX_VERSION PREFIX KITTY_WINDOW_ID TMUX STY VTE_VERSION
    TERM=foot COLORTERM=truecolor
else
    TERM=xterm-256color TERMUX_VERSION=test
fi
input_init
ui_enter
LOGO_BACKEND=sixel LOGO_READY_URL=$PLAYER_URL LOGO_SIXEL_SIDE=96
LOGO_SIXEL_BODY='"1;1;96;96#0;2;0;60;20#0!96~-!96~-!96~-!96~-!96~-!96~'
INPUT_CELL_WIDTH=8 INPUT_CELL_HEIGHT=16
LOGO_CELL_QUERY_KEY="$TERM|$probe_cols|$probe_lines" LOGO_GENERATION=1
logo_request_signature 0
LOGO_REQUEST=$LOGO_SIGNATURE
stations_select_fzf || true
[[ -z $SEARCH_WORK_PID && -z $SEARCH_WORK_DIR ]] || exit 1
probe_notify closed
