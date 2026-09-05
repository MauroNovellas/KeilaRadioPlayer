#!/usr/bin/env bash

# Grabación del stream que ya está reproduciendo mpv.
# Usa la opción runtime stream-record para no abrir una segunda conexión.

RECORDING_ACTIVE=0
RECORDING_FILE=""
RECORDINGS_DIR=""
RECORDING_STARTED_EPOCH=0
RECORDING_LAST_DISPLAY_SECOND=-1
RECORDING_LAST_VALID=0
RECORDING_LAST_SIZE=0
RECORDING_LAST_ERROR=""

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

recording_elapsed_seconds() {
    if ((!RECORDING_ACTIVE || RECORDING_STARTED_EPOCH <= 0)); then
        printf '0\n'
        return 0
    fi

    local now="${EPOCHSECONDS:-$(date +%s)}"
    local elapsed=$((now - RECORDING_STARTED_EPOCH))
    ((elapsed < 0)) && elapsed=0
    printf '%s\n' "$elapsed"
}

recording_elapsed_display() {
    local total
    total=$(recording_elapsed_seconds)

    local hours=$((total / 3600))
    local minutes=$(((total % 3600) / 60))
    local seconds=$((total % 60))

    printf '%02d:%02d:%02d' "$hours" "$minutes" "$seconds"
}

# Devuelve 0 solo cuando el segundo visible del contador ha cambiado.
recording_tick_changed() {
    ((RECORDING_ACTIVE)) || return 1

    local elapsed
    elapsed=$(recording_elapsed_seconds)

    if ((elapsed != RECORDING_LAST_DISPLAY_SECOND)); then
        RECORDING_LAST_DISPLAY_SECOND=$elapsed
        return 0
    fi

    return 1
}

recording_verify_file() {
    local file="${1:-$RECORDING_FILE}"

    RECORDING_LAST_VALID=0
    RECORDING_LAST_SIZE=0
    RECORDING_LAST_ERROR=""

    if [[ -z "$file" ]]; then
        RECORDING_LAST_ERROR="No hay una ruta de grabación para verificar."
        return 1
    fi

    # stream-record puede tardar unas décimas en cerrar y vaciar buffers.
    local attempt
    for ((attempt = 0; attempt < 10; attempt++)); do
        [[ -s "$file" ]] && break
        sleep 0.05
    done

    if [[ ! -f "$file" ]]; then
        RECORDING_LAST_ERROR="El archivo de grabación no existe."
        return 1
    fi

    local size
    size=$(stat -c %s "$file" 2>/dev/null || printf '0')
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    RECORDING_LAST_SIZE=$size

    if ((size <= 0)); then
        RECORDING_LAST_ERROR="El archivo de grabación está vacío."
        return 1
    fi

    RECORDING_LAST_VALID=1
    return 0
}

recording_size_human() {
    local bytes="${RECORDING_LAST_SIZE:-0}"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0

    if ((bytes >= 1073741824)); then
        local tenths=$((bytes * 10 / 1073741824))
        printf '%d.%d GiB' "$((tenths / 10))" "$((tenths % 10))"
    elif ((bytes >= 1048576)); then
        local tenths=$((bytes * 10 / 1048576))
        printf '%d.%d MiB' "$((tenths / 10))" "$((tenths % 10))"
    elif ((bytes >= 1024)); then
        local tenths=$((bytes * 10 / 1024))
        printf '%d.%d KiB' "$((tenths / 10))" "$((tenths % 10))"
    else
        printf '%d B' "$bytes"
    fi
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
    RECORDING_STARTED_EPOCH="${EPOCHSECONDS:-$(date +%s)}"
    RECORDING_LAST_DISPLAY_SECOND=0
    RECORDING_LAST_VALID=0
    RECORDING_LAST_SIZE=0
    RECORDING_LAST_ERROR=""
}

recording_stop() {
    ((RECORDING_ACTIVE)) || return 0

    local file="$RECORDING_FILE"
    local ipc_failed=0
    local payload

    if player_is_running; then
        payload=$(jq -cn '{command:["set_property","stream-record",""]}') || ipc_failed=1
        if ((ipc_failed == 0)); then
            player_ipc "$payload" || ipc_failed=1
        fi
    fi

    RECORDING_ACTIVE=0
    RECORDING_STARTED_EPOCH=0
    RECORDING_LAST_DISPLAY_SECOND=-1

    if recording_verify_file "$file"; then
        if ((ipc_failed)); then
            RECORDING_LAST_ERROR="mpv no confirmó el cierre, pero el archivo contiene datos."
        fi
        return 0
    fi

    return 1
}

# Se usa cuando mpv desaparece por su cuenta. Ya no hay IPC al que pedir cierre,
# pero podemos comprobar si el contenedor que dejó en disco contiene datos.
recording_finalize_after_player_exit() {
    ((RECORDING_ACTIVE)) || return 1

    local file="$RECORDING_FILE"
    RECORDING_ACTIVE=0
    RECORDING_STARTED_EPOCH=0
    RECORDING_LAST_DISPLAY_SECOND=-1

    recording_verify_file "$file"
}

recording_reset() {
    RECORDING_ACTIVE=0
    RECORDING_STARTED_EPOCH=0
    RECORDING_LAST_DISPLAY_SECOND=-1
}

recording_filename() {
    printf '%s' "${RECORDING_FILE##*/}"
}
