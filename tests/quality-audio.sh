#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
# mpv/IPC reales, variantes HLS locales y señal sintética, sin red/altavoces.
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache" XDG_RUNTIME_DIR="$task_tmp/runtime"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
# Socket real en la carpeta privada del test, sin sumar prefijos largos de CI.
PLAYER_RUNTIME_DIR=$task_tmp
PLAYER_SOCKET="$task_tmp/mpv.sock"
trap 'player_stop; quality_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s: %s / %s\n' "$*" "$QUALITY_NOTICE" "$RECORDING_LAST_ERROR" >&2; [[ ! -f $task_tmp/mpv.log ]] || tail -n 25 "$task_tmp/mpv.log" >&2; exit 1; }
real_mpv=$(command -v mpv) || fail dependencia
mpv() {
    local arg
    local -a args=()
    for arg in "$@"; do
        case $arg in
            https://radio.invalid/original) args+=("$task_tmp/source.mp3") ;;
            https://radio.invalid/alternate.aac) args+=("$task_tmp/source.aac") ;;
            https://radio.invalid/master.m3u8) args+=("$task_tmp/master.m3u8") ;;
            *) args+=("$arg") ;;
        esac
    done
    exec setsid -- "$real_mpv" --no-config --ao=null --demuxer-readahead-secs=0.1 --demuxer-max-bytes=4096 "${args[@]}" >> "$task_tmp/mpv.log" 2>&1
}
app_message() { UI_MESSAGE=$1; }
ui_draw_player_info_only() { return 0; }
spectrum_tick() { return 1; }
player_title_probe_should_run() { return 1; }
wait_audio() {
    for ((i=0; i<120; i++)); do player_refresh_info || true; ((PLAYER_STREAM_READY)) && return 0; sleep .03; done
    return 1
}
property() {
    local response
    response=$(printf '{"command":["get_property","%s"],"request_id":77}\n' "$1" | socat -t 1 - UNIX-CONNECT:"$PLAYER_SOCKET") || return 1
    jq -r 'select(.request_id==77 and .error=="success") | .data | if type=="number" then .+0 else . end' <<< "$response"
}
config_load "$task_tmp/recordings" || fail configuración
favorites_init; favorites_load; history_load; quality_load
favorites_add Radio https://radio.invalid/original || fail favorita
labels_set https://radio.invalid/original Comentario || fail comentario
history_record Radio https://radio.invalid/original || fail reciente
personal_before=$(sha256sum "$KEILA_FAVORITES_FILE" "$KEILA_CONFIG_DIR/labels" "$KEILA_STATE_DIR/history")
recording_init "$task_tmp/recordings"
timeout --kill-after=1s 15s ffmpeg -nostdin -v error -f lavfi -i 'sine=frequency=440:duration=30' -c:a libmp3lame "$task_tmp/source.mp3" || fail MP3
timeout --kill-after=1s 15s ffmpeg -nostdin -v error -i "$task_tmp/source.mp3" -c:a aac -b:a 64k "$task_tmp/source.aac" || fail AAC
for rate in 64 128; do
    timeout --kill-after=1s 15s ffmpeg -nostdin -v error -i "$task_tmp/source.mp3" -c:a aac -b:a "${rate}k" -f hls -hls_time 2 -hls_list_size 0 -hls_playlist_type vod "$task_tmp/$rate.m3u8" || fail HLS
done
printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=76800,CODECS="mp4a.40.2"\n64.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=160000,CODECS="mp4a.40.2"\n128.m3u8\n' > "$task_tmp/master.m3u8"
PLAYER_VOLUME=37
player_start Radio https://radio.invalid/original || fail inicio
wait_audio || fail audio
app_toggle_mute; player_toggle_pause
old_pid=$PLAYER_PID
quality_apply_choice https://radio.invalid/original "$old_pid" https://radio.invalid/alternate.aac 0 || fail 'selección AAC'
[[ $PLAYER_PID != "$old_pid" && $PLAYER_URL == https://radio.invalid/original && $PLAYER_INPUT_URL == https://radio.invalid/alternate.aac ]] || fail 'identidad o entrada'
actual_volume=$(property volume) actual_mute=$(property mute) actual_pause=$(property pause)
[[ $actual_volume == 37 && $actual_mute == true && $actual_pause == true ]] || fail "estado de audio: volumen=$actual_volume mute=$actual_mute pausa=$actual_pause (Keila=$PLAYER_VOLUME/$PLAYER_MUTED/$PLAYER_PAUSED)"
if kill -0 -- "-$old_pid" 2>/dev/null; then fail 'mpv sustituido huérfano'; fi
player_toggle_pause
wait_audio || fail 'audio AAC'
[[ ${PLAYER_CODEC,,} == *aac* ]] || fail codec
recording_start Radio || fail grabar
[[ $RECORDING_FILE == *.aac ]] || fail 'extensión de stream original'
pid=$PLAYER_PID
quality_apply_choice https://radio.invalid/original "$pid" https://radio.invalid/master.m3u8 76800 && fail 'cambia durante grabación'
[[ $PLAYER_PID == "$pid" ]] || fail 'interrumpe mpv grabando'
for ((i=0; i<50; i++)); do [[ ! -s $RECORDING_FILE ]] || break; sleep .05; done
for ((i=0; i<140; i++)); do
    close_status=0; recording_stop || close_status=$?
    ((close_status != 0)) || break
    ((close_status == 2)) || fail cierre
    sleep .03
done
[[ $close_status == 0 ]] || fail 'cierre pendiente'
[[ $RECORDING_LAST_VERIFIED == 1 ]] || fail 'audio grabado inválido'
for rate in 76800 160000; do
    quality_apply_choice https://radio.invalid/original "$PLAYER_PID" https://radio.invalid/master.m3u8 "$rate" || fail 'selección HLS'
    wait_audio || fail 'audio HLS'
    [[ $(property options/hls-bitrate) == "$rate" && $PLAYER_HLS_RATE == "$rate" && $PLAYER_MUTED == 1 && $PLAYER_VOLUME == 37 ]] || fail 'bitrate o audio no aplicados'
done
[[ $(sha256sum "$KEILA_FAVORITES_FILE" "$KEILA_CONFIG_DIR/labels" "$KEILA_STATE_DIR/history") == "$personal_before" ]] || fail 'altera favoritas/comentarios/recientes'
player_stop; QUALITY_TARGETS=() QUALITY_RATES=(); quality_load
player_start Radio https://radio.invalid/original || fail reinicio
wait_audio || fail 'audio tras carga'
[[ $PLAYER_INPUT_URL == https://radio.invalid/master.m3u8 && $(property options/hls-bitrate) == 160000 ]] || fail 'reinicio no usa elección'
quality_apply_choice https://radio.invalid/original "$PLAYER_PID" https://radio.invalid/original 0 || fail original
wait_audio || fail 'audio original'
[[ $PLAYER_INPUT_URL == "$PLAYER_URL" && $(property options/hls-bitrate) == max && -z ${QUALITY_TARGETS[https://radio.invalid/original]:-} ]] || fail 'original no restaura mpv'
printf 'ok   mpv real: alternativas AAC/HLS, bitrate, volumen/silencio/pausa, grabación y reinicio\n'
