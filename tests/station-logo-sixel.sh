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
mkdir "$task_tmp/job" "$task_tmp/cache"
job=$task_tmp/job
timeout 10s ffmpeg -nostdin -v error -f lavfi -i 'testsrc=size=96x96' -frames:v 1 -threads 1 "$job/image.png" || fail fuente
cp "$job/image.png" "$job/image"
logo_convert "$job" || fail convertir
for side in 42 60 96; do
    logo_prepare_sixel "$job" "$side" || fail "codificar $side"
    python3 "$ROOT_DIR/tests/fixtures/check-sixel.py" "$job/sixel" "$job/rgb" "$side" || fail "validar $side"
done
printf 'keila-sixel-v1\n96\n"1;1;96;96\033[2J\n' > "$task_tmp/corrupt"
logo_read_sixel "$task_tmp/corrupt" && fail 'acepta escapes de caché'
printf 'keila-sixel-v1\n96\n"1;1;96;96!999999~\n' > "$task_tmp/corrupt"
logo_read_sixel "$task_tmp/corrupt" && fail 'acepta raster/repetición enorme'
printf 'keila-sixel-v1\n96\n"1;1;96;96"1;1;999999;999999#0~\n' > "$task_tmp/corrupt"
logo_read_sixel "$task_tmp/corrupt" && fail 'acepta cambio posterior de raster'
logo_read_sixel "$job/sixel" 60 && fail 'acepta imagen mayor que las celdas reservadas'
logo_prepare_sixel "$job" 95 && fail 'acepta alto no acotado por bandas'

# Caché antigua -> SIXEL, sin volver a descargar ni decodificar la imagen.
key=$(printf '%s' https://radio.invalid/live | sha256sum); key=${key%% *}
cp "$job/result" "$task_tmp/cache/$key.logo"
mkdir "$task_tmp/hit"
logo_fetch() { fail 'descarga una imagen ya cacheada'; }
logo_worker https://radio.invalid/live '' "$task_tmp/cache" "$task_tmp/hit" Radio 60 || fail 'cache a SIXEL'
python3 "$ROOT_DIR/tests/fixtures/check-sixel.py" "$task_tmp/hit/sixel" "$task_tmp/hit/rgb" 60 || fail 'SIXEL de caché'

# Medidas asíncronas: una consulta por geometría, sin lectores externos.
logo_choose_backend() { LOGO_BACKEND=sixel; }
TERM=foot UI_COLS=132 UI_LINES=30 UI_COLOR=1 UI_UNICODE=1
PLAYER_URL=https://radio.invalid/live PLAYER_NAME=Radio
logo_prepare_backend > "$task_tmp/query" && fail 'no espera las dimensiones'
[[ $(<"$task_tmp/query") == $'\033[16t' && $LOGO_QUERY_CHANGED == 1 ]] || fail consulta
logo_prepare_backend > "$task_tmp/query" && fail 'no espera respuesta'
[[ ! -s "$task_tmp/query" ]] || fail 'consulta en cada tick'
INPUT_CELL_HEIGHT=10 INPUT_CELL_WIDTH=6
logo_prepare_backend || fail dimensiones
[[ $LOGO_SIXEL_SIDE == 60 ]] || fail 'no ajusta al espacio físico'
INPUT_CELL_HEIGHT=32 INPUT_CELL_WIDTH=16
logo_prepare_backend || fail dimensiones
[[ $LOGO_SIXEL_SIDE == 96 ]] || fail 'upscale sin límite'
INPUT_CELL_HEIGHT=0 INPUT_CELL_WIDTH=0 LOGO_CELL_QUERY_UNTIL=0
logo_prepare_backend || fail 'sin respuesta queda bloqueado'
[[ $LOGO_BACKEND == blocks ]] || fail 'sin respuesta no vuelve a bloques'

# Dibujar usa datos preparados; ocultar borra solo la reserva del logo.
UI_ACTIVE=1 UI_SUSPENDED=0 PREFERENCES_ACTIVE=0 UI_LOGO_LAYOUT=1 UI_DESKTOP_LEFT_WIDTH=60
LOGO_BACKEND=sixel LOGO_READY_URL=$PLAYER_URL
logo_read_sixel "$job/sixel" || fail lectura
frame=$(logo_draw)
[[ $frame == *$'\033P0;1;0q'* && $frame != *$'\033[16t'* ]] || fail 'dibujo sin SIXEL o consulta por frame'
logo_draw >/dev/null
[[ $LOGO_DRAWN == 1 && $LOGO_DRAW_COLUMN == 51 ]] || fail 'no guarda posición'
hidden=$(logo_hide)
[[ $hidden == *$'\033[4;51H\033[12X'* && $hidden != *'a=d'* ]] || fail 'borrado de otro backend'
[[ $(logo_print_slot 2) == '            ' ]] || fail 'iniciales debajo de la imagen'

# Si falta el SIXEL preparado no relanzar trabajos cada tick; respetar Unicode.
player_is_running() { return 0; }
LOGO_DRAWN=0 KEILA_CACHE_DIR=$task_tmp/cache KEILA_STATIONS_JSON=$task_tmp/no-catalog
PLAYER_PID=$$ PREF_LOGO=1 INPUT_CELL_HEIGHT=16 INPUT_CELL_WIDTH=8
mkdir -p "$KEILA_CACHE_DIR/logos"
for unicode in 0 1; do
    LOGO_SIXEL_FAILED_KEY='' UI_UNICODE=$unicode
    logo_prepare_backend || fail 'preparar fallback'
    logo_request_signature 0
    LOGO_REQUEST=$LOGO_SIGNATURE LOGO_CHECK_AT=0
    LOGO_JOB=$(mktemp -d "$KEILA_CACHE_DIR/logos/.job.XXXXXX") || fail temporal
    cp "$job/result" "$LOGO_JOB/result"
    LOGO_PID=2147483647
    logo_poll || fail 'no publica fallback'
    expected=initials
    ((unicode == 0)) || expected=blocks
    [[ $LOGO_BACKEND == "$expected" && -z $LOGO_PID ]] || fail 'fallback ignora Unicode'
    for ((i=0; i<20; i++)); do
        logo_poll && fail 'fallback relanza trabajo'
        [[ -z $LOGO_PID ]] || fail 'bucle de tareas SIXEL fallidas'
    done
done
printf 'ok   foot: SIXEL preparado, medidas, fallback, caché antigua y ocultación acotada\n'
