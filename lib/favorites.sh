#!/usr/bin/env bash

# Favoritos personales de Keila. El repositorio solo actúa como semilla inicial.

favorites_init() {
    local seed_file="${1:-}"

    keila_init_paths

    if [[ ! -f "$KEILA_FAVORITES_FILE" ]]; then
        if [[ -n "$seed_file" && -f "$seed_file" ]]; then
            cp "$seed_file" "$KEILA_FAVORITES_FILE"
        else
            : > "$KEILA_FAVORITES_FILE"
        fi
        chmod 600 "$KEILA_FAVORITES_FILE" 2>/dev/null || true
    fi
}

favorites_load() {
    FAVORITE_NAMES=()
    FAVORITE_URLS=()

    [[ -f "$KEILA_FAVORITES_FILE" ]] || return 0

    local name url
    while IFS='|' read -r name url; do
        [[ -n "${name:-}" && -n "${url:-}" ]] || continue
        FAVORITE_NAMES+=("$name")
        FAVORITE_URLS+=("$url")
    done < "$KEILA_FAVORITES_FILE"
}
