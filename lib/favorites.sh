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

favorites_save() {
    keila_init_paths

    local tmp="${KEILA_FAVORITES_FILE}.tmp.$$"
    local i
    umask 077

    : > "$tmp"
    for ((i = 0; i < ${#FAVORITE_NAMES[@]}; i++)); do
        printf '%s|%s\n' "${FAVORITE_NAMES[$i]}" "${FAVORITE_URLS[$i]}" >> "$tmp"
    done

    mv -f "$tmp" "$KEILA_FAVORITES_FILE"
    chmod 600 "$KEILA_FAVORITES_FILE" 2>/dev/null || true
}

favorites_find_url() {
    local url="$1"
    local i

    for ((i = 0; i < ${#FAVORITE_URLS[@]}; i++)); do
        if [[ "${FAVORITE_URLS[$i]}" == "$url" ]]; then
            printf '%s\n' "$i"
            return 0
        fi
    done

    return 1
}

favorites_add() {
    local name="$1"
    local url="$2"

    [[ -n "$name" && -n "$url" ]] || return 1

    if favorites_find_url "$url" >/dev/null; then
        return 2
    fi

    name="${name//$'\n'/ }"
    name="${name//$'\r'/ }"
    name="${name//|/-}"

    if [[ "$url" == *$'\n'* || "$url" == *$'\r'* || "$url" == *'|'* ]]; then
        return 1
    fi

    FAVORITE_NAMES+=("$name")
    FAVORITE_URLS+=("$url")
    favorites_save
}

favorites_remove_index() {
    local index="$1"

    [[ "$index" =~ ^[0-9]+$ ]] || return 1
    ((index >= 0 && index < ${#FAVORITE_NAMES[@]})) || return 1

    local -a new_names=()
    local -a new_urls=()
    local i

    for ((i = 0; i < ${#FAVORITE_NAMES[@]}; i++)); do
        ((i == index)) && continue
        new_names+=("${FAVORITE_NAMES[$i]}")
        new_urls+=("${FAVORITE_URLS[$i]}")
    done

    FAVORITE_NAMES=("${new_names[@]}")
    FAVORITE_URLS=("${new_urls[@]}")
    favorites_save
}

favorites_move() {
    local index="$1"
    local delta="$2"
    local target=$((index + delta))

    [[ "$index" =~ ^[0-9]+$ ]] || return 1
    ((index >= 0 && index < ${#FAVORITE_NAMES[@]})) || return 1
    ((target >= 0 && target < ${#FAVORITE_NAMES[@]})) || return 1

    local tmp
    tmp="${FAVORITE_NAMES[$index]}"
    FAVORITE_NAMES[$index]="${FAVORITE_NAMES[$target]}"
    FAVORITE_NAMES[$target]="$tmp"

    tmp="${FAVORITE_URLS[$index]}"
    FAVORITE_URLS[$index]="${FAVORITE_URLS[$target]}"
    FAVORITE_URLS[$target]="$tmp"

    favorites_save
}

favorites_toggle() {
    local name="$1"
    local url="$2"
    local index

    if index=$(favorites_find_url "$url"); then
        favorites_remove_index "$index" || return 1
        FAVORITES_TOGGLE_ACTION="removed"
    else
        favorites_add "$name" "$url" || return 1
        FAVORITES_TOGGLE_ACTION="added"
    fi
}
