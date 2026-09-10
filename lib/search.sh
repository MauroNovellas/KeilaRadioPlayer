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
SEARCH_COUNTRYCODES=()
SEARCH_INDEX_TEXTS=()
SEARCH_INDEX_ROWS=''
SEARCH_MATCHES=()
SEARCH_COUNTRY_FILTER_ENABLED=0
SEARCH_MATCH_LIMIT="${KEILA_SEARCH_MATCH_LIMIT:-${SEARCH_MATCH_LIMIT:-300}}"
KEILA_CATALOG_COUNTRY_FILTER="${KEILA_CATALOG_COUNTRY_FILTER:-ES}"
SEARCH_SOURCE_FILE=''
SEARCH_SOURCE_ROWS=''
declare -A SEARCH_URL_INDEX=()

search_clear_results() {
    SEARCH_NAMES=()
    SEARCH_AMBITS=()
    SEARCH_COUNTRIES=()
    SEARCH_FORMATS=()
    SEARCH_URLS=()
    SEARCH_COUNTRYCODES=()
    SEARCH_INDEX_TEXTS=()
    SEARCH_INDEX_ROWS=''
    SEARCH_MATCHES=()
    SEARCH_URL_INDEX=()
}

search_reset() {
    SEARCH_QUERY=''
    SEARCH_SELECTED_INDEX=0
    SEARCH_SCROLL_OFFSET=0
    SEARCH_FILTER_DIRTY=0
    search_clear_results
}

search_load_catalog() {
    search_clear_results
    SEARCH_SOURCE_FILE=''
    SEARCH_SOURCE_ROWS=''

    if declare -F stations_tsv_valid >/dev/null 2>&1 && stations_tsv_valid; then
        SEARCH_SOURCE_FILE="$KEILA_STATIONS_TSV"
        return 0
    fi
    if declare -F stations_rebuild_tsv >/dev/null 2>&1 && stations_rebuild_tsv >/dev/null 2>&1; then
        SEARCH_SOURCE_FILE="$KEILA_STATIONS_TSV"
        return 0
    fi

    SEARCH_SOURCE_ROWS=$(stations_emit_tsv) || return 1
    [[ -n "$SEARCH_SOURCE_ROWS" ]]
}

