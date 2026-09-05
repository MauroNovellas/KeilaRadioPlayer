#!/usr/bin/env bash

# Catálogo de emisoras de TDTChannels: caché, validación y búsqueda.

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
    [[ -s "$KEILA_STATIONS_JSON" ]] || return 1
    jq -e '(.countries | type == "array") and (.countries | length > 0)' \
        "$KEILA_STATIONS_JSON" >/dev/null 2>&1
}

stations_catalog_is_fresh() {
    stations_catalog_valid || return 1

    local modified now age
    modified=$(stat -c %Y "$KEILA_STATIONS_JSON" 2>/dev/null || printf '0')
    [[ "$modified" =~ ^[0-9]+$ ]] || return 1

    now=$(date +%s)
    age=$((now - modified))
    ((age >= 0 && age < KEILA_CATALOG_MAX_AGE))
}

stations_update_catalog() {
    stations_require_catalog_dependencies || return 1
    keila_init_paths

    local tmp="${KEILA_STATIONS_JSON}.tmp.$$"
    rm -f "$tmp"

    printf 'Actualizando catálogo de TDTChannels...\n'

    if ! curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --connect-timeout 8 \
        --max-time 30 \
        --retry 1 \
        "$KEILA_TDTCHANNELS_RADIO_URL" \
        --output "$tmp"; then
        rm -f "$tmp"
        printf 'No se pudo descargar el catálogo.\n' >&2
        return 1
    fi

    if ! jq -e '(.countries | type == "array") and (.countries | length > 0)' \
        "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        printf 'El catálogo descargado no tiene el formato esperado.\n' >&2
        return 1
    fi

    mv -f "$tmp" "$KEILA_STATIONS_JSON"
    chmod 600 "$KEILA_STATIONS_JSON" 2>/dev/null || true

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
    jq -r '
        .countries[]? as $country |
        $country.ambits[]? as $ambit |
        $ambit.channels[]? as $channel |
        (($channel.options // [])
            | map(select(.url? and (.url | type == "string") and (.url | length > 0)))
            | .[0]) as $option |
        select($option != null) |
        [
            (($channel.name // "Sin nombre") | gsub("[\\t\\r\\n]"; " ")),
            (($ambit.name // "") | gsub("[\\t\\r\\n]"; " ")),
            (($country.name // "") | gsub("[\\t\\r\\n]"; " ")),
            (($option.format // "") | gsub("[\\t\\r\\n]"; " ")),
            ($option.url | gsub("[\\t\\r\\n]"; " "))
        ] | @tsv
    ' "$KEILA_STATIONS_JSON"
}

stations_count() {
    stations_emit_tsv | awk 'END { print NR + 0 }'
}

stations_select_fzf() {
    stations_require_search_dependencies || return 1
    stations_ensure_catalog || return 1

    local selection
    selection=$(
        stations_emit_tsv |
            fzf \
                --delimiter=$'\t' \
                --with-nth=1,2,3,4 \
                --prompt='Buscar emisora > ' \
                --header='Nombre | Ámbito | País | Formato' \
                --layout=reverse \
                --border
    ) || return $?

    [[ -n "$selection" ]] || return 1

    IFS=$'\t' read -r \
        SELECTED_NAME \
        SELECTED_AMBIT \
        SELECTED_COUNTRY \
        SELECTED_FORMAT \
        SELECTED_URL <<< "$selection"

    [[ -n "${SELECTED_NAME:-}" && -n "${SELECTED_URL:-}" ]]
}
