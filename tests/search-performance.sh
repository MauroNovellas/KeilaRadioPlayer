#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

# shellcheck source=lib/search.sh
source "$ROOT_DIR/lib/search.sh"

KEILA_SEARCH_MATCH_LIMIT=300
SEARCH_SOURCE_FILE="$TEST_TMP/radio.tsv"
for i in $(seq 1 50000); do
    text="radio $i madrid espana mp3 128k es"
    printf 'Radio %s\tMadrid\tEspana\tMP3 128k\thttps://example.invalid/%s\tES\t%s\n' "$i" "$i" "$text"
done > "$SEARCH_SOURCE_FILE"

SEARCH_QUERY='radio'
start=$(date +%s%N)
search_filter
end=$(date +%s%N)
elapsed_ms=$(((end - start) / 1000000))

[[ ${#SEARCH_MATCHES[@]} -eq 300 ]] || fail "límite visible: ${#SEARCH_MATCHES[@]}"
((elapsed_ms < 1500)) || fail "filtrado demasiado lento: ${elapsed_ms} ms"

SEARCH_QUERY='radio 49999'
start=$(date +%s%N)
search_filter
end=$(date +%s%N)
elapsed_ms=$(((end - start) / 1000000))

[[ ${#SEARCH_MATCHES[@]} -eq 1 ]] || fail "consulta concreta: ${#SEARCH_MATCHES[@]}"
((elapsed_ms < 1500)) || fail "consulta concreta lenta: ${elapsed_ms} ms"

awk -F '\t' 'BEGIN { OFS="\t" } { print $0, "Madrid", "rock,jazz" }' "$SEARCH_SOURCE_FILE" > "$TEST_TMP/facets.tsv"
SEARCH_SOURCE_FILE="$TEST_TMP/facets.tsv"
SEARCH_COUNTRY_FILTER_ENABLED=1 KEILA_CATALOG_COUNTRY_FILTER=ES
SEARCH_REGION_FILTER=Madrid SEARCH_TAG_FILTER=rock
start=$(date +%s%N)
search_filter
end=$(date +%s%N)
elapsed_ms=$(((end - start) / 1000000))
[[ ${#SEARCH_MATCHES[@]} -eq 1 ]] || fail 'filtros combinados cambian resultado'
((elapsed_ms < 1500)) || fail "filtros combinados lentos: ${elapsed_ms} ms"
printf 'ok   50.000 emisoras, tres filtros y consulta concreta: %s ms\n' "$elapsed_ms"

printf 'ok   búsqueda: índice rápido para catálogos grandes\n'

# Las versiones se consultan solo al abrir Opciones, pero tampoco deben
# normalizar cada campo de 50.000 emisoras antes de identificar la actual.
jq -n '[range(0;50000) as $i | {name:"Radio \($i)",url:"https://radio.invalid/\($i)",
    countrycode:(if ($i%5)==0 then "ES" else "FR" end),state:"Madrid",
    homepage:"https://radio.invalid",codec:"MP3",bitrate:128,hls:0}] +
    [{name:"Radio 0",url:"https://radio.invalid/low",countrycode:"ES",state:"Madrid",
      homepage:"https://radio.invalid",codec:"AAC",bitrate:64,hls:0}]' > "$TEST_TMP/qualities.json" || fail 'catálogo de versiones'
start=$(date +%s%N)
timeout --kill-after=1s 8s jq --arg origin https://radio.invalid/0 --arg input https://radio.invalid/0 \
    -f "$ROOT_DIR/lib/quality-candidates.jq" "$TEST_TMP/qualities.json" > "$TEST_TMP/qualities.result" || fail 'consulta de versiones no termina'
end=$(date +%s%N)
elapsed_ms=$(((end - start) / 1000000))
jq -e '.rows|length==2 and .[1].url=="https://radio.invalid/low"' "$TEST_TMP/qualities.result" >/dev/null || fail 'versiones mezclan emisoras'
((elapsed_ms < 5000)) || fail "consulta de versiones demasiado lenta: $elapsed_ms ms"
printf 'ok   versiones: 50.000 emisoras sin normalización global: %s ms\n' "$elapsed_ms"
