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

printf 'ok   búsqueda: índice rápido para catálogos grandes\n'
