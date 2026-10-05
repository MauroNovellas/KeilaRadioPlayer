#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Bucle de mantenimiento real; sin red, altavoces, catálogo ni datos personales.
set -uo pipefail
export KEILA_NOW_PLAYING=0
probe_root=$1 probe_mode=$2 probe_seconds=$3 probe_dir=$4
set -- --version
source "$probe_root/keila-radio" >/dev/null
trap 'input_shutdown; spectrum_stop; exec 3>&-' EXIT
export XDG_CONFIG_HOME="$probe_dir/config" XDG_STATE_HOME="$probe_dir/state" XDG_CACHE_HOME="$probe_dir/cache"
mkfifo "$probe_dir/input"
exec 3<>"$probe_dir/input"
input_init
UI_ACTIVE=1 UI_SUSPENDED=0 UI_COLS=132 UI_LINES=40
PREF_LOGO=0 SPECTRUM_ENABLED=0 HISTORY_PENDING_URL=''
player_title_probe_should_run() { return 1; }
ui_draw_player_info_only() { return 0; }
ui_draw_spectrum_only() { return 0; }
app_message() { UI_MESSAGE=$1; }
player_is_running() { [[ -n $PLAYER_PID ]]; }
player_query_snapshot() {
    printf '{"1":{},"2":"mp3","3":128000,"4":{"samplerate":44100,"channels":2},"5":false,"10":false,"11":%s}\n' "$EPOCHSECONDS"
}
if [[ $probe_mode != stopped ]]; then
    PLAYER_PID=probe PLAYER_NAME='Radio sintética' PLAYER_URL=https://radio.invalid/probe
    PLAYER_STREAM_READY=1 PLAYER_INFO_READY=1
    PLAYER_STREAM_LAST_PROGRESS_AT=$EPOCHSECONDS
fi
if [[ $probe_mode == menu ]]; then PREFERENCES_ACTIVE=1; fi
if [[ $probe_mode == animation ]]; then
    # Solo medir el lector/estado del analizador, no FFT ni servidor de audio.
    SPECTRUM_ENABLED=1 SPECTRUM_AVAILABLE=yes SPECTRUM_SOURCE=synthetic
    SPECTRUM_DIR="$probe_dir/spectrum"
    mkdir "$SPECTRUM_DIR"
    printf '0 2 4 6 8 10 12 14 16 14 12 10 8 6 4 2\n' > "$SPECTRUM_DIR/levels"
    sleep 60 &
    SPECTRUM_PID=$!
fi
probe_ticks=0 probe_end=$((SECONDS+probe_seconds))
while ((SECONDS < probe_end)); do
    input_read <&3 || exit 1
    [[ $INPUT_EVENT == TICK ]] || continue
    ((probe_ticks+=1))
    app_poll_player >/dev/null || true
    ui_message_tick >/dev/null || true
done
printf '%s\n' "$probe_ticks" > "$probe_dir/ticks"
