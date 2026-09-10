#!/usr/bin/env bash

# Catálogo de emisoras de Radio Browser: caché, validación y búsqueda.

stations_require_catalog_dependencies() {
    local missing=0 dep

    for dep in curl jq; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            printf 'Falta la dependencia: %s\n' "$dep" >&2
            missing=1
        fi
    done

    if ((missing)); then
        printf 'En Debian puedes instalarlas con: sudo apt install curl jq\n' >&2
        return 1
    fi
}

stations_require_search_dependencies() {
    stations_require_catalog_dependencies || return 1

    if ! command -v fzf >/dev/null 2>&1; then
        printf 'Falta la dependencia: fzf\n' >&2
        printf 'En Debian puedes instalarla con: sudo apt install fzf\n' >&2
        return 1
    fi
}

stations_catalog_valid() {
    stations_tsv_valid && return 0
    stations_json_valid
}

stations_json_valid() {
    [[ -s "$KEILA_STATIONS_JSON" ]] || return 1
    jq -e 'type == "array" and any(.[]; (.name? // "") != "" and (.url_resolved? // .url? // "") != "")' \
        "$KEILA_STATIONS_JSON" >/dev/null 2>&1
}

stations_tsv_valid() {
    [[ -s "$KEILA_STATIONS_TSV" ]] || return 1
    awk -F '\t' 'NF >= 5 && $1 != "" && $5 != "" { found=1; exit } END { exit !found }' \
        "$KEILA_STATIONS_TSV" >/dev/null 2>&1
}

stations_catalog_is_fresh() {
    stations_tsv_valid || return 1

    local modified now age
    modified=$(stat -c %Y "$KEILA_STATIONS_TSV" 2>/dev/null || printf '0')
    [[ "$modified" =~ ^[0-9]+$ ]] || return 1

    now=$(date +%s)
    age=$((now - modified))
    ((age >= 0 && age < KEILA_CATALOG_MAX_AGE))
}

stations_catalog_mtime() {
    local file=''
    if [[ -s "$KEILA_STATIONS_TSV" ]]; then
        file="$KEILA_STATIONS_TSV"
    elif [[ -s "$KEILA_STATIONS_JSON" ]]; then
        file="$KEILA_STATIONS_JSON"
    fi
    [[ -n "$file" ]] || { printf '0'; return 0; }
    stat -c %Y "$file" 2>/dev/null || printf '0'
}

stations_catalog_age_seconds() {
    local modified now
    modified=$(stations_catalog_mtime)
    [[ "$modified" =~ ^[0-9]+$ ]] || modified=0
    ((modified > 0)) || { printf '0'; return 0; }
    now=$(date +%s)
    if ((now >= modified)); then
        printf '%s' "$((now - modified))"
    else
        printf '0'
    fi
}

stations_human_duration() {
    local seconds="${1:-0}" value unit
    [[ "$seconds" =~ ^[0-9]+$ ]] || seconds=0
    if ((seconds < 60)); then
        printf '%ss' "$seconds"
    elif ((seconds < 3600)); then
        printf '%sm' "$((seconds / 60))"
    elif ((seconds < 86400)); then
        printf '%sh %02sm' "$((seconds / 3600))" "$(((seconds % 3600) / 60))"
    else
        value=$((seconds / 86400))
        unit='d'
        printf '%s%s %sh' "$value" "$unit" "$(((seconds % 86400) / 3600))"
    fi
}

