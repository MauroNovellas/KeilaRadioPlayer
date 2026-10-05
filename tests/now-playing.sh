#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Metadatos sin radio, red ni espera real; reloj controlado.
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
export KEILA_NOW_PLAYING=1
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'now_playing_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
metadata() { jq -r -L "$ROOT_DIR/lib" 'include "now-playing-metadata"; np_content' <<< "$1"; }
[[ $(metadata '{"TITLE":"Boletín","ARTIST":"RNE"}') == 'RNE - Boletín' ]] || fail 'Ogg artist/title'
[[ $(metadata '{"programme-title":"Entrevista","title":"Archivo","artist":"Radio"}') == Entrevista ]] || fail 'programa explícito'
[[ $(metadata '{"ICY-TITLE":"Noticias","title":"Archivo"}') == Noticias ]] || fail 'ICY prioritario'
[[ $(metadata '{"title":"Newsroom","artist":"News"}') == 'News - Newsroom' ]] || fail 'prefijo de artista ambiguo'
[[ $(metadata '{"title":"Artista - Tema","artist":"Artista"}') == 'Artista - Tema' ]] || fail 'artista duplicado'
[[ -z $(metadata '{"title":{"cmd":"evil"},"artist":42,"description":"Descripción estática"}') ]] || fail 'datos no textuales o descripción como programa'
text=$(metadata '{"title":"Noticias\u001b\nAhora\u009b"}')
[[ $text == 'Noticias Ahora' && $text != *$'\e'* ]] || fail 'escapes de terminal'
[[ $(jq -nr -L "$ROOT_DIR/lib" 'include "now-playing-metadata"; {title:("a"*1000)} | np_content | length') == 240 ]] || fail 'texto ilimitado'

# Usar la lógica de reproducción real, con snapshots deterministas.
player_is_running() { return 0; }
player_title_probe_should_run() { return 1; }
PLAYER_NAME=Radio PLAYER_URL=https://radio.invalid/live PLAYER_INPUT_URL=$PLAYER_URL
PLAYER_SOCKET="$task_tmp/mpv.sock" PLAYER_STREAM_TITLE_MAX_AGE=300 PLAYER_INFO_INTERVAL=1
embedded='El matinal'
player_query_snapshot() { jq -nc --arg title "$embedded" '{"1":{title:$title},"6":"https://radio.invalid/live","10":false,"11":1}'; }
refresh() { KEILA_PLAYER_NOW=$1; PLAYER_INFO_LAST_REFRESH=0; player_refresh_info || true; }
NP_URL=$PLAYER_URL NP_NEXT_AT=99999
refresh 1000
[[ $PLAYER_STREAM_TITLE == 'El matinal' ]] || fail 'fallback URL oculta título válido'
snapshot_function=$(declare -f player_query_snapshot)
player_query_snapshot() { printf '%s\n' '{"1":{"title":"No publicar"},"4":"respuesta parcial"}'; }
KEILA_PLAYER_NOW=1001 PLAYER_INFO_LAST_REFRESH=0
player_refresh_info > "$task_tmp/parse-output" 2>&1 && fail 'snapshot parcial aceptado'
[[ ! -s $task_tmp/parse-output && $PLAYER_STREAM_TITLE == 'El matinal' && $PLAYER_INFO_PARSE_ERROR == 1 ]] || fail 'error del parser desplaza/borra la TUI'
eval "$snapshot_function"
refresh 1002
[[ $PLAYER_INFO_PARSE_ERROR == 0 ]] || fail 'parser no recupera estado sano'
refresh 1300
[[ -z $PLAYER_STREAM_TITLE ]] || fail 'texto sin verificar no caduca'
NP_CONFIRMED=1 NP_BASELINE=$embedded NP_TITLE=$embedded NP_CHECKED_AT=1301 NP_VALID_UNTIL=1421
refresh 1301
[[ $PLAYER_STREAM_TITLE == 'El matinal' ]] || fail 'confirmación renueva programa sin cambiar nombre'
NP_TITLE='Boletín especial' NP_CHECKED_AT=1302 NP_VALID_UNTIL=1422
refresh 1302
[[ $PLAYER_STREAM_TITLE == 'Boletín especial' && $PLAYER_STREAM_TITLE_UPDATED_AT == 1302 ]] || fail 'contenido nuevo de API no sustituye snapshot congelado'
NP_TITLE='El matinal'
NP_CHECKED_AT=10000 NP_VALID_UNTIL=10120
refresh 10000
[[ $PLAYER_STREAM_TITLE == 'El matinal' ]] || fail 'programa largo verificado oculto'
refresh 10120
[[ -z $PLAYER_STREAM_TITLE ]] || fail 'dato público sin vigencia visible'
refresh 10121
[[ -z $PLAYER_STREAM_TITLE ]] || fail 'reaparece título inicial congelado'
embedded='Entrevista nueva'
refresh 10122
[[ $PLAYER_STREAM_TITLE == 'Entrevista nueva' && $NP_CONFIRMED == 0 ]] || fail 'metadatos de audio más recientes'

