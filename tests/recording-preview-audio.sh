#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Audio real contra salida nula: nunca usa los altavoces ni una emisora.
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'pending_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; [[ ! -f "$task_tmp/mpv.log" ]] || cat "$task_tmp/mpv.log" >&2; exit 1; }
real_mpv=$(command -v mpv) || fail 'falta mpv'
mpv() { exec setsid -- "$real_mpv" --ao=null "$@" > "$task_tmp/mpv.log" 2>&1; }
player_is_running() { return 0; }
player_toggle_pause() { PLAYER_PAUSED=$((1-PLAYER_PAUSED)); }
PLAYER_PID=$$ PLAYER_URL=https://radio.invalid PLAYER_PAUSED=0 RECORDING_ACTIVE=0
file="$task_tmp/prueba.wav"
ffmpeg -v error -f lavfi -i 'sine=frequency=440:duration=25' "$file" || fail fixture
before=$(sha256sum "$file")
pending_preview_start "$file" || fail iniciar
# El directorio se publica en pending_preview_start (módulo cargado).
# shellcheck disable=SC2153
pid=$PENDING_PREVIEW_PID dir=$PENDING_PREVIEW_DIR
for ((i=0; i<300; i++)); do
    pending_preview_poll || true
    ((PENDING_PREVIEW_READY)) && break
    [[ -n "$PENDING_PREVIEW_PID" ]] || fail "$PENDING_NOTICE"
    sleep .02
done
((PENDING_PREVIEW_READY)) || fail 'no abre IPC de mpv real'
[[ $(ps -o pgid= -p "$pid" | tr -d ' ') == "$pid" ]] || fail 'sin grupo privado'
pending_preview_action pause || fail pausa
pending_preview_command '["get_property","pause"]' || fail consulta
[[ $PENDING_PREVIEW_RESPONSE == *'"data":true'* ]] || fail 'mpv no pausó'
pending_preview_action forward || fail avance
pending_preview_command '["get_property","time-pos"]' || fail posición
jq -e '.data >= 9 and .data < 13' <<< "$PENDING_PREVIEW_RESPONSE" >/dev/null || fail 'no avanza diez segundos'
pending_preview_action back || fail retroceso
pending_preview_action start || fail inicio
pending_preview_command '["get_property","time-pos"]' || fail posición
jq -e '.data < 1' <<< "$PENDING_PREVIEW_RESPONSE" >/dev/null || fail 'no vuelve al inicio'
# EOF real y respuesta del canal de control; luego recoger proceso y socket.
pending_preview_command '["seek",23,"absolute+exact"]' || fail 'preparar EOF'
pending_preview_action pause || fail reanudar
for ((i=0; i<200; i++)); do
    pending_preview_poll || true
    [[ -n "$PENDING_PREVIEW_PID" ]] || break
    sleep .02
done
[[ -z "$PENDING_PREVIEW_PID" && $PENDING_PREVIEW_STATE == Terminada && $PLAYER_PAUSED == 0 && ! -e "$dir" ]] || fail 'EOF no retorna o no limpia'
if kill -0 -- "-$pid" 2>/dev/null; then fail 'queda grupo privado'; fi
[[ $(sha256sum "$file") == "$before" ]] || fail 'escucha modifica archivo'
printf 'ok   escucha mpv real: salida nula, pausa, posición, saltos, EOF y grupo privado\n'
