#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'logo_cleanup >/dev/null; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
keila_init_paths || fail rutas
app_message() { UI_MESSAGE=$1; }
logo_choose_backend() { LOGO_BACKEND=blocks; }
TERM=xterm-256color UI_COLS=132 UI_LINES=30 PLAYER_PID=$$ PLAYER_URL=https://radio.invalid/stream
unset PREFIX TERMUX_VERSION
((PREF_LOGO == 0)) || fail 'se activa por defecto'
app_toggle_logo || fail activar
preferences_load
((PREF_LOGO == 1)) || fail 'no persiste'
data_validate "$KEILA_CONFIG_DIR/preferences" preferences || fail 'formato persistente'
cache=$KEILA_CACHE_DIR/logos
mkdir -p "$cache"
key=$(printf '%s' "$PLAYER_URL" | sha256sum); key=${key%% *}
pixels=$(printf '%036864d' 0); pixels=${pixels//0/A}
printf 'keila-logo-v1\n%s\n%0864d\n' "$pixels" 0 > "$cache/$key.logo"
logo_poll || fail 'no inicia tarea'
pid=$LOGO_PID
for ((i=0; i<100; i++)); do LOGO_CHECK_AT=0; logo_poll || true; [[ -n $LOGO_PID ]] || break; sleep .02; done
[[ -z $LOGO_PID && $LOGO_READY_URL == "$PLAYER_URL" && ${#LOGO_ROWS[@]} == 6 ]] || fail 'no publica caché'
for ((i=0; i<100; i++)); do logo_poll && fail 'trabajo repetido'; done
if kill -0 -- "-$pid" 2>/dev/null; then fail 'grupo terminado sigue vivo'; fi
# Un cambio de emisora cancela inmediatamente el trabajo anterior y sus hijos.
real_worker=$LOGO_WORKER
LOGO_WORKER=$ROOT_DIR/tests/fixtures/logo-slow-worker.sh
PLAYER_URL=https://lenta.invalid/stream
logo_poll || fail lento
slow_pid=$LOGO_PID old_job=$LOGO_JOB
for ((i=0; i<100; i++)); do [[ ! -f "$old_job/child" ]] || break; sleep .02; done
[[ -f "$old_job/child" ]] || fail 'trabajo lento no arranca'
LOGO_WORKER=$real_worker PLAYER_URL=https://radio.invalid/stream
logo_poll || fail 'cambio de emisora'
[[ ! -e $old_job && $LOGO_READY_URL == '' ]] || fail 'publica imagen vieja o deja temporal'
if kill -0 -- "-$slow_pid" 2>/dev/null; then fail 'hijos huérfanos al cambiar'; fi
app_toggle_logo || fail desactivar
[[ -z $LOGO_PID && $PREF_LOGO == 0 ]] || fail 'desactivar deja tarea'
preferences_save() { return 1; }
app_toggle_logo && fail 'guardado fallido'
((PREF_LOGO == 0)) || fail 'error cambia preferencia'
printf 'ok   logos: persistencia, worker real de caché, cambio/cancelación sin huérfanos\n'
