#!/usr/bin/env bash

CATALOG_PID=''
CATALOG_JOB_DIR=''
CATALOG_STATUS='Cargando emisoras…'

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

catalog_worker_stop() {
    local child
    for child in $(jobs -pr); do kill "$child" 2>/dev/null || true; done
    wait
    rm -f "${KEILA_STATIONS_JSON}.tmp.${BASHPID}"
    exit 0
}

catalog_start() {
    [[ -z "$CATALOG_PID" ]] || return 0
    if [[ "${1:-}" != force ]]; then
        if stations_catalog_valid; then catalog_reload || true; fi
        stations_catalog_is_fresh && return 0
    fi
    CATALOG_JOB_DIR=$(mktemp -d "$KEILA_CACHE_DIR/catalog.XXXXXX") || return 1
    CATALOG_STATUS='Cargando emisoras…'
    (
        # No heredar cleanup de la TUI: este proceso solo es dueño de su descarga.
        trap - EXIT INT TERM
        trap catalog_worker_stop TERM INT
        result=0
        stations_update_catalog >/dev/null 2>&1 || result=$?
        printf '%s\n' "$result" > "$CATALOG_JOB_DIR/done"
    ) </dev/null >/dev/null 2>&1 &
    CATALOG_PID=$!
}

catalog_poll() {
    [[ -n "$CATALOG_PID" ]] || return 1
    if [[ ! -f "$CATALOG_JOB_DIR/done" ]] && kill -0 "$CATALOG_PID" 2>/dev/null; then return 1; fi
    local status=1
    [[ -f "$CATALOG_JOB_DIR/done" ]] && read -r status < "$CATALOG_JOB_DIR/done"
    wait "$CATALOG_PID" 2>/dev/null || true
    CATALOG_PID=''
    rm -rf "$CATALOG_JOB_DIR"
    CATALOG_JOB_DIR=''
    if [[ "$status" == 0 ]] && catalog_reload; then
        return 0
    fi
    if ((${#SEARCH_NAMES[@]})); then
        CATALOG_STATUS='Usando catálogo guardado'
        app_message 'Sin actualización de emisoras; se conserva el catálogo guardado.' 5
    else
        CATALOG_STATUS='Sin catálogo disponible; U reintentar'
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
