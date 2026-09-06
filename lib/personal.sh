#!/usr/bin/env bash

# Datos personales independientes del formato histórico nombre|URL de favoritos.
declare -A FAVORITE_LABELS=()
HISTORY_NAMES=()
HISTORY_URLS=()
RECENT_NAMES=()
RECENT_URLS=()
HISTORY_PENDING_URL=''

personal_text() {
    local text="$1"
    text="${text//[[:cntrl:]]/ }"
    text="${text//|/-}"
    printf '%s' "${text:0:80}"
}

labels_load() {
    FAVORITE_LABELS=()
    local url label file="${KEILA_CONFIG_DIR}/labels"
    [[ -f "$file" ]] || return 0
    while IFS='|' read -r url label; do
        [[ -n "$url" ]] || continue
        FAVORITE_LABELS["$url"]=$(personal_text "$label")
    done < "$file"
}

labels_set() {
    local url="$1" label file="${KEILA_CONFIG_DIR}/labels" status=0 key tmp
    [[ -n "$url" && "$url" != *[[:cntrl:]\|]* ]] || return 1
    label=$(personal_text "$2")
    lock_acquire "$file.lock" || return 1
    labels_load
    FAVORITE_LABELS["$url"]="$label"
    tmp=$(mktemp "$file.tmp.XXXXXX") || { lock_release "$file.lock"; labels_load; return 1; }
    for key in "${!FAVORITE_LABELS[@]}"; do
        [[ -n "${FAVORITE_LABELS[$key]}" ]] || continue
        printf '%s|%s\n' "$key" "${FAVORITE_LABELS[$key]}" >> "$tmp" || status=1
    done
    if ((status == 0)); then mv -f "$tmp" "$file" || status=1; fi
    rm -f "$tmp"
    lock_release "$file.lock" || status=1
    labels_load
    return "$status"
}

history_load() {
    HISTORY_NAMES=()
    HISTORY_URLS=()
    local name url file="${KEILA_STATE_DIR}/history"
    [[ -f "$file" ]] || return 0
    while IFS='|' read -r name url; do
        [[ -n "$name" && -n "$url" && "$url" != *[[:cntrl:]\|]* ]] || continue
        HISTORY_NAMES+=("$(personal_text "$name")")
        HISTORY_URLS+=("$url")
        ((${#HISTORY_URLS[@]} >= 20)) && break
    done < "$file"
    return 0
}

history_record() {
    local name url="$2" file="${KEILA_STATE_DIR}/history" tmp i status=0
    [[ -n "$url" && "$url" != *[[:cntrl:]\|]* ]] || return 1
    name=$(personal_text "$1")
    lock_acquire "$file.lock" || return 1
    history_load
    local -a names=("$name") urls=("$url")
    for ((i=0; i<${#HISTORY_URLS[@]}; i++)); do
        [[ "${HISTORY_URLS[i]}" == "$url" ]] && continue
        ((${#urls[@]} >= 20)) && break
        names+=("${HISTORY_NAMES[i]}")
        urls+=("${HISTORY_URLS[i]}")
    done
    tmp=$(mktemp "$file.tmp.XXXXXX") || { lock_release "$file.lock"; return 1; }
    for ((i=0; i<${#urls[@]}; i++)); do
        printf '%s|%s\n' "${names[i]}" "${urls[i]}" >> "$tmp" || status=1
    done
    if ((status == 0)); then mv -f "$tmp" "$file" || status=1; fi
    rm -f "$tmp"
    lock_release "$file.lock" || status=1
    history_load
    return "$status"
}

history_recent_refresh() {
    RECENT_NAMES=()
    RECENT_URLS=()
    local i
    for ((i=0; i<${#HISTORY_URLS[@]}; i++)); do
        favorites_find_url "${HISTORY_URLS[i]}" >/dev/null && continue
        RECENT_NAMES+=("${HISTORY_NAMES[i]}")
        RECENT_URLS+=("${HISTORY_URLS[i]}")
    done
    return 0
}

history_observe() {
    [[ -n "$HISTORY_PENDING_URL" && "$HISTORY_PENDING_URL" == "${PLAYER_URL:-}" ]] || return 1
    ((${PLAYER_STREAM_READY:-0})) || return 1
    local selected_url='' recent_index
    if ((${UI_SELECTED_INDEX:-0} >= ${#FAVORITE_URLS[@]})); then
        recent_index=$((${UI_SELECTED_INDEX:-0} - ${#FAVORITE_URLS[@]}))
        selected_url="${RECENT_URLS[recent_index]:-}"
    fi
    HISTORY_PENDING_URL=''
    history_record "$PLAYER_NAME" "$PLAYER_URL" || {
        app_message 'No se pudo guardar el historial.' 5
        return 0
    }
    history_recent_refresh
    if [[ -n "$selected_url" ]] && declare -F ui_select_url >/dev/null; then
        ui_select_url "$selected_url" || true
    fi
    return 0
}
