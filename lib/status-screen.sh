#!/usr/bin/env bash
# Pantalla de estado en vivo: diagnóstico ligero sin abandonar la TUI.

STATUS_ACTIVE=0
STATUS_ROWS=()

status_human_size() {
    local file="$1" size
    [[ -e "$file" ]] || { printf 'no existe'; return 0; }
    size=$(wc -c < "$file" 2>/dev/null || printf '0')
    awk -v size="$size" 'BEGIN {
        split("B KiB MiB GiB", units, " ")
        value = size + 0
        unit = 1
        while (value >= 1024 && unit < 4) { value /= 1024; unit++ }
        if (unit == 1) printf "%d %s", value, units[unit]
        else printf "%.1f %s", value, units[unit]
    }'
}

status_mtime() {
    local file="$1"
    [[ -e "$file" ]] || { printf '—'; return 0; }
    date -d "@$(stat -c %Y "$file" 2>/dev/null || printf '0')" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '—'
}

status_git_revision() {
    local base_dir="${BASE_DIR:-.}" branch commit
    [[ -d "$base_dir/.git" ]] || { printf 'sin repositorio git'; return 0; }
    branch=$(git -C "$base_dir" branch --show-current 2>/dev/null || true)
    commit=$(git -C "$base_dir" rev-parse --short HEAD 2>/dev/null || true)
    [[ -n "$branch$commit" ]] || { printf 'git no disponible'; return 0; }
    printf '%s%s%s' "${branch:-sin-rama}" "${commit:+ · }" "$commit"
}

status_catalog_state() {
    if [[ -n "${CATALOG_PID:-}" ]]; then
        printf '%s' "${CATALOG_STATUS:-actualizando}"
    elif stations_catalog_is_fresh; then
        printf 'fresco'
    elif stations_catalog_valid; then
        printf 'disponible, pendiente de actualizar'
    else
        printf 'sin catálogo válido'
    fi
}

status_player_state() {
    if player_is_running; then
        if ((${PLAYER_PAUSED:-0})); then printf 'pausado'; else printf 'reproduciendo'; fi
        if ((${PLAYER_BUFFERING:-0})); then printf ' · buffer'; fi
        if ((${PLAYER_MUTED:-0})); then printf ' · silencio'; fi
        printf ' · pid %s' "${PLAYER_PID:-?}"
    else
        printf 'detenido'
    fi
}