search_source_rows_from_current() {
    local i name ambit country format url countrycode index_text
    for ((i = 0; i < ${#SEARCH_URLS[@]}; i++)); do
        name="${SEARCH_NAMES[$i]:-}"
        ambit="${SEARCH_AMBITS[$i]:-}"
        country="${SEARCH_COUNTRIES[$i]:-}"
        format="${SEARCH_FORMATS[$i]:-}"
        url="${SEARCH_URLS[$i]:-}"
        countrycode="${SEARCH_COUNTRYCODES[$i]:-}"
        [[ -n "$url" ]] || continue
        index_text="${SEARCH_INDEX_TEXTS[$i]:-${name,,} ${ambit,,} ${country,,} ${format,,} ${countrycode,,}}"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$name" "$ambit" "$country" "$format" "$url" "$countrycode" "$index_text"
    done
}

search_filter_station_rows() {
    local source_rows="$1"
    local query="${SEARCH_QUERY,,}"

    if [[ -n "$SEARCH_SOURCE_FILE" ]]; then
        awk -F '\t' \
            -v query="$query" \
            -v country="$KEILA_CATALOG_COUNTRY_FILTER" \
            -v country_filter="$SEARCH_COUNTRY_FILTER_ENABLED" \
            -v limit="$SEARCH_MATCH_LIMIT" '
            BEGIN { if (limit < 100) limit = 300 }
            NF < 5 || $5 == "" { next }
            country_filter && toupper($6) != country { next }
            {
                text = tolower($1 " " $2 " " $3 " " $4 " " $6)
                if (query == "" || index(text, query)) {
                    print
                    if (++matches >= limit) exit
                }
            }
        ' "$SEARCH_SOURCE_FILE"
    else
        awk -F '\t' \
            -v query="$query" \
            -v country="$KEILA_CATALOG_COUNTRY_FILTER" \
            -v country_filter="$SEARCH_COUNTRY_FILTER_ENABLED" \
            -v limit="$SEARCH_MATCH_LIMIT" '
            BEGIN { if (limit < 100) limit = 300 }
            NF < 5 || $5 == "" { next }
            country_filter && toupper($6) != country { next }
            {
                text = ($7 != "" ? $7 : tolower($1 " " $2 " " $3 " " $4 " " $6))
                if (query == "" || index(text, query)) {
                    print
                    if (++matches >= limit) exit
                }
            }
        ' <<< "$source_rows"
    fi
}

search_station_line_for_url() {
    local url="$1" source_rows="$2"

    if [[ -n "$SEARCH_SOURCE_FILE" ]]; then
        awk -F '\t' -v target="$url" 'NF >= 5 && $5 == target { print; exit }' "$SEARCH_SOURCE_FILE"
    else
        awk -F '\t' -v target="$url" 'NF >= 5 && $5 == target { print; exit }' <<< "$source_rows"
    fi
}

search_add_result_line() {
    local line="$1"
    local name ambit country format url countrycode index index_text record

    record="${line//$'\t'/$'\x1f'}"
    IFS=$'\x1f' read -r name ambit country format url countrycode index_text <<< "$record"
    [[ -n "$url" ]] || return 1
    [[ -n "$name" ]] || name='Sin nombre'

    index=${#SEARCH_NAMES[@]}
    SEARCH_NAMES+=("$name")
    SEARCH_AMBITS+=("$ambit")
    SEARCH_COUNTRIES+=("$country")
    SEARCH_FORMATS+=("$format")
    SEARCH_URLS+=("$url")
    SEARCH_COUNTRYCODES+=("$countrycode")
    SEARCH_INDEX_TEXTS+=("${index_text:-${name,,} ${ambit,,} ${country,,} ${format,,} ${countrycode,,}}")
    SEARCH_MATCHES+=("$index")
    SEARCH_URL_INDEX["$url"]="$index"
}

search_filter() {
    local query="${SEARCH_QUERY,,}"
    local source_rows='' line label url has_labels=0
    SEARCH_MATCH_LIMIT="${KEILA_SEARCH_MATCH_LIMIT:-$SEARCH_MATCH_LIMIT}"
    [[ "$SEARCH_MATCH_LIMIT" =~ ^[0-9]+$ ]] || SEARCH_MATCH_LIMIT=300
    ((SEARCH_MATCH_LIMIT < 100)) && SEARCH_MATCH_LIMIT=100
    declare -p FAVORITE_LABELS >/dev/null 2>&1 && has_labels=1

    if [[ -z "$SEARCH_SOURCE_FILE" && -z "$SEARCH_SOURCE_ROWS" ]]; then
        source_rows=$(search_source_rows_from_current)
    else
        source_rows="$SEARCH_SOURCE_ROWS"
    fi

    search_clear_results
    while IFS= read -r line; do
        search_add_result_line "$line" || true
    done < <(search_filter_station_rows "$source_rows")

    if ((has_labels)) && [[ -n "$query" ]]; then
        for url in "${!FAVORITE_LABELS[@]}"; do
            label="${FAVORITE_LABELS[$url],,}"
            [[ "$label" == *"$query"* ]] || continue
            ((${#SEARCH_MATCHES[@]} >= SEARCH_MATCH_LIMIT)) && break
            [[ -n "${SEARCH_URL_INDEX[$url]+set}" ]] && continue
            line=$(search_station_line_for_url "$url" "$source_rows")
            [[ -n "$line" ]] || continue
            if ((SEARCH_COUNTRY_FILTER_ENABLED)); then
                local line_countrycode=''
                IFS=$'\t' read -r _ _ _ _ _ line_countrycode _ <<< "$line"
                [[ "$line_countrycode" == "$KEILA_CATALOG_COUNTRY_FILTER" ]] || continue
            fi
            search_add_result_line "$line" || true
        done
    fi

    if ((${#SEARCH_MATCHES[@]} == 0)); then
        SEARCH_SELECTED_INDEX=0
        SEARCH_SCROLL_OFFSET=0
    else
        ((SEARCH_SELECTED_INDEX >= ${#SEARCH_MATCHES[@]})) && SEARCH_SELECTED_INDEX=$((${#SEARCH_MATCHES[@]} - 1))
        ((SEARCH_SELECTED_INDEX < 0)) && SEARCH_SELECTED_INDEX=0
    fi

    SEARCH_FILTER_DIRTY=0
}

search_country_filter_toggle() {
    if ((SEARCH_COUNTRY_FILTER_ENABLED)); then
        SEARCH_COUNTRY_FILTER_ENABLED=0
    else
        SEARCH_COUNTRY_FILTER_ENABLED=1
    fi
    SEARCH_SELECTED_INDEX=0
    SEARCH_SCROLL_OFFSET=0
    SEARCH_FILTER_DIRTY=1
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
    SELECTED_COUNTRYCODE="${SEARCH_COUNTRYCODES[$source_index]:-}"

    [[ -n "$SELECTED_NAME" && -n "$SELECTED_URL" ]]
}
