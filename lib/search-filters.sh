#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Filtros locales de sesión. Nunca se mezclan con la consulta libre.
SEARCH_REGION_FILTER=''
SEARCH_TAG_FILTER=''

search_filters_awk() {
    # ENVIRON evita que awk interprete escapes de consultas como \\n o \\.
    KEILA_QUERY="${SEARCH_QUERY,,}" KEILA_COUNTRY="$KEILA_CATALOG_COUNTRY_FILTER" \
    KEILA_REGION="$SEARCH_REGION_FILTER" KEILA_TAG="$SEARCH_TAG_FILTER" \
    awk -F '\t' -v country_filter="$SEARCH_COUNTRY_FILTER_ENABLED" -v limit="$SEARCH_MATCH_LIMIT" '
        BEGIN {
            query=ENVIRON["KEILA_QUERY"]; country=ENVIRON["KEILA_COUNTRY"]
            region=tolower(ENVIRON["KEILA_REGION"]); tag=tolower(ENVIRON["KEILA_TAG"])
            if (limit < 100) limit=300
        }
        NF < 5 || $5 == "" { next }
        country_filter && toupper($6) != country { next }
        region != "" && tolower($8) != region { next }
        tag != "" {
            found=0; n=split(tolower($9), tags, ",")
            for (i=1; i<=n; i++) {
                gsub(/^[ ]+|[ ]+$/, "", tags[i])
                if (tags[i] == tag) { found=1; break }
            }
            if (!found) next
        }
        {
            text=tolower($7 != "" ? $7 : $1 " " $2 " " $3 " " $4 " " $6)
            if (query == "" || index(text, query)) {
                print; if (++matches >= limit) exit
            }
        }
    ' "$1"
}

search_filters_accept_line() {
    local SEARCH_QUERY='' SEARCH_SOURCE_FILE=''
    [[ -n $(search_filter_station_rows "$1") ]]
}

search_filters_changed() {
    SEARCH_SELECTED_INDEX=0 SEARCH_SCROLL_OFFSET=0 SEARCH_FILTER_DIRTY=1
    # Refrescar también el panel sin foco, pero nunca volver a analizar JSON.
    if stations_tsv_valid; then SEARCH_SOURCE_FILE=$KEILA_STATIONS_TSV; fi
    search_apply_pending_filter || true
}

search_filters_set() {
    local kind=$1 value=$2
    case "$kind" in
        country)
            [[ -z "$value" || "$value" =~ ^[A-Z]{2}$ ]] || return 1
            SEARCH_COUNTRY_FILTER_ENABLED=0
            if [[ -n "$value" ]]; then KEILA_CATALOG_COUNTRY_FILTER=$value; SEARCH_COUNTRY_FILTER_ENABLED=1; fi
            SEARCH_REGION_FILTER='' ;;
        region) SEARCH_REGION_FILTER=$value ;;
        tag) SEARCH_TAG_FILTER=$value ;;
        clear) SEARCH_COUNTRY_FILTER_ENABLED=0 SEARCH_REGION_FILTER='' SEARCH_TAG_FILTER='' ;;
        *) return 1 ;;
    esac
    search_filters_changed
}

search_filters_summary() {
    SEARCH_FILTER_SUMMARY='Sin filtros'
    local parts=()
    ((SEARCH_COUNTRY_FILTER_ENABLED == 0)) || parts+=("País: $KEILA_CATALOG_COUNTRY_FILTER")
    [[ -z "$SEARCH_REGION_FILTER" ]] || parts+=("Región: $SEARCH_REGION_FILTER")
    [[ -z "$SEARCH_TAG_FILTER" ]] || parts+=("Tema: $SEARCH_TAG_FILTER")
    if ((${#parts[@]})); then local IFS=';'; SEARCH_FILTER_SUMMARY="${parts[*]}"; fi
}

search_filters_badge() {
    SEARCH_FILTER_BADGE='Global'
    ((SEARCH_COUNTRY_FILTER_ENABLED == 0)) || SEARCH_FILTER_BADGE="País $KEILA_CATALOG_COUNTRY_FILTER"
    if [[ -n "$SEARCH_REGION_FILTER$SEARCH_TAG_FILTER" ]]; then
        if ((SEARCH_COUNTRY_FILTER_ENABLED)); then SEARCH_FILTER_BADGE="$KEILA_CATALOG_COUNTRY_FILTER + filtros"
        else SEARCH_FILTER_BADGE='Filtros (O)'; fi
    fi
}

# Se ejecuta una vez al abrir un selector, nunca en el ciclo de repintado.
# Listas derivadas del catálogo local, no de los primeros 300 resultados.
search_filter_choices() {
    local kind=$1
    [[ -s "$KEILA_STATIONS_TSV" ]] || return 1
    KEILA_COUNTRY="$KEILA_CATALOG_COUNTRY_FILTER" KEILA_REGION="$SEARCH_REGION_FILTER" \
    awk -F '\t' -v kind="$kind" -v enabled="$SEARCH_COUNTRY_FILTER_ENABLED" '
        BEGIN { OFS="\t"; country=ENVIRON["KEILA_COUNTRY"]; region=tolower(ENVIRON["KEILA_REGION"]) }
        NF < 5 || $5 == "" { next }
        kind != "country" && enabled && toupper($6) != country { next }
        kind == "tag" && region != "" && tolower($8) != region { next }
        function emit(value, label, key) {
            gsub(/^[ ]+|[ ]+$/, "", value)
            if (value == "" || value ~ /[[:cntrl:]]/) return
            key=tolower(value)
            if (!seen[key]++) print value, label
        }
        kind == "country" && $6 ~ /^[A-Za-z][A-Za-z]$/ {
            code=toupper($6); name=$3
            if (code == "ES") name="España"
            emit(code, name " (" code ")"); next
        }
        kind == "region" { emit($8, $8); next }
        kind == "tag" {
            n=split($9, tags, ",")
            for (i=1; i<=n; i++) { gsub(/^[ ]+|[ ]+$/, "", tags[i]); emit(tags[i], tags[i]) }
        }
    ' "$KEILA_STATIONS_TSV" | LC_ALL=C sort -t $'\t' -k2,2
}
