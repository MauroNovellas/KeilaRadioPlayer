#!/usr/bin/env bash

# Estado y filtrado de la búsqueda integrada de emisoras.
# El catálogo se carga una vez al abrir la vista y después se filtra en memoria.

SEARCH_ACTIVE=0
SEARCH_QUERY=''
SEARCH_SELECTED_INDEX=0
SEARCH_SCROLL_OFFSET=0
SEARCH_FILTER_DIRTY=0

SEARCH_NAMES=()
SEARCH_AMBITS=()
SEARCH_COUNTRIES=()
SEARCH_FORMATS=()
SEARCH_URLS=()
SEARCH_INDEX_TEXTS=()
SEARCH_MATCHES=()

search_reset() {
    SEARCH_QUERY=''
    SEARCH_SELECTED_INDEX=0
    SEARCH_SCROLL_OFFSET=0
    SEARCH_FILTER_DIRTY=0
    SEARCH_MATCHES=()
}

search_load_catalog() {
    SEARCH_NAMES=()
    SEARCH_AMBITS=()
    SEARCH_COUNTRIES=()
    SEARCH_FORMATS=()
    SEARCH_URLS=()
    SEARCH_INDEX_TEXTS=()

    local name ambit country format url
    while IFS=$'\t' read -r name ambit country format url; do
        [[ -n "$name" && -n "$url" ]] || continue
        SEARCH_NAMES+=("$name")
        SEARCH_AMBITS+=("$ambit")
        SEARCH_COUNTRIES+=("$country")
        SEARCH_FORMATS+=("$format")
        SEARCH_URLS+=("$url")
        # Precalculamos el texto normalizado una sola vez al abrir la búsqueda.
        # Así cada filtro no vuelve a concatenar y convertir todo el catálogo.
        SEARCH_INDEX_TEXTS+=("${name,,} ${ambit,,} ${country,,} ${format,,}")
    done < <(stations_emit_tsv)

    ((${#SEARCH_NAMES[@]} > 0))
}

search_filter() {
    SEARCH_MATCHES=()

    local query="${SEARCH_QUERY,,}"
    local i label
    for ((i = 0; i < ${#SEARCH_INDEX_TEXTS[@]}; i++)); do
        label=''
        if declare -p FAVORITE_LABELS >/dev/null 2>&1; then
            label="${FAVORITE_LABELS[${SEARCH_URLS[$i]}]:-}"
        fi
        if [[ -z "$query" || "${SEARCH_INDEX_TEXTS[$i]} ${label,,}" == *"$query"* ]]; then
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

    SEARCH_FILTER_DIRTY=0
}

search_apply_pending_filter() {
    ((SEARCH_FILTER_DIRTY)) || return 1
    search_filter
    return 0
}

search_open() {
    # Cerrar la búsqueda deja la consulta visible en el panel desktop con
    # "B editar". Al volver a entrar conservamos esa consulta de verdad, pero
    # reiniciamos selección/scroll y recargamos el catálogo por si cambió.
    local previous_query="$SEARCH_QUERY"
    search_reset
    SEARCH_QUERY="$previous_query"
    search_load_catalog || return 1
    search_filter
    SEARCH_ACTIVE=1
}

search_close() {
    SEARCH_ACTIVE=0
    SEARCH_SCROLL_OFFSET=0
    SEARCH_FILTER_DIRTY=0
}

search_append() {
    local char="$1"
    ((${#SEARCH_QUERY} < 80)) || return 1
    [[ "$char" == [[:print:]] ]] || return 1

    SEARCH_QUERY+="$char"
    SEARCH_SELECTED_INDEX=0
    SEARCH_SCROLL_OFFSET=0
    SEARCH_FILTER_DIRTY=1
}

search_backspace() {
    [[ -n "$SEARCH_QUERY" ]] || return 1
    SEARCH_QUERY="${SEARCH_QUERY%?}"
    SEARCH_SELECTED_INDEX=0
    SEARCH_SCROLL_OFFSET=0
    SEARCH_FILTER_DIRTY=1
}

search_clear() {
    [[ -n "$SEARCH_QUERY" ]] || return 1
    SEARCH_QUERY=''
    SEARCH_SELECTED_INDEX=0
    SEARCH_SCROLL_OFFSET=0
    SEARCH_FILTER_DIRTY=1
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
