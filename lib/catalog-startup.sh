#!/usr/bin/env bash

CATALOG_PID=''
CATALOG_JOB_DIR=''
CATALOG_STATUS='Cargando emisoras…'
CATALOG_LAST_ERROR=''

catalog_reload() {
    local selected_url=''
    if search_selected_load; then selected_url="${SELECTED_URL:-}"; fi
    search_load_catalog || return 1
    search_filter
    local position source_index
    for ((position=0; position<${#SEARCH_MATCHES[@]}; position++)); do
        source_index=${SEARCH_MATCHES[position]}
        if [[ "${SEARCH_URLS[source_index]}" == "$selected_url" ]]; then
            SEARCH_SELECTED_INDEX=$position
            break
        fi
    done
    CATALOG_STATUS=''
}

catalog_prime_search() {
    (( ${SEARCH_ACTIVE:-0} )) && return 0
    ((${#SEARCH_MATCHES[@]} > 0)) && return 0
    stations_tsv_valid || return 1
    search_load_catalog || return 1
    search_filter
    CATALOG_STATUS=''
}

catalog_worker_stop() {
    local child
    for child in $(jobs -pr); do kill "$child" 2>/dev/null || true; done
    wait
    rm -f "${KEILA_STATIONS_JSON}.tmp.${BASHPID}"
    rm -f "${KEILA_STATIONS_TSV}.tmp.${BASHPID}"
    exit 0
}

catalog_start() {
    local mode="${1:-}"
    CATALOG_LAST_ERROR=''
    if [[ -n "$CATALOG_PID" ]]; then
        if [[ "$mode" == force ]]; then
            catalog_stop
        else
            return 0
        fi
    fi
    if [[ "$mode" != force ]]; then
        if stations_catalog_is_fresh; then
            CATALOG_STATUS=''
            catalog_prime_search || true
            return 0
        fi
        if stations_json_is_fresh && ! stations_tsv_valid; then
            mode=rebuild
        fi
        if stations_catalog_valid && { ((${SEARCH_ACTIVE:-0})) || [[ -n "${SEARCH_QUERY:-}" ]]; }; then
            catalog_reload || true
        fi
    fi
    CATALOG_JOB_DIR=$(mktemp -d "$KEILA_CACHE_DIR/catalog.XXXXXX") || return 1
    if [[ "$mode" == rebuild ]]; then
        CATALOG_STATUS='Preparando índice local…'
    else
        CATALOG_STATUS='Cargando emisoras…'
    fi
    (
        # No heredar cleanup de la TUI: este proceso solo es dueño de su descarga.
        trap - EXIT INT TERM
        trap catalog_worker_stop TERM INT
        result=0
        if [[ "$mode" == rebuild ]]; then
            stations_rebuild_tsv >"$CATALOG_JOB_DIR/output" 2>&1 || result=$?
        else
            stations_update_catalog >"$CATALOG_JOB_DIR/output" 2>&1 || result=$?
        fi
        printf '%s\n' "$result" > "$CATALOG_JOB_DIR/done"
    ) </dev/null >/dev/null 2>&1 &
    CATALOG_PID=$!
}

catalog_poll() {
    [[ -n "$CATALOG_PID" ]] || return 1
    if [[ ! -f "$CATALOG_JOB_DIR/done" ]] && kill -0 "$CATALOG_PID" 2>/dev/null; then return 1; fi
    local status=1
    [[ -f "$CATALOG_JOB_DIR/done" ]] && read -r status < "$CATALOG_JOB_DIR/done"
    if [[ -f "$CATALOG_JOB_DIR/output" ]]; then
        CATALOG_LAST_ERROR=$(awk 'NF { last=$0 } END { print last }' "$CATALOG_JOB_DIR/output")
    else
        CATALOG_LAST_ERROR=''
    fi
    wait "$CATALOG_PID" 2>/dev/null || true
    CATALOG_PID=''
    rm -rf "$CATALOG_JOB_DIR"
    CATALOG_JOB_DIR=''
    if [[ "$status" == 0 ]]; then
        if ((${SEARCH_ACTIVE:-0})) || [[ -n "${SEARCH_QUERY:-}" ]]; then
            catalog_reload || return 0
        else
            catalog_prime_search || true
        fi
        CATALOG_STATUS=''
        if declare -F app_message >/dev/null 2>&1; then
            app_message 'Catálogo de emisoras listo. Pulsa B para buscar.' 4
        fi
        return 0
    fi
    if stations_catalog_valid; then
        CATALOG_STATUS='Usando catálogo guardado'
        if ((${SEARCH_ACTIVE:-0})) || [[ -n "${SEARCH_QUERY:-}" ]]; then
            catalog_reload || true
        fi
        app_message "No se pudo actualizar; se conserva el catálogo guardado.${CATALOG_LAST_ERROR:+ ($CATALOG_LAST_ERROR)}" 7
    elif ((${#SEARCH_NAMES[@]})); then
        CATALOG_STATUS='Usando catálogo guardado'
        app_message "Sin actualización de emisoras; se conserva la búsqueda actual.${CATALOG_LAST_ERROR:+ ($CATALOG_LAST_ERROR)}" 7
    else
        CATALOG_STATUS='Sin catálogo disponible; U reintentar'
        app_message "Sin catálogo disponible. Pulsa U para reintentar.${CATALOG_LAST_ERROR:+ ($CATALOG_LAST_ERROR)}" 9
    fi
    return 0
}

catalog_stop() {
    if [[ -n "$CATALOG_PID" ]]; then
        kill "$CATALOG_PID" 2>/dev/null || true
        wait "$CATALOG_PID" 2>/dev/null || true
    fi
    CATALOG_PID=''
    [[ -z "$CATALOG_JOB_DIR" ]] || rm -rf "$CATALOG_JOB_DIR"
    CATALOG_JOB_DIR=''
}