# Respuesta recibida después de que el audio haya anunciado otro contenido.
completed_result() {
    NP_JOB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keila-nowplaying.XXXXXX") || fail temporal
    (exit 0) & NP_JOB_PID=$!; wait "$NP_JOB_PID" || true
    jq -n --arg stream "$PLAYER_URL" --arg title "$1" --argjson now "$2" \
        '{version:1,stream:$stream,endpoint:"https://radio.invalid/status-json.xsl",kind:"icecast",title:$title,host:"",checked_at:$now,valid_until:($now+120)}' > "$NP_JOB_DIR/result.json"
}
completed_result 'El matinal' 10123
NP_JOB_BASELINE='El matinal'
now_playing_poll 10123 || fail poll
now_playing_choose 10123 'Entrevista nueva'
[[ $NP_DISPLAY_TITLE == 'Entrevista nueva' && $NP_CONFIRMED == 0 && -z $NP_JOB_DIR ]] || fail 'respuesta tardía reemplaza audio'
NP_CONFIRMED=1 NP_BASELINE='Dato viejo' NP_TITLE=$embedded NP_CHECKED_AT=1000 NP_VALID_UNTIL=1120
PLAYER_STREAM_TITLE_EMBEDDED_LAST_SEEN='Dato viejo' PLAYER_STREAM_TITLE_UPDATED_AT=1000 PLAYER_STREAM_TITLE_CONFIRMED_AT=1000
refresh 10124
[[ $PLAYER_STREAM_TITLE == "$embedded" && $PLAYER_STREAM_TITLE_UPDATED_AT == 10124 ]] || fail 'cambio real de mpv idéntico a último título API no renueva frescura'
completed_result '' 10124; NP_JOB_BASELINE=$embedded
now_playing_poll 10124 || fail 'respuesta vacía'
now_playing_choose 10124 "$embedded"
[[ -z $NP_DISPLAY_TITLE && $NP_CONFIRMED == 1 ]] || fail 'estado sin contenido revive título viejo'

# Validación del canal de publicación: nunca aceptar snapshots parciales/ajenos.
for expression in '.stream="https://otra.invalid/live"' '.checked_at=1' '.checked_at=20000' \
    '.valid_until+=121' '.checked_at+=0.5' '.title="\u001b[2J"' '.host="a\nb"' \
    '.endpoint="https://otra.invalid/status-json.xsl"' '.kind="shell"'; do
    completed_result Noticias 10125
    jq "$expression" "$NP_JOB_DIR/result.json" > "$NP_JOB_DIR/bad"
    mv -- "$NP_JOB_DIR/bad" "$NP_JOB_DIR/result.json"
    previous=$NP_CHECKED_AT
    now_playing_poll 10125 || fail 'no recoge trabajo inválido'
    [[ $NP_CHECKED_AT == "$previous" && $NP_NEXT_AT -gt 10125 ]] || fail 'acepta resultado inválido'
