#!/usr/bin/env bash

# Estado y filtrado de la búsqueda integrada de emisoras.
# El catálogo se carga una vez al abrir la vista y después se filtra en memoria.

SEARCH_ACTIVE=0
SEARCH_QUERY=''
SEARCH_SELECTED_INDEX=0
SEARCH_SCROLL_OFFSET=0

SEARCH_NAMES=()
SEARCH_AMBITS=()
SEARCH_COUNTRIES=()
SEARCH_FORMATS=()
SEARCH_URLS=()
SEARCH_MATCHES=()

search_reset() {
    SEARCH_QUERY=''
    SEARCH_SELECTED_INDEX=0
    SEARCH_SCROLL_OFFSET=0
    SEARCH_MATCHES=()
}

search_load_catalog() {
    SEARCH_NAMES=()
    SEARCH_AMBITS=()
    SEARCH_COUNTRIES=()
    SEARCH_FORMATS=()
    SEARCH_URLS=()

    local name ambit country format url
    while IFS=$'\t' read -r name ambit country format url; do
        [[ -n "$name" && -n "$url" ]] || continue
        SEARCH_NAMES+=("$name")
        SEARCH_AMBITS+=("$ambit")
        SEARCH_COUNTRIES+=("$country")
        SEARCH_FORMATS+=("$format")
        SEARCH_URLS+=("$url")
    done < <(stations_emit_tsv)

    ((${#SEARCH_NAMES[@]} > 0))
}

search_filter() {
    SEARCH_MATCHES=()

    local query="${SEARCH_QUERY,,}"
    local i haystack
    for ((i = 0; i < ${#SEARCH_NAMES[@]}; i++)); do
        haystack="${SEARCH_NAMES[$i]} ${SEARCH_AMBITS[$i]} ${SEARCH_COUNTRIES[$i]} ${SEARCH_FORMATS[$i]}"
        haystack="${haystack,,}"
        if [[ -z "$query" || "$haystack" == *"$query"* ]]; then
            SEARCH_MATCHES+=("$i")
        fi
    done

    if ((${#SEARCH_MATCHES[@]} == 0)); then
        SEARCH_SELECTED_INDEX=0
        SEARCH_SCROLL_OFFSET=0
    else
        ((SEARCH_SELECTED_INDEX >= ${#SEARCH_MATCHES[@]})) && SEARCH_SELECTED_INDEX=$((${#SEARCH_MATCHES[@]} - 1))
        ((SEARCH_SELECTED_INDEX < 0)) && SEARCH_SELECTED_INDEX=0
    fi
}

search_open() {
    search_reset
    search_load_catalog || return 1
    search_filter
    SEARCH_ACTIVE=1
}

search_close() {
    SEARCH_ACTIVE=0
    SEARCH_SCROLL_OFFSET=0
}

search_append() {
    local char="$1"
    ((${#SEARCH_QUERY} < 80)) || return 1
    [[ "$char" == [[:print:]] ]] || return 1

    SEARCH_QUERY+="$char"
    SEARCH_SELECTED_INDEX=0
    SEARCH_SCROLL_OFFSET=0
    search_filter
}

search_backspace() {
    [[ -n "$SEARCH_QUERY" ]] || return 1
    SEARCH_QUERY="${SEARCH_QUERY%?}"
    SEARCH_SELECTED_INDEX=0
    SEARCH_SCROLL_OFFSET=0
    search_filter
}

search_clear() {
    [[ -n "$SEARCH_QUERY" ]] || return 1
    SEARCH_QUERY=''
    SEARCH_SELECTED_INDEX=0
    SEARCH_SCROLL_OFFSET=0
    search_filter
}

search_move() {
    local delta="$1"
    local count=${#SEARCH_MATCHES[@]}
    ((count > 0)) || return 1

    SEARCH_SELECTED_INDEX=$(((SEARCH_SELECTED_INDEX + delta) % count))
    ((SEARCH_SELECTED_INDEX < 0)) && SEARCH_SELECTED_INDEX=$((SEARCH_SELECTED_INDEX + count))
}

search_select_first() {
    ((${#SEARCH_MATCHES[@]} > 0)) || return 1
    SEARCH_SELECTED_INDEX=0
}

search_select_last() {
    local count=${#SEARCH_MATCHES[@]}
    ((count > 0)) || return 1
    SEARCH_SELECTED_INDEX=$((count - 1))
}

search_sync_scroll() {
    local height="$1"
    local count=${#SEARCH_MATCHES[@]}

    ((height > 0)) || height=1
    if ((count == 0)); then
        SEARCH_SCROLL_OFFSET=0
        return 0
    fi

    if ((SEARCH_SELECTED_INDEX < SEARCH_SCROLL_OFFSET)); then
        SEARCH_SCROLL_OFFSET=$SEARCH_SELECTED_INDEX
    elif ((SEARCH_SELECTED_INDEX >= SEARCH_SCROLL_OFFSET + height)); then
        SEARCH_SCROLL_OFFSET=$((SEARCH_SELECTED_INDEX - height + 1))
    fi

    local max_scroll=$((count - height))
    ((max_scroll < 0)) && max_scroll=0
    ((SEARCH_SCROLL_OFFSET > max_scroll)) && SEARCH_SCROLL_OFFSET=$max_scroll
    ((SEARCH_SCROLL_OFFSET < 0)) && SEARCH_SCROLL_OFFSET=0
}

search_selected_load() {
    local count=${#SEARCH_MATCHES[@]}
    ((count > 0)) || return 1
    ((SEARCH_SELECTED_INDEX >= 0 && SEARCH_SELECTED_INDEX < count)) || return 1

    local source_index=${SEARCH_MATCHES[$SEARCH_SELECTED_INDEX]}
    SELECTED_NAME="${SEARCH_NAMES[$source_index]}"
    SELECTED_AMBIT="${SEARCH_AMBITS[$source_index]}"
    SELECTED_COUNTRY="${SEARCH_COUNTRIES[$source_index]}"
    SELECTED_FORMAT="${SEARCH_FORMATS[$source_index]}"
    SELECTED_URL="${SEARCH_URLS[$source_index]}"

    [[ -n "$SELECTED_NAME" && -n "$SELECTED_URL" ]]
}
