#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export XDG_CONFIG_HOME="$TMP_ROOT/config"
export XDG_STATE_HOME="$TMP_ROOT/state"
export XDG_CACHE_HOME="$TMP_ROOT/cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/keila-radio"

cat > "$XDG_CONFIG_HOME/keila-radio/config" <<EOF
recordings_dir=$TMP_ROOT/recordings
EOF

output=$("$ROOT_DIR/keila-radio" --check) || {
    printf 'FAIL smoke de inicialización\n' >&2
    exit 1
}

grep -q 'inicialización OK' <<< "$output" || {
    printf 'FAIL --check no confirmó inicialización\n' >&2
    exit 1
}
[[ -d "$TMP_ROOT/recordings" ]] || { printf 'FAIL no creó recordings_dir\n' >&2; exit 1; }
[[ -f "$XDG_CONFIG_HOME/keila-radio/favorites" ]] || { printf 'FAIL no inicializó favoritos\n' >&2; exit 1; }
printf 'ok   smoke de inicialización\n'

# Vacía la semilla para que el recuento concurrente sea inequívoco.
: > "$XDG_CONFIG_HOME/keila-radio/favorites"

worker_add() {
    local number="$1"
    (
        source "$ROOT_DIR/lib/config.sh"
        source "$ROOT_DIR/lib/lock.sh"
        source "$ROOT_DIR/lib/favorites.sh"
        favorites_load
        favorites_add "Radio $number" "https://example.invalid/$number"
    )
}

pids=()
for i in 1 2 3 4 5 6 7 8; do
    worker_add "$i" &
    pids+=("$!")
done

for pid in "${pids[@]}"; do
    wait "$pid" || { printf 'FAIL un escritor concurrente falló\n' >&2; exit 1; }
done

source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/lock.sh"
source "$ROOT_DIR/lib/favorites.sh"
favorites_load

[[ ${#FAVORITE_NAMES[@]} -eq 8 ]] || {
    printf 'FAIL concurrencia de favoritos: esperados 8, obtenidos %d\n' "${#FAVORITE_NAMES[@]}" >&2
    exit 1
}

unique=$(printf '%s\n' "${FAVORITE_URLS[@]}" | sort -u | wc -l)
[[ "$unique" -eq 8 ]] || { printf 'FAIL concurrencia produjo duplicados/pérdidas\n' >&2; exit 1; }
printf 'ok   locking concurrente de favoritos\n'

source "$ROOT_DIR/lib/state.sh"
STATE_VOLUME=73
STATE_LAST_NAME='Radio Estado'
STATE_LAST_URL='https://example.invalid/state'
state_save || { printf 'FAIL escritura de estado bloqueada\n' >&2; exit 1; }
state_load
[[ "$STATE_VOLUME" == 73 && "$STATE_LAST_NAME" == 'Radio Estado' ]] || {
    printf 'FAIL round-trip de estado con lock\n' >&2
    exit 1
}
[[ ! -d "${KEILA_STATE_FILE}.lock" ]] || { printf 'FAIL lock de estado no liberado\n' >&2; exit 1; }
printf 'ok   locking de estado\n'
