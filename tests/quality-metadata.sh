#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
origin=https://radio.invalid/original
jq -n '[{name:"Radio",countrycode:"ES",state:"Madrid",homepage:"https://www.radio.invalid/",url:"https://radio.invalid/original",codec:"MP3",bitrate:96,hls:0},
    {name:" RADIO ",countrycode:"ES",state:"madrid",homepage:"http://radio.invalid",url:"https://radio.invalid/low",codec:"AAC",bitrate:64},
    {name:"Radio",countrycode:"FR",state:"Madrid",homepage:"https://radio.invalid",url:"https://radio.invalid/fr",codec:"MP3",bitrate:320},
    {name:"Radio",countrycode:"ES",state:"Barcelona",homepage:"https://radio.invalid",url:"https://radio.invalid/barcelona"},
    {name:"Radio",countrycode:"ES",state:"Madrid",homepage:"https://radio.invalid/otra",url:"https://radio.invalid/otra"},
    {name:"Radio",countrycode:"ES",state:"Madrid",homepage:"https://diferente.invalid",url:"https://radio.invalid/homonima"}]' > "$task_tmp/catalog"
candidates() { jq --arg origin "$origin" --arg input "$origin" -f "$ROOT_DIR/lib/quality-candidates.jq" "$1"; }
candidates "$task_tmp/catalog" > "$task_tmp/result" || fail catálogo
jq -e '.rows|length==2 and .[0].kind=="original" and .[1].url=="https://radio.invalid/low" and .[1].bits==64000' "$task_tmp/result" >/dev/null || fail 'agrupación confunde emisoras'
jq '.[0:2]+[.[1]]' "$task_tmp/catalog" > "$task_tmp/duplicate"
[[ $(candidates "$task_tmp/duplicate" | jq '.rows|length') == 2 ]] || fail duplicados
jq '.+[.[0] | .countrycode="FR"]' "$task_tmp/catalog" > "$task_tmp/ambiguous"
[[ $(candidates "$task_tmp/ambiguous" | jq '.rows|length') == 1 ]] || fail 'URL con identidad contradictoria'
for mutation in '.[]|.homepage=""' '.[]|.homepage="no es una web"' '.[]|.countrycode="ZZZ"'; do
    jq "[$mutation]" "$task_tmp/catalog" > "$task_tmp/unidentified"
    [[ $(candidates "$task_tmp/unidentified" | jq '.rows|length') == 1 ]] || fail 'agrupación sin identidad'
done
jq '.[1].bitrate="desconocido"' "$task_tmp/catalog" > "$task_tmp/unknown"
[[ $(candidates "$task_tmp/unknown" | jq '.rows[1].bits') == 0 ]] || fail 'bitrate desconocido'
jq '.+[.[1] | .url="file:///tmp/secret"]' "$task_tmp/catalog" > "$task_tmp/unsafe"
[[ $(candidates "$task_tmp/unsafe" | jq '.rows|length') == 2 ]] || fail 'URL inválida contamina alternativas'
jq '.[0].url_resolved="" | .[1].url_resolved=""' "$task_tmp/catalog" > "$task_tmp/empty"
[[ $(candidates "$task_tmp/empty" | jq '.rows|length') == 2 ]] || fail 'resolved vacío oculta emisora'
jq '.[0:2] | .[0].homepage="https://radio.invalid/Radio" | .[1].homepage="https://radio.invalid/radio"' "$task_tmp/catalog" > "$task_tmp/paths"
[[ $(candidates "$task_tmp/paths" | jq '.rows|length') == 1 ]] || fail 'web de ruta distinta'
origin=https://ausente.invalid
[[ $(candidates "$task_tmp/catalog" | jq '.rows|length') == 1 ]] || fail 'emisora manual inventa alternativas'
parse() { LC_ALL=C awk -f "$ROOT_DIR/lib/quality-hls.awk" "$1"; }
printf '#EXTM3U\r\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"\r\nlow.m3u8\r\n#EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.5",NAME="Audio, alta"\r\nhttps://radio.invalid/high.m3u8\r\n' > "$task_tmp/master"
[[ $(parse "$task_tmp/master") == $'64000\tAAC\n128000\tHE-AAC' ]] || fail 'variantes y atributos con comas'
printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000,CODECS="avc1.42e01e,mp4a.40.2",RESOLUTION=640x360\nvideo.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=64000\nunknown.m3u8\n' > "$task_tmp/video"
[[ -z $(parse "$task_tmp/video") ]] || fail 'ofrece vídeo/formato desconocido'
printf '#EXTM3U\n#EXTINF:5,\naudio.ts\n#EXT-X-ENDLIST\n' > "$task_tmp/media"
[[ -z $(parse "$task_tmp/media") ]] || fail 'confunde segmentos con variantes'
printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2",AUDIO="idiomas"\nlow.m3u8\n' > "$task_tmp/groups"
[[ -z $(parse "$task_tmp/groups") ]] || fail 'grupo externo ambiguo'
for uri in 'file:///tmp/secret' 'data:audio/aac,x' 'https://radio.invalid/a b' 'child|bad'; do
    printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"\n%s\n' "$uri" > "$task_tmp/bad"
    parse "$task_tmp/bad" >/dev/null && fail "acepta $uri"
done
for line in '#EXT-X-STREAM-INF:BANDWIDTH=64000,BANDWIDTH=128000,CODECS="mp4a.40.2"' '#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2'; do
    printf '#EXTM3U\n%s\naudio.m3u8\n' "$line" > "$task_tmp/bad"
    parse "$task_tmp/bad" >/dev/null && fail 'atributos corruptos'
done
printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"\n' > "$task_tmp/bad"
parse "$task_tmp/bad" >/dev/null && fail 'lista truncada'
printf '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"\na.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="opus"\nb.m3u8\n' > "$task_tmp/bad"
parse "$task_tmp/bad" >/dev/null && fail 'límite no distingue variantes'
printf '#EXTM3U\n\033[2J\n' > "$task_tmp/bad"
parse "$task_tmp/bad" >/dev/null && fail 'control de terminal'
printf 'ok   calidades: identidad conservadora, catálogo ambiguo y parser HLS de audio acotado\n'
