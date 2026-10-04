#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Snapshot binario de datos; no guardar declaraciones Bash ni escapes de UI.
set -uo pipefail
(($# == 8)) || exit 2
source "$(dirname "${BASH_SOURCE[0]}")/search.sh"
SEARCH_SOURCE_FILE=$1 SEARCH_QUERY=$2 SEARCH_MATCH_LIMIT=$3
SEARCH_COUNTRY_FILTER_ENABLED=$4 KEILA_CATALOG_COUNTRY_FILTER=$5
SEARCH_REGION_FILTER=$6 SEARCH_TAG_FILTER=$7
job=$8
[[ -f $SEARCH_SOURCE_FILE && ! -L $SEARCH_SOURCE_FILE && -d $job && ! -L $job && -f $job/labels && ! -L $job/labels ]] || exit 1
umask 077
ulimit -f 32768 2>/dev/null || true
declare -A FAVORITE_LABELS=()
while IFS= read -r -d '' url && IFS= read -r -d '' label; do
    [[ -z $url ]] || FAVORITE_LABELS["$url"]=$label
done < "$job/labels"
search_filter || exit 1
count=${#SEARCH_NAMES[@]}
{
    printf 'keila-search-v1\0%s\0' "$count"
    if ((count > 0)); then
        printf '%s\0' "${SEARCH_NAMES[@]}"
        printf '%s\0' "${SEARCH_AMBITS[@]}"
        printf '%s\0' "${SEARCH_COUNTRIES[@]}"
        printf '%s\0' "${SEARCH_FORMATS[@]}"
        printf '%s\0' "${SEARCH_URLS[@]}"
        printf '%s\0' "${SEARCH_COUNTRYCODES[@]}"
        printf '%s\0' "${SEARCH_INDEX_TEXTS[@]}"
        printf '%s\0' "${SEARCH_REGIONS[@]}"
        printf '%s\0' "${SEARCH_TAGS[@]}"
    fi
    printf 'keila-search-end\0'
} > "$job/result.tmp" || exit 1
mv -- "$job/result.tmp" "$job/result"
