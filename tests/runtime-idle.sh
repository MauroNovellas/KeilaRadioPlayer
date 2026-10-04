#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
expect_timeout() {
    input_poll_timeout
    [[ $INPUT_READ_TIMEOUT == "$1" ]] || fail "$2: timeout=$INPUT_READ_TIMEOUT, esperado=$1"
}
unset KEILA_INPUT_POLL_INTERVAL
INPUT_POLL_INTERVAL=0.02 SEARCH_ACTIVE=0 SEARCH_FILTER_DIRTY=0 SEARCH_WORK_PID=''
QUALITY_JOB_PID='' LOGO_PID='' PLAYER_PID='' SPECTRUM_ENABLED=0
PREFERENCES_ACTIVE=0 UI_SUSPENDED=0 PLAYER_PAUSED=0 PLAYER_STREAM_READY=0 PLAYER_INFO_READY=0
expect_timeout 0.2 detenido
PLAYER_PID=probe PLAYER_STREAM_READY=1 PLAYER_INFO_READY=1 SPECTRUM_ENABLED=1 SPECTRUM_AVAILABLE=yes
expect_timeout 0.02 animación
PREFERENCES_ACTIVE=1; expect_timeout 0.2 menú; PREFERENCES_ACTIVE=0
UI_SUSPENDED=1; expect_timeout 0.2 suspensión; UI_SUSPENDED=0
PLAYER_PAUSED=1; expect_timeout 0.2 pausa; PLAYER_PAUSED=0
SPECTRUM_AVAILABLE=no; expect_timeout 0.2 'sin monitor'; SPECTRUM_AVAILABLE=yes
SPECTRUM_ENABLED=0
SEARCH_ACTIVE=1 SEARCH_FILTER_DIRTY=1; expect_timeout 0.02 'consulta pendiente'
SEARCH_FILTER_DIRTY=0 SEARCH_WORK_PID=probe; expect_timeout 0.02 'filtro en curso'
SEARCH_WORK_PID=''; expect_timeout 0.2 'búsqueda esperando teclado'
SEARCH_ACTIVE=0 QUALITY_JOB_PID=probe; expect_timeout 0.02 'calidad pendiente'
QUALITY_JOB_PID='' LOGO_PID=probe; expect_timeout 0.02 'logo pendiente'; LOGO_PID=''
INPUT_POLL_INTERVAL=0.05; expect_timeout 0.05 'intervalo en vivo'
INPUT_POLL_INTERVAL=0.02 KEILA_INPUT_POLL_INTERVAL=0.02; expect_timeout 0.02 'override explícito'
unset KEILA_INPUT_POLL_INTERVAL

# El timeout de reposo no es un sleep delante de la lectura. Una tecla llegada
# durante read lo interrumpe sin esperar a los 200 ms del mantenimiento.
mkfifo "$task_tmp/input"
exec {probe_fd}<>"$task_tmp/input"
(
    sleep .03
    printf '%s' "${EPOCHREALTIME//[.,]/}" > "$task_tmp/sent"
    printf x >&"$probe_fd"
) &
probe_writer=$!
input_read <&"$probe_fd" || fail 'no recibe tecla durante reposo'
probe_received=${EPOCHREALTIME//[.,]/}
wait "$probe_writer" || fail 'emisor de tecla'
read -r probe_sent < "$task_tmp/sent" || true
[[ $INPUT_EVENT == KEY && $INPUT_KEY == x ]] || fail 'tecla alterada por reposo'
((probe_received-probe_sent < 150000)) || fail 'la tecla esperó al tick de reposo'
exec {probe_fd}>&-
INPUT_RESIZE_PENDING=1
input_read </dev/null || fail resize
[[ $INPUT_EVENT == RESIZE ]] || fail 'resize retrasado'

# Las APIs de texto siguen disponibles; la variante state publica en el padre.
KEILA_PLAYER_NOW=1234
player_now state
[[ $PLAYER_NOW_VALUE == 1234 && $(player_now) == 1234 ]] || fail 'API de reloj player'
unset KEILA_PLAYER_NOW
app_reconnect_now state
[[ $APP_RECONNECT_NOW_VALUE =~ ^[0-9]+$ ]] || fail 'reloj de reconexión'
player_events_now state
[[ $PLAYER_EVENTS_NOW_VALUE =~ ^[0-9]+$ ]] || fail 'reloj de eventos'

# No analizar audio que el menú tapa; restaurar sin cambiar la preferencia.
probe_stops=0 probe_starts=0
player_is_running() { return 0; }
spectrum_stop() { ((probe_stops+=1)); SPECTRUM_PID=''; }
spectrum_start() { ((probe_starts+=1)); SPECTRUM_PID=probe; return 0; }
SPECTRUM_ENABLED=1 SPECTRUM_AVAILABLE=yes SPECTRUM_PID=probe PREFERENCES_ACTIVE=1
spectrum_tick || fail 'no detiene captura oculta'
[[ $probe_stops == 1 && $SPECTRUM_ENABLED == 1 ]] || fail 'cambia preferencia al ocultar'
spectrum_tick && fail 'menú estable repite transición'
[[ $probe_stops == 1 ]] || fail 'repite stop oculto'
PREFERENCES_ACTIVE=0
spectrum_tick || fail 'no reanuda captura al volver'
[[ $probe_starts == 1 ]] || fail 'reanuda más de una captura'
PREFERENCES_ACTIVE=1 SPECTRUM_ENABLED=0 SPECTRUM_PID=''
spectrum_toggle || fail 'activación desde Opciones'
[[ $SPECTRUM_ENABLED == 1 && $probe_starts == 1 ]] || fail 'crea captura oculta al activar'

# El launcher también limpia al analizador si mpv ya no existe.
PLAYER_PID='' SPECTRUM_PID=probe
player_is_running() { return 1; }
app_poll_player || fail 'no publica cierre de captura sin mpv'
[[ -z $SPECTRUM_PID && $probe_stops == 2 ]] || fail 'analizador queda huérfano'
printf 'ok   reposo: 5 Hz, teclado inmediato, tareas rápidas, relojes y captura visible\n'
