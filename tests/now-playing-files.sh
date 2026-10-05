#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
export KEILA_NOW_PLAYING=1
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'now_playing_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
source "$ROOT_DIR/lib/now-playing-worker.sh"
stream=https://radio.invalid/live now=1000
parse() {
    jq -e -L "$ROOT_DIR/lib" --arg stream "$stream" --arg endpoint https://radio.invalid/status-json.xsl \
        --arg kind "$1" --argjson now "$now" -f "$ROOT_DIR/lib/now-playing-response.jq" <<< "$2"
}
ice='{"icestats":{"source":[{"listenurl":"https://radio.invalid/other","title":"Otra radio"},{"listenurl":"https://RADIO.invalid:443/live","title":"Noticias","artist":"Radio"}]}}'
output=$(parse icecast "$ice") || fail Icecast
[[ $(jq -r .title <<< "$output") == 'Radio - Noticias' ]] || fail 'Icecast montaje incorrecto'
[[ $(jq -r .valid_until <<< "$output") == 1120 ]] || fail 'vigencia Icecast'
parse icecast '{"icestats":{"source":{"mount":"/live","title":"Noticias"}}}' >/dev/null || fail 'montaje sin listenurl'
parse icecast '{"icestats":{"source":{"listenurl":"https://otra.invalid/live","mount":"/live","title":"Noticias"}}}' >/dev/null 2>&1 && fail 'host distinto'
parse icecast '{"icestats":{"source":{"listenurl":"https://radio.invalid/live?x=1","title":"Noticias"}}}' >/dev/null 2>&1 && fail 'query descartada'
parse icecast "$(jq '.icestats.source += [.icestats.source[1]]' <<< "$ice")" >/dev/null 2>&1 && fail 'montaje ambiguo'
parse icecast '{"icestats":{"source":{"listenurl":"https://radio.invalid/live","server_name":"Radio","title":"Radio"}}}' >/dev/null 2>&1 && fail 'nombre de radio presentado como contenido'
parse icecast '{"icestats":{"source":{"listenurl":"https://radio.invalid/live"}}}' >/dev/null 2>&1 && fail 'fuente sin datos reemplaza metadatos del audio'

azura='{"station":{"name":"Radio","listen_url":"https://radio.invalid/other","mounts":[{"url":"https://radio.invalid/live"}]},"is_online":true,"now_playing":{"played_at":950,"duration":100,"song":{"title":"La entrevista","artist":"","text":"Texto antiguo"}},"live":{"is_live":true,"streamer_name":"Ana"}}'
output=$(parse azuracast "$azura") || fail AzuraCast
[[ $(jq -r '.title + "|" + .host + "|" + (.valid_until|tostring)' <<< "$output") == 'La entrevista|Ana|1050' ]] || fail 'contenido/locutor/vigencia'
for field in listen_url hls_url mounts remotes; do
    response=$(jq --arg field "$field" '.station={name:"Radio"} | if ($field=="mounts" or $field=="remotes") then .station[$field]=[{url:"https://radio.invalid/live"}] else .station[$field]="https://radio.invalid/live" end' <<< "$azura")
    parse azuracast "$response" >/dev/null || fail "identificación $field"
done
parse azuracast "[$azura,$azura]" >/dev/null 2>&1 && fail 'estación ambigua'
parse azuracast "$(jq '.station.mounts[0].url="https://otro.invalid/live"' <<< "$azura")" >/dev/null 2>&1 && fail 'emisora por nombre'
for expression in '.now_playing.played_at=800' '.now_playing.played_at=1100' '.now_playing.duration=-1' '.now_playing.duration="100"'; do
    parse azuracast "$(jq "$expression" <<< "$azura")" >/dev/null 2>&1 && fail 'API fuera de vigencia'
done
output=$(parse azuracast "$(jq '.now_playing.duration=0 | .live.is_live=false' <<< "$azura")") || fail 'programa largo'
[[ $(jq -r '.host + "|" + (.valid_until|tostring)' <<< "$output") == '|1120' ]] || fail 'DJ desconectado mostrado'
output=$(parse azuracast "$(jq '.is_online=false' <<< "$azura")") || fail offline
[[ -z $(jq -r .title <<< "$output") && -z $(jq -r .host <<< "$output") ]] || fail 'offline conserva programa'
output=$(parse azuracast "$(jq '.now_playing.song={text:"Boletín especial"}' <<< "$azura")") || fail 'texto alternativo'
[[ $(jq -r .title <<< "$output") == 'Boletín especial' ]] || fail 'text no leído'
parse azuracast "$(jq '.now_playing.song={} | .live.is_live=false' <<< "$azura")" >/dev/null 2>&1 && fail 'API sin datos oculta audio'
for expression in 'del(.is_online)' '.is_online="false"'; do
    parse azuracast "$(jq "$expression" <<< "$azura")" >/dev/null 2>&1 && fail 'estado ausente confundido con offline'
done

