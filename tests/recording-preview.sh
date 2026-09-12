#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'pending_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
file="$task_tmp/audio.mp3"
printf 'audio ficticio' > "$file"
mpv() { exec sleep 30; }
player_is_running() { [[ -n "$PLAYER_PID" ]]; }
player_toggle_pause() { ((radio_error == 0)) || return 1; PLAYER_PAUSED=$((1-PLAYER_PAUSED)); }
mode=success radio_error=0
pending_preview_exchange() {
    printf '%s\n' "$1" >> "$task_tmp/commands"
    case "$mode" in
        transport) return 1 ;;
        wrong) printf '{"request_id":-1,"error":"success"}\n' ;;
        reject) printf '{"request_id":%s,"error":"command error"}\n' "$PENDING_PREVIEW_REQUEST" ;;
        unseekable) printf '{"data":false,"request_id":%s,"error":"success"}\n' "$PENDING_PREVIEW_REQUEST" ;;
        *) printf '{"data":true,"request_id":%s,"error":"success"}\n' "$PENDING_PREVIEW_REQUEST" ;;
    esac
}
PLAYER_PID=$$ PLAYER_URL=https://radio.invalid PLAYER_PAUSED=0 PLAYER_MUTED=1 PLAYER_VOLUME=63
HISTORY_PENDING_URL=sin-cambios ALARM_AT=123456 RECORDING_ACTIVE=0
pending_preview_start "$file" || fail inicio
[[ $PLAYER_PAUSED == 1 && $PENDING_PREVIEW_READY == 0 && $PENDING_PREVIEW_STATE == Preparando ]] || fail preparación
pid=$PENDING_PREVIEW_PID dir=$PENDING_PREVIEW_DIR
[[ $(stat -c %a "$dir") == 700 ]] || fail 'socket no privado'
pending_preview_poll || fail readiness
[[ $PENDING_PREVIEW_READY == 1 ]] || fail 'no reconoce respuesta'
pending_preview_action pause || fail pausa
[[ $PENDING_PREVIEW_PAUSED == 1 && $PLAYER_PAUSED == 1 ]] || fail 'pausa cambia radio'
pending_preview_action forward || fail avance
pending_preview_action back || fail retroceso
pending_preview_action start || fail inicio
jq -se 'any(.[]; .command == ["seek",10,"relative+exact"]) and any(.[]; .command == ["seek",-10,"relative+exact"]) and any(.[]; .command == ["seek",0,"absolute+exact"])' "$task_tmp/commands" >/dev/null || fail 'comandos de seek'
for mode in reject wrong transport; do
    if pending_preview_action pause; then fail "acepta $mode"; fi
    [[ $PENDING_PREVIEW_PAUSED == 1 ]] || fail 'cambia pausa sin confirmar'
done
mode=unseekable
if pending_preview_action forward; then fail 'acepta archivo no seekable'; fi
mode=success
# No nuevas consultas periódicas después de confirmar que el audio está listo.
before=$(wc -l < "$task_tmp/commands")
for ((i=0; i<100; i++)); do pending_preview_poll || true; done
[[ $(wc -l < "$task_tmp/commands") == "$before" ]] || fail 'consulta IPC por tick'
pending_preview_stop
[[ ! -e "$dir" && $PLAYER_PAUSED == 0 && $PLAYER_VOLUME == 63 && $PLAYER_MUTED == 1 && $HISTORY_PENDING_URL == sin-cambios && $ALARM_AT == 123456 ]] || fail retorno
if kill -0 "$pid" 2>/dev/null; then fail 'queda reproductor vivo'; fi
PLAYER_PAUSED=1
pending_preview_start "$file"; pending_preview_stop
[[ $PLAYER_PAUSED == 1 ]] || fail 'reanuda radio que ya estaba pausada'
PLAYER_PAUSED=0 radio_error=1
if pending_preview_start "$file"; then fail 'inicia sin pausar radio'; fi
[[ -z "$PENDING_PREVIEW_PID" && -z "$PENDING_PREVIEW_DIR" ]] || fail 'fuga al fallar pausa'
radio_error=0
pending_preview_start "$file"
PLAYER_URL=https://alarma.invalid PLAYER_PAUSED=0
pending_preview_poll || fail alarma
[[ -z "$PENDING_PREVIEW_PID" && $PLAYER_PAUSED == 0 && $PLAYER_URL == https://alarma.invalid ]] || fail 'revierte alarma'
pending_preview_start "$file"
PENDING_PREVIEW_DEADLINE=0
pending_preview_poll || fail timeout
[[ -z "$PENDING_PREVIEW_PID" && $PLAYER_PAUSED == 0 && $PENDING_PREVIEW_STATE == Error ]] || fail 'timeout deja radio pausada'
# EOF y error de decodificación vuelven a radio sin tocar ni finalizar el archivo.
for exit_status in 0 2; do
    mpv() { return "$exit_status"; }
    pending_preview_start "$file"
    wait "$PENDING_PREVIEW_PID" || true
    pending_preview_poll || fail eof
    [[ $PLAYER_PAUSED == 0 && -s "$file" && -z "$PENDING_PREVIEW_PID" ]] || fail 'EOF o error pierde audio'
    if ((exit_status)); then [[ $PENDING_PREVIEW_STATE == Error ]] || fail 'oculta error'; fi
done

# Navegación real del panel: flechas horizontales solo buscan aquí. Redimensionar
# conserva el control seleccionado y Enter lo activa, sin memorizar letras.
mpv() { exec sleep 30; }
ui_refresh_size() { UI_COLS=40 UI_LINES=10; }; tput() { :; }
app_poll_player() { ((polls+=1)); return 1; }
catalog_poll() { return 1; }; pending_scan_poll() { return 1; }; ui_message_tick() { return 1; }
step=0 polls=0
input_read() {
    ((step+=1)); INPUT_KEY=''
    case "$step" in
        1) INPUT_EVENT=TICK ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=p ;;
        3) INPUT_EVENT=RIGHT ;;
        4) INPUT_EVENT=LEFT ;;
        5) INPUT_EVENT=DOWN ;;
        6) INPUT_EVENT=RESIZE ;;
        7) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_recording_preview "$file" >/dev/null || fail menú
[[ $step == 8 && $polls == 1 && $PLAYER_PAUSED == 0 && -z "$PENDING_PREVIEW_PID" ]] || fail 'menú no vuelve a radio'
printf 'ok   escucha: IPC validado, pausa, saltos, EOF, error, alarma, retorno y controles\n'
