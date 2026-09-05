#!/usr/bin/env bash

# Núcleo de reproducción de Keila Radio Player v2.
# Este archivo está pensado para ser cargado con `source`.

PLAYER_PID=""
PLAYER_NAME=""
PLAYER_URL=""
PLAYER_VOLUME="${KEILA_VOLUME:-50}"
PLAYER_PAUSED=0

if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    PLAYER_RUNTIME_DIR="$XDG_RUNTIME_DIR/keila-radio"
else
    PLAYER_RUNTIME_DIR="${TMPDIR:-/tmp}/keila-radio-${UID:-$(id -u)}"
fi

PLAYER_SOCKET="$PLAYER_RUNTIME_DIR/mpv.sock"

player_require_dependencies() {
    local missing=0
    local dep

    for dep in mpv socat; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            printf 'Falta la dependencia: %s\n' "$dep" >&2
            missing=1
        fi
    done

    if ((missing)); then
        printf 'En Debian puedes instalarlas con: sudo apt install mpv socat\n' >&2
        return 1
    fi
}

player_is_running() {
    [[ -n "$PLAYER_PID" ]] && kill -0 "$PLAYER_PID" 2>/dev/null
}

player_ipc() {
    local payload="$1"

    [[ -S "$PLAYER_SOCKET" ]] || return 1
    printf '%s\n' "$payload" | socat -t 1 - UNIX-CONNECT:"$PLAYER_SOCKET" >/dev/null 2>&1
}

player_wait_for_socket() {
    local attempt

    for ((attempt = 0; attempt < 60; attempt++)); do
        [[ -S "$PLAYER_SOCKET" ]] && return 0
        player_is_running || return 1
        sleep 0.05
    done

    return 1
}

player_start() {
    local name="$1"
    local url="$2"

    [[ -n "$url" ]] || {
        printf 'La URL de la emisora está vacía.\n' >&2
        return 1
    }

    player_stop >/dev/null 2>&1 || true

    mkdir -p "$PLAYER_RUNTIME_DIR"
    chmod 700 "$PLAYER_RUNTIME_DIR" 2>/dev/null || true
    rm -f "$PLAYER_SOCKET"

    PLAYER_NAME="$name"
    PLAYER_URL="$url"
    PLAYER_PAUSED=0

    mpv \
        --really-quiet \
        --no-video \
        --no-terminal \
        --audio-display=no \
        --input-ipc-server="$PLAYER_SOCKET" \
        --volume="$PLAYER_VOLUME" \
        "$PLAYER_URL" \
        >/dev/null 2>&1 &

    PLAYER_PID=$!

    if ! player_wait_for_socket; then
        printf 'mpv terminó antes de crear el socket IPC.\n' >&2
        player_stop >/dev/null 2>&1 || true
        return 1
    fi
}

player_toggle_pause() {
    player_is_running || return 1

    if ! player_ipc '{"command":["cycle","pause"]}'; then
        return 1
    fi

    if ((PLAYER_PAUSED)); then
        PLAYER_PAUSED=0
    else
        PLAYER_PAUSED=1
    fi
}

player_set_volume() {
    local volume="$1"

    [[ "$volume" =~ ^[0-9]+$ ]] || return 1
    ((volume < 0)) && volume=0
    ((volume > 100)) && volume=100

    PLAYER_VOLUME="$volume"

    if player_is_running; then
        player_ipc "{\"command\":[\"set_property\",\"volume\",$PLAYER_VOLUME]}" || return 1
    fi
}

player_change_volume() {
    local delta="$1"
    local next=$((PLAYER_VOLUME + delta))

    ((next < 0)) && next=0
    ((next > 100)) && next=100

    player_set_volume "$next"
}

player_stop() {
    if player_is_running; then
        player_ipc '{"command":["quit"]}' >/dev/null 2>&1 || true

        local attempt
        for ((attempt = 0; attempt < 20; attempt++)); do
            player_is_running || break
            sleep 0.05
        done

        if player_is_running; then
            kill "$PLAYER_PID" 2>/dev/null || true
            wait "$PLAYER_PID" 2>/dev/null || true
        fi
    fi

    PLAYER_PID=""
    PLAYER_PAUSED=0
    rm -f "$PLAYER_SOCKET"
}