# Descubrimiento acotado y consultas posteriores al único endpoint identificado.
mkdir -p "$task_tmp/job"
NOW_PLAYING_WORKER_NOW=1000
now_playing_fetch() {
    printf '%s\n' "$1" >> "$task_tmp/endpoints"
    [[ $1 == */status-json.xsl ]] || return 1
    printf '%s\n' "$ice" > "$2/response"
}
now_playing_worker "$stream" "$task_tmp/job" '' '' || fail worker
[[ $(wc -l < "$task_tmp/endpoints") == 1 && -f $task_tmp/job/result.json && ! -e $task_tmp/job/result.tmp ]] || fail 'publicación/descubrimiento'
now_playing_worker "$stream" "$task_tmp/job" https://radio.invalid/status-json.xsl icecast || fail 'endpoint identificado'
now_playing_worker "$stream" "$task_tmp/job" https://otro.invalid/status-json.xsl icecast && fail 'endpoint fuera del stream'
now_playing_fetch() {
    printf '%s\n' "$1" >> "$task_tmp/endpoints"
    [[ $1 == */nowplaying_static/demo.json ]] || return 1
    jq '.station.listen_url="https://radio.invalid/listen/demo/radio.mp3"' <<< "$azura" > "$2/response"
}
now_playing_worker https://radio.invalid/listen/demo/radio.mp3 "$task_tmp/job" '' '' || fail 'AzuraCast estático'
[[ $(jq -r .endpoint "$task_tmp/job/result.json") == https://radio.invalid/api/nowplaying_static/demo.json ]] || fail 'endpoint eficiente'

# Restituir la descarga real con DNS/curl simulados: no sale ningún paquete.
source "$ROOT_DIR/lib/now-playing-worker.sh"
logo_resolve() { [[ $1 != private.invalid ]] || { printf '127.0.0.1\n'; return; }; printf '93.184.216.34\n'; }
mode=good
curl() {
    local output='' headers='' url=${*: -1}
    { printf '%q ' "$@"; printf '\n'; } >> "$task_tmp/requests"
    while (($#)); do
        case $1 in --output) output=$2; shift;; --dump-header) headers=$2; shift;; esac
        shift
    done
    if [[ $mode == redirect ]]; then printf '302\nhttps://private.invalid/json'; return; fi
    printf 'HTTP/1.1 200 OK\r\nAge: %s\r\n\r\n' "${task_http_age:-0}" > "$headers"
    if [[ $mode == large ]]; then head -c 524289 /dev/zero > "$output"; else printf '%s\n' "$ice" > "$output"; fi
    [[ $url == https://radio.invalid/* ]] || return 1
    printf '200\n'
}
now_playing_fetch https://radio.invalid/status-json.xsl "$task_tmp/job" || fail 'descarga segura'
request=$(<"$task_tmp/requests")
[[ $request == *'--max-filesize 524288'* && $request == *'--connect-timeout 2'* && $request == *'--max-time 4'* && \
   $request == *'--resolve radio.invalid:443:93.184.216.34'* && $request == *'--noproxy \*'* && \
   $request == *'--proto =http\,https'* && $request != *'--location'* ]] || fail 'guardas de red'
for task_http_age in 120 invalid 999999999999; do
    now_playing_fetch https://radio.invalid/status-json.xsl "$task_tmp/job" && fail 'respuesta envejecida'
done
task_http_age=0 mode=large
now_playing_fetch https://radio.invalid/status-json.xsl "$task_tmp/job" && fail 'respuesta grande'
mode=redirect
before=$(wc -l < "$task_tmp/requests")
now_playing_fetch https://radio.invalid/status-json.xsl "$task_tmp/job" && fail 'redirección privada'
[[ $(wc -l < "$task_tmp/requests") == $((before+1)) ]] || fail 'consulta red privada'
now_playing_fetch file:///etc/passwd "$task_tmp/job" && fail 'URL local'
now_playing_fetch https://user:password@radio.invalid/json "$task_tmp/job" && fail 'credenciales en URL'

# Grupo privado y cancelación al pausar, cambiar de stream y cerrar.
NOW_PLAYING_WORKER=$ROOT_DIR/tests/fixtures/now-playing-slow-worker.sh
NP_JOB_DIR=''
PLAYER_URL=$stream PLAYER_INPUT_URL=$stream PLAYER_STREAM_READY=1 PLAYER_PAUSED=0 PLAYER_BUFFERING=0
launch() {
    NP_URL=$PLAYER_URL NP_NEXT_AT=1
    now_playing_tick 1000 Noticias
    pid=$NP_JOB_PID directory=$NP_JOB_DIR
    [[ -n $pid ]] || fail 'trabajo asíncrono'
    for ((i=0; i<150; i++)); do [[ ! -f $directory/child ]] || break; sleep .01; done
    [[ -f $directory/child && $(stat -c %a "$directory") == 700 ]] || fail 'grupo privado'
    now_playing_tick 1001 Noticias
    [[ $NP_JOB_PID == "$pid" ]] || fail 'trabajos duplicados'
}
launch
PLAYER_PAUSED=1; now_playing_tick 1002 Noticias
[[ -z $NP_JOB_PID && ! -e $directory ]] || fail 'pausa no cancela consulta'
kill -0 -- "-$pid" 2>/dev/null && fail 'grupo huérfano en pausa'
PLAYER_PAUSED=0
launch
PLAYER_INPUT_URL=https://radio.invalid/other; now_playing_tick 1002 Otro
[[ -z $NP_JOB_PID && ! -e $directory && -z $NP_TITLE ]] || fail 'cambio deja consulta anterior'
kill -0 -- "-$pid" 2>/dev/null && fail 'grupo huérfano al cambiar'
PLAYER_INPUT_URL=$stream
launch
now_playing_reset
[[ -z $NP_JOB_PID && ! -e $directory ]] || fail 'cierre deja consulta'
kill -0 -- "-$pid" 2>/dev/null && fail 'grupo huérfano al cerrar'
printf 'ok   proveedores: coincidencia de stream, JSON público, límites, red segura y grupos cancelables\n'