status_build_rows() {
    STATUS_ROWS=()
    local catalog_count='0' pending_count title_age='—' title_state='sin título'
    if stations_tsv_valid; then catalog_count=$(stations_count); fi
    pending_count=${#PENDING_FILES[@]}
    if [[ -n "${PLAYER_STREAM_TITLE:-}" ]]; then
        title_state="$PLAYER_STREAM_TITLE"
        if ((PLAYER_STREAM_TITLE_UPDATED_AT > 0)); then
            title_age="$((${EPOCHSECONDS:-$(date +%s)} - PLAYER_STREAM_TITLE_UPDATED_AT))s"
        fi
    fi

    STATUS_ROWS+=("Versión|Keila ${KEILA_VERSION:-desconocida}")
    STATUS_ROWS+=("Git|$(status_git_revision)")
    STATUS_ROWS+=("Entorno|$(deps_is_termux && printf 'Termux' || printf 'Unix/Linux') · Bash ${BASH_VERSION%%(*}")
    STATUS_ROWS+=("Terminal|${TERM:-sin TERM} · ${UI_COLS:-?}x${UI_LINES:-?}")
    STATUS_ROWS+=("Reproductor|$(status_player_state)")
    STATUS_ROWS+=("Emisora|${PLAYER_NAME:-ninguna}")
    STATUS_ROWS+=("Título|$title_state")
    STATUS_ROWS+=("Título edad|$title_age")
    STATUS_ROWS+=("Volumen|${PLAYER_VOLUME:-?}%")
    STATUS_ROWS+=("Catálogo|$(status_catalog_state)")
    STATUS_ROWS+=("Emisoras indexadas|$catalog_count")
    STATUS_ROWS+=("Resultados precargados|${#SEARCH_MATCHES[@]}")
    STATUS_ROWS+=("Filtro país|${KEILA_CATALOG_COUNTRY_FILTER:-ES} · $((SEARCH_COUNTRY_FILTER_ENABLED))")
    STATUS_ROWS+=("JSON Radio Browser|$(status_human_size "$KEILA_STATIONS_JSON") · $(status_mtime "$KEILA_STATIONS_JSON")")
    STATUS_ROWS+=("Índice TUI|$(status_human_size "$KEILA_STATIONS_TSV") · $(status_mtime "$KEILA_STATIONS_TSV")")
    STATUS_ROWS+=("Grabación|$((RECORDING_ACTIVE)) · ${RECORDING_PHASE:-idle} · ${RECORDING_FILE:-sin archivo}")
    STATUS_ROWS+=("Pendientes|$pending_count${PENDING_SCAN_PID:+ · escaneando}")
    STATUS_ROWS+=("Config|$KEILA_CONFIG_FILE")
    STATUS_ROWS+=("Favoritos|${#FAVORITE_NAMES[@]} · $KEILA_FAVORITES_FILE")
    STATUS_ROWS+=("Comentarios|${#FAVORITE_LABELS[@]} · $KEILA_CONFIG_DIR/labels")
    STATUS_ROWS+=("Estado|$KEILA_STATE_FILE")
    STATUS_ROWS+=("Caché|$KEILA_CACHE_DIR")
    STATUS_ROWS+=("Grabaciones|$KEILA_RECORDINGS_DIR")
    STATUS_ROWS+=("Runtime IPC|${PLAYER_RUNTIME_DIR:-—}")
}

status_draw() {
    ui_refresh_size
    status_build_rows
    local width=$((UI_COLS - 1)) height=$((UI_LINES - 4)) i label value line
    ((width < 1)) && width=1
    ((height < 1)) && height=1
    tput cup 0 0 2>/dev/null || true
    ui_print_styled_padded "$width" 'KEILA · DIAGNÓSTICO EN VIVO' title; printf '\n'
    for ((i=0; i<height && i<${#STATUS_ROWS[@]}; i++)); do
        label=${STATUS_ROWS[i]%%|*}
        value=${STATUS_ROWS[i]#*|}
        line=$(printf '%-22s %s' "$label" "$value")
        ui_print_styled_padded "$width" "$line" accent
        printf '\n'
    done
    ui_print_padded "$width" 'D/Esc volver · U actualiza catálogo · ; grabaciones · B búsqueda'
    printf '\n'
    ui_print_padded "$width" "${UI_MESSAGE:-}"
    tput ed 2>/dev/null || true
}

app_status_screen() {
    local event key redraw=1
    STATUS_ACTIVE=1
    PREFERENCES_ACTIVE=1
    while true; do
        ((redraw)) && status_draw
        input_read || break
        event=$INPUT_EVENT key=$INPUT_KEY redraw=1
        case "$event" in
            TICK)
                redraw=0
                app_poll_player && redraw=1
                catalog_poll && redraw=1
                pending_scan_poll && redraw=1
                ui_message_tick && redraw=1
                ;;
            RESIZE) redraw=1 ;;
            ESC) break ;;
            KEY)
                case "$key" in
                    d|D) break ;;
                    u|U) app_update_catalog || true ;;
                    b|B) app_search_catalog || true ;;
                    ';') app_pending_menu || true ;;
                    q|Q) STATUS_ACTIVE=0; PREFERENCES_ACTIVE=0; return 2 ;;
                    *) redraw=0 ;;
                esac
                ;;
        esac
    done
    STATUS_ACTIVE=0
    PREFERENCES_ACTIVE=0
    ui_draw
}
