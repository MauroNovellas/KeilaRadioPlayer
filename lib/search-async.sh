#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Solo el filtrado de una consulta editada es asíncrono. Los comandos que usan
# la selección sincronizan antes con search_apply_pending_filter.
SEARCH_WORKER="$(dirname "${BASH_SOURCE[0]}")/search-worker.sh"
SEARCH_WORK_PID='' SEARCH_WORK_DIR='' SEARCH_WORK_REQUEST=''
SEARCH_WORK_LIMIT=300 SEARCH_ASYNC_FAILED=0

search_async_cleanup() {
    if [[ -n $SEARCH_WORK_PID ]]; then
        if declare -F player_terminate_group_bounded >/dev/null 2>&1; then
            player_terminate_group_bounded "$SEARCH_WORK_PID" "$SEARCH_WORK_PID" >/dev/null 2>&1 || true
        else
            kill -TERM -- "-$SEARCH_WORK_PID" 2>/dev/null || true
        fi
        wait "$SEARCH_WORK_PID" 2>/dev/null || true
    fi
    SEARCH_WORK_PID=''
    if [[ -n $SEARCH_WORK_DIR && $SEARCH_WORK_DIR == "${TMPDIR:-/tmp}/keila-search."* && ! -L $SEARCH_WORK_DIR ]]; then
        rm -rf -- "$SEARCH_WORK_DIR"
    fi
    SEARCH_WORK_DIR='' SEARCH_WORK_REQUEST=''
}

search_async_signature() {
    printf -v SEARCH_WORK_SIGNATURE '%q\034' "$SEARCH_QUERY" "$SEARCH_SOURCE_FILE" \
        "${KEILA_SEARCH_MATCH_LIMIT:-$SEARCH_MATCH_LIMIT}" "$SEARCH_COUNTRY_FILTER_ENABLED" \
        "$KEILA_CATALOG_COUNTRY_FILTER" "$SEARCH_REGION_FILTER" "$SEARCH_TAG_FILTER"
}

search_async_start() {
    local url limit=${KEILA_SEARCH_MATCH_LIMIT:-$SEARCH_MATCH_LIMIT}
    [[ $limit =~ ^[0-9]+$ ]] || limit=300
    ((limit >= 100)) || limit=100
    SEARCH_WORK_DIR=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/keila-search.XXXXXX") || return 1
    SEARCH_WORK_LIMIT=$limit
    # Datos separados por NUL: no source/eval de comentarios ni resultados.
    if ! {
        if declare -p FAVORITE_LABELS >/dev/null 2>&1; then
            for url in "${!FAVORITE_LABELS[@]}"; do printf '%s\0%s\0' "$url" "${FAVORITE_LABELS[$url]}"; done
        fi
    } > "$SEARCH_WORK_DIR/labels"; then search_async_cleanup; return 1; fi
    SEARCH_WORK_REQUEST=$SEARCH_WORK_SIGNATURE
    setsid -- timeout --kill-after=1s 8s bash "$SEARCH_WORKER" "$SEARCH_SOURCE_FILE" "$SEARCH_QUERY" \
        "$limit" "$SEARCH_COUNTRY_FILTER_ENABLED" "$KEILA_CATALOG_COUNTRY_FILTER" \
        "$SEARCH_REGION_FILTER" "$SEARCH_TAG_FILTER" "$SEARCH_WORK_DIR" </dev/null >/dev/null 2>&1 &
    SEARCH_WORK_PID=$!
}

search_async_read() {
    local file=$1 fd header count size field footer extra='' i url
    [[ -f $file && ! -L $file ]] || return 1
    size=$(stat -c %s "$file") || return 1
    ((size > 0 && size <= 16777216)) || return 1
    local -a names=() ambits=() countries=() formats=() urls=() codes=() texts=() regions=() tags=()
    exec {fd}< "$file" || return 1
    if ! IFS= read -r -d '' header <&"$fd" || [[ $header != keila-search-v1 ]] ||
        ! IFS= read -r -d '' count <&"$fd" || [[ ! $count =~ ^(0|[1-9][0-9]{0,6})$ ]] || ((count > SEARCH_WORK_LIMIT)); then
        exec {fd}<&-; return 1
    fi
    if ((count > 0)); then
        for field in names ambits countries formats urls codes texts regions tags; do
            mapfile -d '' -t -n "$count" "$field" <&"$fd" || { exec {fd}<&-; return 1; }
            local -n values=$field
            if ((${#values[@]} != count)); then exec {fd}<&-; return 1; fi
            unset -n values
        done
    fi
    if ! IFS= read -r -d '' footer <&"$fd" || [[ $footer != keila-search-end ]]; then exec {fd}<&-; return 1; fi
    if IFS= read -r -d '' extra <&"$fd" || [[ -n $extra ]]; then exec {fd}<&-; return 1; fi
    exec {fd}<&-
    for url in "${urls[@]}"; do [[ -n $url ]] || return 1; done
    # Publicar solo tras validar las nueve columnas completas. No cambiar la
    # consulta ni compartir arrays a medio cargar con navegación/reproducción.
    SEARCH_NAMES=("${names[@]}") SEARCH_AMBITS=("${ambits[@]}") SEARCH_COUNTRIES=("${countries[@]}")
    SEARCH_FORMATS=("${formats[@]}") SEARCH_URLS=("${urls[@]}") SEARCH_COUNTRYCODES=("${codes[@]}")
    SEARCH_INDEX_TEXTS=("${texts[@]}") SEARCH_REGIONS=("${regions[@]}") SEARCH_TAGS=("${tags[@]}")
    SEARCH_MATCHES=() SEARCH_URL_INDEX=() SEARCH_INDEX_ROWS=''
    for ((i=0; i<count; i++)); do SEARCH_MATCHES+=("$i"); SEARCH_URL_INDEX["${urls[i]}"]=$i; done
    SEARCH_SELECTED_INDEX=0 SEARCH_SCROLL_OFFSET=0 SEARCH_FILTER_DIRTY=0
}

search_async_tick() {
    ((SEARCH_FILTER_DIRTY)) || return 1
    # El fallback en memoria se usa en pruebas/índices pequeños. No necesita
    # un worker y mantiene la misma semántica que el selector externo.
    if ((SEARCH_ASYNC_FAILED)) || [[ -z $SEARCH_SOURCE_FILE ]]; then
        search_apply_pending_filter
        return $?
    fi
    search_async_signature
    if [[ -n $SEARCH_WORK_REQUEST && $SEARCH_WORK_REQUEST != "$SEARCH_WORK_SIGNATURE" ]]; then search_async_cleanup; fi
    if [[ -z $SEARCH_WORK_PID ]]; then
        if ! search_async_start; then SEARCH_ASYNC_FAILED=1; search_apply_pending_filter; return $?; fi
        return 1
    fi
    kill -0 "$SEARCH_WORK_PID" 2>/dev/null && return 1
    local status=0
    wait "$SEARCH_WORK_PID" 2>/dev/null || status=$?
    SEARCH_WORK_PID=''
    if ((status == 0)) && search_async_read "$SEARCH_WORK_DIR/result"; then
        search_async_cleanup
        return 0
    fi
    search_async_cleanup
    SEARCH_ASYNC_FAILED=1
    search_apply_pending_filter
}
