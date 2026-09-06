#!/usr/bin/env bash

# Favoritos personales de Keila. El repositorio solo actúa como semilla inicial.

# La confirmación de borrado vive en memoria y pertenece a la sesión actual.
# Nunca se persiste: sirve únicamente como barrera contra pulsaciones accidentales.
FAVORITES_CONFIRM_ACTION=''
FAVORITES_CONFIRM_URL=''
FAVORITES_CONFIRM_EXPIRES=0
FAVORITES_CONFIRM_TIMEOUT="${KEILA_FAVORITES_CONFIRM_TIMEOUT:-4}"

favorites_confirm_timeout_value() {
    local timeout="${FAVORITES_CONFIRM_TIMEOUT:-4}"
    [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=4
    ((timeout < 2)) && timeout=2
    ((timeout > 10)) && timeout=10
    printf '%s\n' "$timeout"
}

favorites_confirm_clear() {
    FAVORITES_CONFIRM_ACTION=''
    FAVORITES_CONFIRM_URL=''
    FAVORITES_CONFIRM_EXPIRES=0
}

# Limpia una confirmación caducada. Devuelve 0 solo cuando había algo que
# caducó, de modo que los bucles de UI puedan usarlo si alguna vez lo necesitan.
favorites_confirm_expire() {
    [[ -n "${FAVORITES_CONFIRM_ACTION:-}" ]] || return 1

    local now="${EPOCHSECONDS:-$(date +%s)}"
    if ((FAVORITES_CONFIRM_EXPIRES <= 0 || now > FAVORITES_CONFIRM_EXPIRES)); then
        favorites_confirm_clear
        return 0
    fi
    return 1
}

# Primera llamada: arma la confirmación y devuelve 2. Segunda llamada con la
# misma acción y URL dentro de la ventana: confirma, limpia el estado y devuelve
# 0. Una acción/URL distinta sustituye la confirmación anterior sin borrar nada.
favorites_confirm_removal() {
    local action="$1" url="$2"
    [[ -n "$action" && -n "$url" ]] || return 1

    local now="${EPOCHSECONDS:-$(date +%s)}"
    local timeout
    timeout=$(favorites_confirm_timeout_value)

    if [[ "${FAVORITES_CONFIRM_ACTION:-}" == "$action" && "${FAVORITES_CONFIRM_URL:-}" == "$url" ]] &&
        ((FAVORITES_CONFIRM_EXPIRES > 0 && now <= FAVORITES_CONFIRM_EXPIRES)); then
        favorites_confirm_clear
        return 0
    fi

    FAVORITES_CONFIRM_ACTION="$action"
    FAVORITES_CONFIRM_URL="$url"
    FAVORITES_CONFIRM_EXPIRES=$((now + timeout))
    return 2
}

favorites_init() {
    local seed_file="${1:-}"

    keila_init_paths || return 1
    [[ -f "$KEILA_FAVORITES_FILE" ]] && return 0

    local lock_dir="${KEILA_FAVORITES_FILE}.lock"
    lock_acquire "$lock_dir" || return 1

    local status=0
    if [[ ! -f "$KEILA_FAVORITES_FILE" ]]; then
        if [[ -n "$seed_file" && -f "$seed_file" ]]; then
            cp "$seed_file" "$KEILA_FAVORITES_FILE" || status=1
        else
            : > "$KEILA_FAVORITES_FILE" || status=1
        fi
        if ((status == 0)); then
            chmod 600 "$KEILA_FAVORITES_FILE" 2>/dev/null || true
        fi
    fi

    lock_release "$lock_dir" || status=1
    return "$status"
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

favorites_save_unlocked() {
    keila_init_paths || return 1
    local tmp="${KEILA_FAVORITES_FILE}.tmp.${BASHPID:-$$}"
    local i status=0
    umask 077

    : > "$tmp" || return 1
    for ((i = 0; i < ${#FAVORITE_NAMES[@]}; i++)); do
        printf '%s|%s\n' "${FAVORITE_NAMES[$i]}" "${FAVORITE_URLS[$i]}" >> "$tmp" || { status=1; break; }
    done

    if ((status == 0)); then
        mv -f "$tmp" "$KEILA_FAVORITES_FILE" || status=1
    fi
    if ((status == 0)); then
        chmod 600 "$KEILA_FAVORITES_FILE" 2>/dev/null || true
    else
        rm -f "$tmp" 2>/dev/null || true
    fi
    return "$status"
}

favorites_save() {
    local lock_dir="${KEILA_FAVORITES_FILE}.lock"
    lock_acquire "$lock_dir" || return 1
    local status=0
    favorites_save_unlocked || status=$?
    lock_release "$lock_dir" || status=1
    return "$status"
}

favorites_find_url() {
    local url="$1" i
    for ((i = 0; i < ${#FAVORITE_URLS[@]}; i++)); do
        if [[ "${FAVORITE_URLS[$i]}" == "$url" ]]; then
            printf '%s\n' "$i"
            return 0
        fi
    done
    return 1
}

favorites_add_unlocked() {
    local name="$1" url="$2"
    [[ -n "$name" && -n "$url" ]] || return 1
    if favorites_find_url "$url" >/dev/null; then return 2; fi
    name="${name//$'\n'/ }"
    name="${name//$'\r'/ }"
    name="${name//|/-}"
    if [[ "$url" == *$'\n'* || "$url" == *$'\r'* || "$url" == *'|'* ]]; then return 1; fi
    FAVORITE_NAMES+=("$name")
    FAVORITE_URLS+=("$url")
    favorites_save_unlocked
}

favorites_add() {
    local name="$1" url="$2" lock_dir="${KEILA_FAVORITES_FILE}.lock"
    local -a previous_names=() previous_urls=()
    lock_acquire "$lock_dir" || return 1
    local status=0
    favorites_load || status=1
    if ((status == 0)); then
        previous_names=("${FAVORITE_NAMES[@]}")
        previous_urls=("${FAVORITE_URLS[@]}")
        favorites_add_unlocked "$name" "$url" || status=$?
        if ((status != 0)); then
            FAVORITE_NAMES=("${previous_names[@]}")
            FAVORITE_URLS=("${previous_urls[@]}")
        fi
    fi
    lock_release "$lock_dir" || status=1
    return "$status"
}

favorites_remove_index_unlocked() {
    local index="$1"
    [[ "$index" =~ ^[0-9]+$ ]] || return 1
    ((index >= 0 && index < ${#FAVORITE_NAMES[@]})) || return 1
    local -a new_names=() new_urls=()
    local i
    for ((i = 0; i < ${#FAVORITE_NAMES[@]}; i++)); do
        ((i == index)) && continue
        new_names+=("${FAVORITE_NAMES[$i]}")
        new_urls+=("${FAVORITE_URLS[$i]}")
    done
    FAVORITE_NAMES=("${new_names[@]}")
    FAVORITE_URLS=("${new_urls[@]}")
    favorites_save_unlocked
}

favorites_remove_index() {
    local index="$1"
    [[ "$index" =~ ^[0-9]+$ ]] || return 1
    ((index >= 0 && index < ${#FAVORITE_URLS[@]})) || return 1
    local target_url="${FAVORITE_URLS[$index]}"
    local lock_dir="${KEILA_FAVORITES_FILE}.lock"
    local -a previous_names=() previous_urls=()
    lock_acquire "$lock_dir" || return 1
    local status=0 current_index
    favorites_load || status=1
    if ((status == 0)); then
        previous_names=("${FAVORITE_NAMES[@]}")
        previous_urls=("${FAVORITE_URLS[@]}")
        if current_index=$(favorites_find_url "$target_url"); then
            favorites_remove_index_unlocked "$current_index" || status=$?
        else
            status=1
        fi
        if ((status != 0)); then
            FAVORITE_NAMES=("${previous_names[@]}")
            FAVORITE_URLS=("${previous_urls[@]}")
        fi
    fi
    lock_release "$lock_dir" || status=1
    return "$status"
}

favorites_move() {
    local index="$1" delta="$2"
    [[ "$index" =~ ^[0-9]+$ ]] || return 1
    ((index >= 0 && index < ${#FAVORITE_URLS[@]})) || return 1
    local target_url="${FAVORITE_URLS[$index]}"
    local lock_dir="${KEILA_FAVORITES_FILE}.lock"
    local -a previous_names=() previous_urls=()
    lock_acquire "$lock_dir" || return 1
    local status=0 current target tmp
    favorites_load || status=1
    if ((status == 0)); then
        previous_names=("${FAVORITE_NAMES[@]}")
        previous_urls=("${FAVORITE_URLS[@]}")
        if current=$(favorites_find_url "$target_url"); then
            target=$((current + delta))
            if ((target < 0 || target >= ${#FAVORITE_NAMES[@]})); then
                status=1
            else
                tmp="${FAVORITE_NAMES[current]}"
                FAVORITE_NAMES[current]="${FAVORITE_NAMES[target]}"
                FAVORITE_NAMES[target]="$tmp"
                tmp="${FAVORITE_URLS[current]}"
                FAVORITE_URLS[current]="${FAVORITE_URLS[target]}"
                FAVORITE_URLS[target]="$tmp"
                favorites_save_unlocked || status=$?
            fi
        else
            status=1
        fi
        if ((status != 0)); then
            FAVORITE_NAMES=("${previous_names[@]}")
            FAVORITE_URLS=("${previous_urls[@]}")
        fi
    fi
    lock_release "$lock_dir" || status=1
    return "$status"
}

favorites_toggle() {
    local name="$1" url="$2" lock_dir="${KEILA_FAVORITES_FILE}.lock"
    local -a previous_names=() previous_urls=()
    FAVORITES_TOGGLE_ACTION=''
    lock_acquire "$lock_dir" || return 1
    local status=0 index
    favorites_load || status=1
    if ((status == 0)); then
        previous_names=("${FAVORITE_NAMES[@]}")
        previous_urls=("${FAVORITE_URLS[@]}")
        if index=$(favorites_find_url "$url"); then
            if favorites_remove_index_unlocked "$index"; then FAVORITES_TOGGLE_ACTION="removed"; else status=1; fi
        else
            if favorites_add_unlocked "$name" "$url"; then FAVORITES_TOGGLE_ACTION="added"; else status=$?; fi
        fi
        if ((status != 0)); then
            FAVORITE_NAMES=("${previous_names[@]}")
            FAVORITE_URLS=("${previous_urls[@]}")
            FAVORITES_TOGGLE_ACTION=''
        fi
    fi
    lock_release "$lock_dir" || status=1
    return "$status"
}

# shellcheck source=lib/personal.sh
source "$(dirname "${BASH_SOURCE[0]}")/personal.sh"
