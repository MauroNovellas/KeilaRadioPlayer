#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'quality_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
keila_init_paths
origin=https://radio.invalid/master.m3u8
source "$ROOT_DIR/lib/quality-worker.sh"
mkdir -p "$task_tmp/job"
jq -n --arg url "$origin" '[{url:$url,name:"Radio",countrycode:"ES",homepage:"https://radio.invalid",codec:"AAC",bitrate:64,hls:1},
    {url:"https://radio.invalid/low",name:"Radio",countrycode:"ES",homepage:"https://radio.invalid",codec:"MP3",bitrate:96}]' > "$KEILA_STATIONS_JSON"
printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"\nlow.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2"\nhigh.m3u8\n' > "$task_tmp/master"
quality_fetch_playlist() { cp -- "$task_tmp/master" "$2/playlist"; }
quality_worker "$origin" "$origin" Radio "$KEILA_STATIONS_JSON" "$task_tmp/job" || fail worker
quality_read_result "$task_tmp/job/catalog.json" "$origin" || fail 'primera fase'
[[ ${#QUALITY_ROWS[@]} == 2 ]] || fail 'catálogo inicial'
quality_read_result "$task_tmp/job/result.json" "$origin" || fail 'segunda fase'
[[ ${#QUALITY_ROWS[@]} == 4 && ${QUALITY_ROWS[2]} == "$origin|64000|AAC|64000|hls" ]] || fail 'variantes HLS no conservan master'
cp -- "$task_tmp/job/result.json" "$task_tmp/good"
for expression in '.rows[0].url="https://otra.invalid"' '.rows[1].rate=-1' '.rows[1].rate=0.5' '.rows[1].url="https://radio.invalid/a\u0000b"' '.rows[1].kind="command"'; do
    jq "$expression" "$task_tmp/good" > "$task_tmp/bad"
    quality_read_result "$task_tmp/bad" "$origin" && fail 'snapshot inválido'
    [[ ${#QUALITY_ROWS[@]} == 4 ]] || fail 'snapshot parcial publicado'
done
ln -s "$task_tmp/good" "$task_tmp/link"
quality_read_result "$task_tmp/link" "$origin" && fail 'snapshot enlazado'
# Fallo de red no borra las versiones declaradas por el catálogo.
quality_fetch_playlist() { return 1; }
rm -- "$task_tmp/job/result.tmp" 2>/dev/null || true
quality_worker "$origin" "$origin" Radio "$KEILA_STATIONS_JSON" "$task_tmp/job" || fail 'fallback de red'
quality_read_result "$task_tmp/job/result.json" "$origin" || fail fallback
[[ ${#QUALITY_ROWS[@]} == 2 && $QUALITY_RESULT_NOTICE == *'No se pudo comprobar'* ]] || fail 'fallo de red quita catálogo'
printf 'roto' > "$KEILA_STATIONS_JSON"
quality_worker "$origin" "$origin" Radio "$KEILA_STATIONS_JSON" "$task_tmp/job" 2>/dev/null || fail 'fallback catálogo dañado'
quality_read_result "$task_tmp/job/result.json" "$origin" || fail 'original disponible'
[[ ${#QUALITY_ROWS[@]} == 1 ]] || fail 'catálogo dañado inventa versiones'
# Nunca presentar una sola variante como un selector de múltiples calidades.
printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"\nlow.m3u8\n' > "$task_tmp/master"
quality_fetch_playlist() { cp -- "$task_tmp/master" "$2/playlist"; }
quality_worker "$origin" "$origin" Radio "$KEILA_STATIONS_JSON" "$task_tmp/job" 2>/dev/null || fail 'variante única'
quality_read_result "$task_tmp/job/result.json" "$origin" || fail 'resultado único'
[[ ${#QUALITY_ROWS[@]} == 1 && $QUALITY_RESULT_NOTICE == *'solo anuncia una'* ]] || fail 'inventa calidades'
# Guardas de red con respuestas ficticias: ningún tráfico exterior.
source "$ROOT_DIR/lib/quality-worker.sh"
logo_resolve() { [[ $1 != privada.invalid ]] || { printf '127.0.0.1\n'; return; }; printf '93.184.216.34\n'; }
curl() {
    { printf '%q ' "$@"; printf '\n'; } >> "$task_tmp/requests"
    printf '302\nhttps://privada.invalid/playlist.m3u8'
}
quality_fetch_playlist "$origin" "$task_tmp/job" && fail 'redirección privada'
[[ $(wc -l < "$task_tmp/requests") == 1 ]] || fail 'descarga de red privada'
request=$(<"$task_tmp/requests")
[[ $request == *'--max-filesize 65536'* && $request == *'http\,https'* && $request == *'--resolve radio.invalid:443:93.184.216.34'* && $request == *'--noproxy \*'* ]] || fail 'descarga no acotada/DNS no fijado'
# Trabajo privado cancelable y publicación de catálogo antes de consultar HLS.
QUALITY_WORKER=$ROOT_DIR/tests/fixtures/quality-slow-worker.sh
quality_start_job "$origin" "$origin" Radio || fail iniciar
pid=$QUALITY_JOB_PID directory=$QUALITY_JOB_DIR
for ((i=0; i<150; i++)); do [[ ! -f $directory/child ]] || break; sleep .01; done
[[ -f $directory/child && $(stat -c %a "$directory") == 700 ]] || fail 'grupo privado no arranca'
quality_poll_job "$origin" || fail 'catálogo no disponible durante consulta'
[[ $QUALITY_JOB_PID == "$pid" && $QUALITY_RESULT_NOTICE == 'Catálogo disponible' ]] || fail 'publicación inicial mata trabajo'
quality_cleanup
[[ ! -e $directory ]] || fail 'temporal abandonado'
if kill -0 -- "-$pid" 2>/dev/null; then fail 'grupo de consulta huérfano'; fi
# Copias nuevas incluyen calidades; una copia antigua no las elimina.
quality_save_choice "$origin" https://radio.invalid/low 0 || fail guardar
backup_create "$task_tmp/good.tar.gz" >/dev/null || fail copia
quality_save_choice "$origin" "$origin" 0 || fail borrar
backup_restore "$task_tmp/good.tar.gz" >/dev/null || fail restaurar
quality_load; [[ ${QUALITY_TARGETS[$origin]} == https://radio.invalid/low ]] || fail 'copia pierde calidad'
mkdir -p "$task_tmp/old/keila-backup/config"
printf 'format=keila-backup-v1\n' > "$task_tmp/old/keila-backup/manifest"
printf 'Radio|https://radio.invalid/original\n' > "$task_tmp/old/keila-backup/config/favorites"
tar -C "$task_tmp/old" -czf "$task_tmp/old.tar.gz" keila-backup
backup_restore "$task_tmp/old.tar.gz" >/dev/null || fail 'copia antigua'
quality_load; [[ ${QUALITY_TARGETS[$origin]} == https://radio.invalid/low ]] || fail 'copia antigua borra calidad'
printf 'ok   calidades: worker en dos fases, red privada, cancelación, snapshots y copias compatibles\n'
