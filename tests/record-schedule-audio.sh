#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# IPC/grabación reales sobre audio sintético; sin red ni altavoces.
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache" XDG_RUNTIME_DIR="$task_tmp/runtime"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'player_stop; rm -rf -- "$task_tmp"' EXIT
fail() {
    printf 'FAIL %s: estado=%s fase=%s aviso=%s\n' "$*" "$RECORD_PLAN_STATE" "$RECORDING_PHASE" "$RECORD_PLAN_NOTE" >&2
    [[ ! -f "$task_tmp/mpv.log" ]] || cat "$task_tmp/mpv.log" >&2
    exit 1
}
real_mpv=$(command -v mpv) || fail 'falta mpv'
mpv() {
    # Mantener nombre/URL en Keila, pero sustituir únicamente la fuente en mpv.
    # El resto, incluidos IPC, silencio, volumen y stream-record, son reales.
    local arg
    local -a args=()
    for arg in "$@"; do
        if [[ "$arg" == https://radio.invalid/prueba ]]; then args+=("$task_tmp/fuente.mp3")
        else args+=("$arg"); fi
    done
    exec setsid -- "$real_mpv" --no-config --ao=null --demuxer-readahead-secs=0.1 --demuxer-max-bytes=4096 "${args[@]}" >> "$task_tmp/mpv.log" 2>&1
}
# Aislar persistencia y visualización, no el flujo de reproducción/grabación.
app_message() { UI_MESSAGE=$1; }
save_player_state() { return 0; }
track_history_start_station() { :; }
track_history_observe() { return 1; }
history_observe() { return 1; }
ui_draw_player_info_only() { return 0; }
spectrum_tick() { return 1; }
player_title_probe_should_run() { return 1; }
recording_init "$task_tmp/grabaciones" || fail carpeta
printf 'fase: crear fuente sintética y programar\n'
timeout --kill-after=1s 15s ffmpeg -nostdin -v error -f lavfi -i 'sine=frequency=440:duration=120' -c:a libmp3lame "$task_tmp/fuente.mp3" || fail fuente
before=$(sha256sum "$task_tmp/fuente.mp3")
audio_level() {
    local report
    report=$(timeout --kill-after=1s 5s ffmpeg -nostdin -hide_banner -i "$1" -ss 0.2 -t 1 -af volumedetect -f null - 2>&1) || return 1
    [[ "$report" =~ mean_volume:[[:space:]](-?[0-9]+([.][0-9]+)?)[[:space:]]dB ]] || return 1
    printf '%s' "${BASH_REMATCH[1]}"
}
original_level=$(audio_level "$task_tmp/fuente.mp3") || fail 'nivel de fuente'
for stop_after in 0 1; do
    PLAYER_VOLUME=$((37*(1-stop_after))) PLAYER_MUTED=1
    volume=$PLAYER_VOLUME
    record_plan_arm 'Radio Prueba' https://radio.invalid/prueba "$((EPOCHSECONDS+1))" "$((EPOCHSECONDS+61))" "$EPOCHSECONDS" "$stop_after" || fail armar
    printf 'fase: esperar audio (parar al final=%s, volumen=%s, mute=Sí)\n' "$stop_after" "$volume"
    for ((i=0; i<160; i++)); do
        app_poll_player || true
        [[ "$RECORD_PLAN_STATE" == recording && -s "$RECORD_PLAN_FILE" ]] && break
        case "$RECORD_PLAN_STATE" in failed|skipped|cancelled) fail inicio ;; esac
        sleep .05
    done
    [[ "$RECORD_PLAN_STATE" == recording || "$RECORD_PLAN_STATE" == preparing ]] || fail 'no se inicia el archivo'
    pid=$PLAYER_PID file=$RECORD_PLAN_FILE
    [[ -f "$file.pending" ]] || fail 'falta marcador activo'
    [[ "$PLAYER_VOLUME" == "$volume" && "$PLAYER_MUTED" == 1 ]] || fail 'cambia volumen/silencio'
    response=$(printf '%s\n' '{"command":["get_property","mute"],"request_id":77}' '{"command":["get_property","volume"],"request_id":78}' | socat -t 1 - UNIX-CONNECT:"$PLAYER_SOCKET") || fail IPC
    jq -e 'select(.request_id == 77 and .error == "success" and .data == true)' <<< "$response" >/dev/null || fail 'mpv no conserva silencio'
    jq -e --argjson volume "$volume" 'select(.request_id == 78 and .error == "success" and .data == $volume)' <<< "$response" >/dev/null || fail 'mpv no conserva volumen'
    printf 'fase: adelantar solo el fin previsto y verificar el cierre real\n'
    # El reloj del motor se prueba exhaustivamente aparte; acelerar esta prueba.
    RECORD_PLAN_END=$EPOCHSECONDS
    for ((i=0; i<140; i++)); do
        app_poll_player || true
        [[ "$RECORD_PLAN_STATE" == closing || "$RECORD_PLAN_STATE" == recording ]] || break
        sleep .05
    done
    [[ "$RECORD_PLAN_STATE" == 'done' && "$RECORDING_ACTIVE" == 0 && "$RECORDING_LAST_VERIFIED" == 1 ]] || fail cierre
    [[ -s "$file" && ! -e "$file.pending" ]] || fail 'no finaliza archivo'
    if ((stop_after)); then
        [[ -z "$PLAYER_PID" && "$APP_RECONNECT_ELIGIBLE" == 0 && "$APP_RECONNECT_NEXT_AT" == 0 ]] || fail 'no detiene reproducción/reintentos'
    else
        [[ "$PLAYER_PID" == "$pid" ]] || fail 'fin normal sustituye reproductor'
        player_is_running || fail 'fin normal detiene radio'
    fi
    [[ $(sha256sum "$task_tmp/fuente.mp3") == "$before" ]] || fail 'modifica fuente'
    timeout --kill-after=1s 5s "$real_mpv" --no-config --ao=null --no-video --really-quiet --length=0.2 "$file" || fail 'archivo no reproducible'
    recorded_level=$(audio_level "$file") || fail 'grabación muda o sin audio medible'
    awk -v original="$original_level" -v recorded="$recorded_level" 'BEGIN {d=original-recorded; exit !(d >= -1 && d <= 1)}' || fail 'volumen de grabación diferente al original'
    printf 'nivel medio: fuente=%s dB, grabación=%s dB\n' "$original_level" "$recorded_level"
    player_stop
    if kill -0 -- "-$pid" 2>/dev/null; then fail 'grupo huérfano'; fi
done
printf 'ok   mpv real: silencio/volumen cero no atenúan el archivo; parada optativa tras cierre\n'