stations_human_size() {
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

stations_catalog_updated_at() {
    local modified
    modified=$(stations_catalog_mtime)
    [[ "$modified" =~ ^[0-9]+$ ]] || modified=0
    ((modified > 0)) || { printf '—'; return 0; }
    date -d "@$modified" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '—'
}

stations_catalog_state_label() {
    if stations_catalog_is_fresh; then
        printf 'fresco'
    elif stations_catalog_valid; then
        printf 'offline/caducado'
    else
        printf 'sin catálogo válido'
    fi
}

stations_json_is_fresh() {
    stations_json_valid || return 1

    local modified now age
    modified=$(stat -c %Y "$KEILA_STATIONS_JSON" 2>/dev/null || printf '0')
    [[ "$modified" =~ ^[0-9]+$ ]] || return 1

    now=$(date +%s)
    age=$((now - modified))
    ((age >= 0 && age < KEILA_CATALOG_MAX_AGE))
}

stations_build_tsv() {
    local json_file="$1"
    local tsv_file="$2"

    jq -r '
        def clean:
            tostring | gsub("[\\t\\r\\n]"; " ") | gsub("  +"; " ") | sub("^ +"; "") | sub(" +$"; "");
        .[]? |
        (.url_resolved // .url // "") as $url |
        select(($url | type == "string") and ($url | length > 0)) |
        ((.name // "Sin nombre") | clean) as $name |
        (((.state // "") as $state | (.tags // "") as $tags |
            if ($state | length) > 0 then $state else $tags end) | clean) as $ambit |
        ((.country // .countrycode // "") | clean) as $country |
        (((.codec // "") + (if (.bitrate? // 0) > 0 then " " + ((.bitrate | tostring) + "k") else "" end)) | clean) as $format |
        ($url | clean) as $stream_url |
        ((.countrycode // "") | ascii_upcase | clean) as $countrycode |
        (($name + " " + $ambit + " " + $country + " " + $format + " " + $countrycode) | ascii_downcase | clean) as $index |
        [
            $name,
            $ambit,
            $country,
            $format,
            $stream_url,
            $countrycode,
            $index
        ] | @tsv
    ' "$json_file" > "$tsv_file"
}

stations_rebuild_tsv() {
    stations_json_valid || return 1
    local tmp="${KEILA_STATIONS_TSV}.tmp.${BASHPID:-$$}"
    rm -f "$tmp"
    stations_build_tsv "$KEILA_STATIONS_JSON" "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    stations_tsv_valid_file "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    mv -f "$tmp" "$KEILA_STATIONS_TSV"
    chmod 600 "$KEILA_STATIONS_TSV" 2>/dev/null || true
}

stations_tsv_valid_file() {
    local file="$1"
    [[ -s "$file" ]] || return 1
    awk -F '\t' 'NF >= 5 && $1 != "" && $5 != "" { found=1; exit } END { exit !found }' \
        "$file" >/dev/null 2>&1
}

stations_update_catalog() {
    stations_require_catalog_dependencies || return 1
    keila_init_paths

    local tmp="${KEILA_STATIONS_JSON}.tmp.${BASHPID:-$$}"
    local tsv_tmp="${KEILA_STATIONS_TSV}.tmp.${BASHPID:-$$}"
    local servers_tmp="${KEILA_STATIONS_JSON}.servers.${BASHPID:-$$}"
    local -a api_roots=()
    local api_root=''
    rm -f "$tmp"

    printf 'Actualizando catálogo de Radio Browser...\n'

    if curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --connect-timeout 8 \
        --max-time 15 \
        --retry 1 \
        --user-agent "$KEILA_RADIO_BROWSER_USER_AGENT" \
        "$KEILA_RADIO_BROWSER_SERVER_DISCOVERY_URL" \
        --output "$servers_tmp"; then
        mapfile -t api_roots < <(jq -r '.[].name? // empty' "$servers_tmp" 2>/dev/null | awk 'NF { print "https://" $0 }')
    fi
    rm -f "$servers_tmp"

    api_roots+=("$KEILA_RADIO_BROWSER_FALLBACK_URL")
    local download_ok=1 download_pid
    for api_root in "${api_roots[@]}"; do
        [[ -n "$api_root" ]] || continue
        curl \
            --fail \
            --location \
            --silent \
            --show-error \
            --connect-timeout 8 \
            --max-time 45 \
            --retry 1 \
            --user-agent "$KEILA_RADIO_BROWSER_USER_AGENT" \
            "$api_root/json/stations/search?hidebroken=true&order=clickcount&reverse=true&limit=$KEILA_CATALOG_LIMIT" \
            --output "$tmp" &
        download_pid=$!
        if wait "$download_pid"; then
            download_ok=0
            break
        fi
    done

    if ((download_ok != 0)); then
        rm -f "$tmp"
        printf 'No se pudo descargar el catálogo.\n' >&2
        return 1
    fi

    if ! jq -e 'type == "array" and any(.[]; (.name? // "") != "" and (.url_resolved? // .url? // "") != "")' \
        "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        printf 'El catálogo descargado no tiene el formato esperado.\n' >&2
        return 1
    fi
    if ! stations_build_tsv "$tmp" "$tsv_tmp" || ! stations_tsv_valid_file "$tsv_tmp"; then
        rm -f "$tmp" "$tsv_tmp"
        printf 'No se pudo preparar el índice local de emisoras.\n' >&2
        return 1
    fi

    mv -f "$tmp" "$KEILA_STATIONS_JSON"
    mv -f "$tsv_tmp" "$KEILA_STATIONS_TSV"
    chmod 600 "$KEILA_STATIONS_JSON" 2>/dev/null || true
    chmod 600 "$KEILA_STATIONS_TSV" 2>/dev/null || true

    printf 'Catálogo actualizado: %s emisoras disponibles.\n' "$(stations_count)"
}

stations_ensure_catalog() {
    if stations_catalog_is_fresh; then
        return 0
    fi

    if stations_update_catalog; then
        return 0
    fi

    if stations_catalog_valid; then
        printf 'Aviso: usando la copia local del catálogo porque no se pudo actualizar.\n' >&2
        return 0
    fi

    printf 'No hay un catálogo válido disponible.\n' >&2
    return 1
}

stations_emit_tsv() {
    if stations_tsv_valid; then
        cat "$KEILA_STATIONS_TSV"
        return 0
    fi
    stations_build_tsv "$KEILA_STATIONS_JSON" /dev/stdout
}

stations_count() {
    stations_emit_tsv | awk 'END { print NR + 0 }'
}

stations_catalog_status() {
    keila_init_paths

    local json_status='no' tsv_status='no' count='0' state age updated next_refresh
    stations_json_valid && json_status='sí'
    stations_tsv_valid && tsv_status='sí'
    if stations_tsv_valid; then count=$(stations_count); fi
    state=$(stations_catalog_state_label)
    age=$(stations_catalog_age_seconds)
    updated=$(stations_catalog_updated_at)
    next_refresh='ahora'
    if stations_catalog_is_fresh; then
        next_refresh=$(stations_human_duration "$((KEILA_CATALOG_MAX_AGE - age))")
    fi

    printf 'Catálogo Radio Browser\n'
    printf 'Estado: %s\n' "$state"
    printf 'Emisoras indexadas: %s\n' "$count"
    printf 'Última actualización local: %s · hace %s\n' "$updated" "$(stations_human_duration "$age")"
    printf 'Próxima actualización automática: %s\n' "$next_refresh"
    printf 'Filtro rápido de país: %s\n' "${KEILA_CATALOG_COUNTRY_FILTER:-ES}"
    printf 'JSON: %s · %s · %s\n' "$json_status" "$(stations_human_size "$KEILA_STATIONS_JSON")" "$KEILA_STATIONS_JSON"
    printf 'Índice TUI: %s · %s · %s\n' "$tsv_status" "$(stations_human_size "$KEILA_STATIONS_TSV")" "$KEILA_STATIONS_TSV"
    printf 'Límite configurado: %s emisoras · caducidad %s\n' "$KEILA_CATALOG_LIMIT" "$(stations_human_duration "$KEILA_CATALOG_MAX_AGE")"
}

stations_select_fzf() {
    stations_require_search_dependencies || return 1
    stations_ensure_catalog || return 1

    local selection
    selection=$(
        stations_emit_tsv |
            fzf \
                --delimiter=$'\t' \
                --with-nth=1,2,3,4,6 \
                --prompt='Buscar emisora > ' \
                --header='Nombre | Ámbito/Tags | País | Formato | Código' \
                --layout=reverse \
                --border
    ) || return $?

    [[ -n "$selection" ]] || return 1

    local record="${selection//$'\t'/$'\x1f'}"
    IFS=$'\x1f' read -r \
        SELECTED_NAME \
        SELECTED_AMBIT \
        SELECTED_COUNTRY \
        SELECTED_FORMAT \
        SELECTED_URL \
        SELECTED_COUNTRYCODE <<< "$record"

    [[ -n "${SELECTED_NAME:-}" && -n "${SELECTED_URL:-}" ]]
}
