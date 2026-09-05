#!/usr/bin/env bash

# Mutex portables basados en mkdir. mkdir sobre un directorio inexistente es
# atómico, así que sirve para serializar escrituras sin depender de `flock`.

KEILA_LOCK_ATTEMPTS="${KEILA_LOCK_ATTEMPTS:-40}"
KEILA_LOCK_SLEEP="${KEILA_LOCK_SLEEP:-0.05}"

lock_pid() {
    printf '%s' "${BASHPID:-$$}"
}

lock_acquire() {
    local lock_dir="$1"
    local attempt owner self
    self=$(lock_pid)

    mkdir -p "$(dirname "$lock_dir")" || return 1

    for ((attempt = 0; attempt < KEILA_LOCK_ATTEMPTS; attempt++)); do
        if mkdir "$lock_dir" 2>/dev/null; then
            printf '%s\n' "$self" > "$lock_dir/pid" 2>/dev/null || {
                rmdir "$lock_dir" 2>/dev/null || true
                return 1
            }
            return 0
        fi

        owner=""
        if [[ -r "$lock_dir/pid" ]]; then
            IFS= read -r owner < "$lock_dir/pid" || true
        fi

        if [[ "$owner" =~ ^[0-9]+$ ]] && ! kill -0 "$owner" 2>/dev/null; then
            rm -rf "$lock_dir" 2>/dev/null || true
            continue
        fi

        sleep "$KEILA_LOCK_SLEEP"
    done

    return 1
}

lock_release() {
    local lock_dir="$1"
    local owner="" self
    self=$(lock_pid)

    [[ -d "$lock_dir" ]] || return 0
    if [[ -r "$lock_dir/pid" ]]; then
        IFS= read -r owner < "$lock_dir/pid" || true
    fi

    if [[ -z "$owner" || "$owner" == "$self" ]]; then
        rm -rf "$lock_dir" 2>/dev/null || return 1
    fi
}
