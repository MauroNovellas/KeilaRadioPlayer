#!/usr/bin/env bash
# Pantalla de estado en vivo: diagnóstico ligero sin abandonar la TUI.

STATUS_ACTIVE=0
STATUS_ROWS=()

status_human_size() {
    stations_human_size "$1"
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
    else
        stations_catalog_state_label
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
    local catalog_count='0' pending_count title_age='—' title_state='sin título' catalog_age='—' catalog_next='ahora'
    if stations_tsv_valid; then catalog_count=$(stations_count); fi
    if stations_catalog_valid; then
        catalog_age=$(stations_human_duration "$(stations_catalog_age_seconds)")
        if stations_catalog_is_fresh; then
            catalog_next=$(stations_human_duration "$((KEILA_CATALOG_MAX_AGE - $(stations_catalog_age_seconds)))")
        fi
    fi
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
    STATUS_ROWS+=("Canciones previas|$(declare -F track_history_visible_count >/dev/null 2>&1 && track_history_visible_count || printf '0')")
    STATUS_ROWS+=("Volumen|${PLAYER_VOLUME:-?}%")
    STATUS_ROWS+=("Catálogo|$(status_catalog_state)")
    STATUS_ROWS+=("Emisoras indexadas|$catalog_count")
    STATUS_ROWS+=("Catálogo actualizado|$(stations_catalog_updated_at) · hace $catalog_age")
    STATUS_ROWS+=("Próxima actualización|$catalog_next")
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
    STATUS_ROWS+=("Registro sesión|${SESSION_LOG_FILE:-no iniciado}")
    STATUS_ROWS+=("Caché|$KEILA_CACHE_DIR")
    STATUS_ROWS+=("Grabaciones|$KEILA_RECORDINGS_DIR")
    STATUS_ROWS+=("Runtime IPC|${PLAYER_RUNTIME_DIR:-—}")
}

STATUS_SELECTED=0
STATUS_SCROLL=0
STATUS_REFRESH_AT=0

status_draw() {
    local item label value
    local -a PANEL_ROWS=()
    if ((EPOCHSECONDS >= STATUS_REFRESH_AT)); then
        status_build_rows
        STATUS_REFRESH_AT=$((EPOCHSECONDS + 2))
    fi
    for item in "${STATUS_ROWS[@]}"; do
        label=${item%%|*} value=${item#*|}
        panel_add_row '' "$label" "$label: $value" "$value"
    done
    panel_draw DIAGNÓSTICO "$STATUS_SELECTED" "$STATUS_SCROLL" 'Flechas mover | Enter detalle | Esc volver' "${UI_MESSAGE:-}"
    STATUS_SELECTED=$PANEL_SELECTED STATUS_SCROLL=$PANEL_SCROLL
}

app_status_screen() {
    local event key redraw=1 status=0 previous_preferences=$PREFERENCES_ACTIVE
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    STATUS_ACTIVE=1 PREFERENCES_ACTIVE=1 STATUS_REFRESH_AT=0
    while true; do
        ((redraw)) && status_draw
        input_read || break
        event=$INPUT_EVENT key=$INPUT_KEY redraw=1
        case "$event" in
            TICK)
                redraw=0; panel_poll && redraw=1
                ((EPOCHSECONDS < STATUS_REFRESH_AT)) || redraw=1 ;;
            RESIZE) ;;
            ESC|LEFT) break ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$event" "$STATUS_SELECTED" "${#STATUS_ROWS[@]}" "$PANEL_VISIBLE"
                STATUS_SELECTED=$PANEL_SELECTED ;;
            ENTER)
                local -a PANEL_ROWS=()
                local row
                for row in "${STATUS_ROWS[@]}"; do panel_add_row '' "${row%%|*}" "${row#*|}"; done
                panel_detail DIAGNÓSTICO "$STATUS_SELECTED" ;;
            KEY)
                case "$key" in
                    d|D) break ;;
                    '?')
                        local -a PANEL_ROWS=()
                        local row
                        for row in "${STATUS_ROWS[@]}"; do panel_add_row '' "${row%%|*}" "${row#*|}"; done
                        panel_detail DIAGNÓSTICO "$STATUS_SELECTED" ;;
                    s|S)
                        panel_call DIAGNÓSTICO app_session_history_screen || status=$?
                        ((status == 2)) && break
                        STATUS_REFRESH_AT=0 ;;
                    u|U) app_update_catalog || true; STATUS_REFRESH_AT=0 ;;
                    b|B) panel_call DIAGNÓSTICO app_search_catalog || true ;;
                    ';') panel_call DIAGNÓSTICO app_pending_menu || true ;;
                    q|Q) status=2; break ;;
                    *) redraw=0 ;;
                esac ;;
        esac
    done
    STATUS_ACTIVE=0 PREFERENCES_ACTIVE=$previous_preferences
    if ((!previous_preferences && status != 2)); then ui_draw; fi
    return "$status"
}
