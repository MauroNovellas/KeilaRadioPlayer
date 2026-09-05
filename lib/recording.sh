#!/usr/bin/env bash

# Grabación del stream que ya está reproduciendo mpv.
# Usa la opción runtime stream-record para no abrir una segunda conexión.

RECORDING_ACTIVE=0
RECORDING_FILE=""
RECORDINGS_DIR=""

recording_init() {
    RECORDINGS_DIR="$1"
    mkdir -p "$RECORDINGS_DIR"
}

recording_sanitize_name() {
    local name="$1"
    local safe

    safe=$(printf '%s' "$name" |
        sed -E 's#[/\\:*?"<>|]#_#g; s/[[:space:]]+/_/g; s/_+/_/g; s/^[_ .-]+//; s/[_ .-]+$//')

    [[ -n "$safe" ]] || safe='emisora'
    printf '%s' "$safe"
}

recording_next_file() {
    local station_name="$1"
    local safe timestamp base file counter

    [[ -n "$RECORDINGS_DIR" ]] || return 1
    mkdir -p "$RECORDINGS_DIR" || return 1

    safe=$(recording_sanitize_name "$station_name")
    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    base="$RECORDINGS_DIR/${safe}_${timestamp}"
    file="${base}.mka"
    counter=2

    # No sobreescribimos una grabación si por casualidad se inicia otra en el
    # mismo segundo con el mismo nombre de emisora.
    while [[ -e "$file" ]]; do
        file="${base}_${counter}.mka"
        ((counter += 1))
    done

    printf '%s' "$file"
}

recording_start() {
    local station_name="$1"

    player_is_running || return 1
    ((RECORDING_ACTIVE)) && return 0

    local file payload
    file=$(recording_next_file "$station_name") || return 1
    payload=$(jq -cn --arg path "$file" '{command:["set_property","stream-record",$path]}') || return 1

    player_ipc "$payload" || return 1

    RECORDING_ACTIVE=1
    RECORDING_FILE="$file"
}

recording_stop() {
    ((RECORDING_ACTIVE)) || return 0

    local status=0 payload
    payload=$(jq -cn '{command:["set_property","stream-record",""]}') || status=1

    if ((status == 0)) && player_is_running; then
        player_ipc "$payload" || status=1
    fi

    # Aunque mpv haya terminado por su cuenta, nuestro estado debe quedar limpio.
    RECORDING_ACTIVE=0
    return "$status"
}

recording_reset() {
    RECORDING_ACTIVE=0
}

recording_filename() {
    printf '%s' "${RECORDING_FILE##*/}"
}
