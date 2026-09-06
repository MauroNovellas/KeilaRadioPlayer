#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "$3: esperado '$1', obtenido '$2'"; }

PLAYER_RUNTIME_DIR="$task_tmp/runtime"
PLAYER_STREAM_READY=1
PLAYER_PAUSED=0
PLAYER_PID='test'
player_is_running() { return 0; }

source "$ROOT_DIR/lib/spectrum.sh"
source "$ROOT_DIR/lib/ui.sh"

# La lectura acepta solamente un frame completo de 16 bandas y comunica si
# cambió para que el bucle principal redibuje la TUI.
SPECTRUM_DIR="$task_tmp/frame"
mkdir -p "$SPECTRUM_DIR"
SPECTRUM_PID=$$
printf '0 1 2 3 4 5 6 7 8 7 6 5 4 3 2 1\n' > "$SPECTRUM_DIR/levels"
spectrum_tick || fail 'el frame nuevo no solicitó redibujado'
assert_eq '8' "${SPECTRUM_LEVELS[8]}" 'pico central leído'
if spectrum_tick; then fail 'un frame idéntico solicitó otro redibujado'; fi

printf '0 1 2\n' > "$SPECTRUM_DIR/levels"
if spectrum_tick; then fail 'un frame incompleto fue aceptado'; fi
assert_eq '8' "${SPECTRUM_LEVELS[8]}" 'frame inválido conservó el anterior'

UI_UNICODE=1
ui_configure_glyphs
assert_eq '     ███████    ' "$(ui_spectrum_row 5)" 'fila gráfica del espectro'
assert_eq '▁▁▂▃▄▅▆▇█▇▆▅▄▃▂▁' "$(ui_spectrum_bars)" 'barras de altura variable'

# Incluso un proceso que ignore SIGTERM queda cerrado en un tiempo acotado.
bash -c 'trap "" TERM; while :; do :; done' &
stubborn_pid=$!
SPECTRUM_PID=$stubborn_pid
started_at=$SECONDS
spectrum_stop
((SECONDS - started_at <= 2)) || fail 'la detención del analizador bloqueó la TUI'
if kill -0 "$stubborn_pid" 2>/dev/null; then fail 'el proceso auxiliar sobrevivió al cierre'; fi

# Mostrarlo sin una emisora activa solo cambia la preferencia; la captura se
# iniciará en el primer tick que confirme reproducción real.
SPECTRUM_PID=''
SPECTRUM_ENABLED=1
spectrum_toggle || fail 'ocultar analizador'
assert_eq '0' "$SPECTRUM_ENABLED" 'analizador oculto'
player_is_running() { return 1; }
spectrum_start() { fail 'intentó capturar sin reproducción'; }
spectrum_toggle || fail 'mostrar analizador sin reproducción'
assert_eq '1' "$SPECTRUM_ENABLED" 'analizador preparado'

# El motivo concreto sobrevive a la detección para poder mostrarlo en la TUI y
# en --check; no queda encerrado en una sustitución de comandos.
# shellcheck disable=SC2317
timeout() { return 1; }
if spectrum_find_source; then fail 'aceptó un servidor de audio inaccesible'; fi
[[ -n "$SPECTRUM_ERROR" ]] || fail 'la detección no conservó el motivo del fallo'
unset -f timeout

printf 'ok   analizador: frames, representación y activación diferida\n'
