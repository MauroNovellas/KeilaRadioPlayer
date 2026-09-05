#!/usr/bin/env bash

# Mutex portables basados en mkdir. mkdir sobre un directorio inexistente es
# atómico, así que sirve para serializar escrituras sin depender de `flock`.

KEILA_LOCK_ATTEMPTS="${KEILA_LOCK_ATTEMPTS:-40}"
KEILA_LOCK_SLEEP="${KEILA_LOCK_SLEEP:-0.05}"

lock_pid() {
    printf '%s' "${BASHPID:-$$}"
}

# Aparta un lock antiguo mediante rename atómico antes de borrarlo. Al borrar
# una ruta distinta nunca podemos llevarnos por delante un lock nuevo (ABA).
lock_retire() {
    local lock_dir="$1"
    local tag="$2"
    local retired="${lock_dir}.${tag}.$(lock_pid)"

    rm -rf "$retired" 2>/dev/null || true
    if mv "$lock_dir" "$retired" 2>/dev/null; then
        rm -rf "$retired" 2>/dev/null || true
        return 0
    fi
    return 1
}

lock_acquire() {
    local lock_dir="$1"
    local attempt owner self
    self=$(lock_pid)

    mkdir -p "$(dirname "$lock_dir")" || return 1

    for ((attempt = 0; attempt < KEILA_LOCK_ATTEMPTS; attempt++)); do
        if mkdir "$lock_dir" 2>/dev/null; then
            if printf '%s\n' "$self" > "$lock_dir/pid" 2>/dev/null; then
                return 0
            fi
            lock_retire "$lock_dir" 'broken' >/dev/null 2>&1 || true
            return 1
        fi

        owner=""
        if [[ -r "$lock_dir/pid" ]]; then
            IFS= read -r owner < "$lock_dir/pid" || true
        fi

        if [[ "$owner" =~ ^[0-9]+$ ]] && ! kill -0 "$owner" 2>/dev/null; then
            lock_retire "$lock_dir" 'stale' >/dev/null 2>&1 || true
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

    [[ "$owner" == "$self" ]] || return 1
    lock_retire "$lock_dir" 'released'
}