done
completed_result Noticias 10125
cp -- "$NP_JOB_DIR/result.json" "$NP_JOB_DIR/second"
jq -sc '.[]' "$NP_JOB_DIR/second" "$NP_JOB_DIR/second" > "$NP_JOB_DIR/result.json"
previous=$NP_CHECKED_AT; now_playing_poll 10125 || true
[[ $NP_CHECKED_AT == "$previous" ]] || fail 'múltiples documentos JSON'
completed_result Noticias 10125
mv -- "$NP_JOB_DIR/result.json" "$task_tmp/result"
ln -s "$task_tmp/result" "$NP_JOB_DIR/result.json"
now_playing_poll 10125 || true
[[ $NP_CHECKED_AT == "$previous" ]] || fail 'snapshot enlazado'
completed_result Noticias 10125
head -c 8193 /dev/zero > "$NP_JOB_DIR/result.json"
now_playing_poll 10125 || true
[[ $NP_CHECKED_AT == "$previous" ]] || fail 'snapshot ilimitado'
NP_FAILURES=0 NP_ENDPOINT=https://radio.invalid/status-json.xsl NP_KIND=icecast
for delay in 60 120 240; do
    completed_result Noticias 10125
    printf 'roto' > "$NP_JOB_DIR/result.json"
    now_playing_poll 10125 || fail 'fallo no recogido'
    [[ $NP_NEXT_AT == $((10125+delay)) ]] || fail 'reintento no espaciado'
done
[[ -z $NP_ENDPOINT && -z $NP_KIND ]] || fail 'no redescubre endpoint tras tres fallos'

# Caché solo de direcciones/reintentos: acotada y sin contenidos de otras radios.
NP_CACHE_KEYS=() NP_CACHE_NEXT=() NP_CACHE_ENDPOINTS=() NP_CACHE_KINDS=() NP_CACHE_FAILURES=()
for ((i=0; i<70; i++)); do NP_URL=https://radio.invalid/$i; NP_NEXT_AT=99999; now_playing_cache; done
[[ ${#NP_CACHE_KEYS[@]} == 64 && ! -v 'NP_CACHE_NEXT[https://radio.invalid/0]' ]] || fail 'caché ilimitada'
now_playing_reset
[[ -z $NP_TITLE && $NP_CONFIRMED == 0 && ${#NP_CACHE_KEYS[@]} == 64 ]] || fail 'cambio conserva contenido previo'

# El tick no debe abrir trabajos si no hay audio, en pausa, buffering o archivo.
NP_URL=$PLAYER_URL NP_NEXT_AT=1 PLAYER_STREAM_READY=0 PLAYER_PAUSED=0 PLAYER_BUFFERING=0
now_playing_tick 20000 "$embedded"
[[ -z $NP_JOB_PID ]] || fail 'consulta antes de reproducir'
PLAYER_STREAM_READY=1 PLAYER_PAUSED=1
now_playing_tick 20000 "$embedded"
[[ -z $NP_JOB_PID ]] || fail 'consulta pausada'
PLAYER_PAUSED=0
now_playing_tick 20000 "$embedded" 1 1
[[ -z $NP_JOB_PID ]] || fail 'buffering actual ignorado'
PLAYER_INPUT_URL=$task_tmp/audio.mp3
now_playing_tick 20000 "$embedded"
[[ -z $NP_JOB_PID && -z $NP_URL ]] || fail 'consulta de archivo local'
PLAYER_INPUT_URL=$PLAYER_URL NP_ENABLED=0
now_playing_tick 20000 "$embedded"
[[ -z $NP_JOB_PID ]] || fail 'desactivación ignorada'
printf 'ok   metadatos: etiquetas, programas largos, vigencia, carreras, snapshots y caché acotada\n'
