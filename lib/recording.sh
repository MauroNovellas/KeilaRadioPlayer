#!/usr/bin/env bash

# Grabación del stream que ya está reproduciendo mpv.
# Usa la opción runtime stream-record para no abrir una segunda conexión.

RECORDING_ACTIVE=0
RECORDING_FILE=""
RECORDINGS_DIR=""
RECORDING_STARTED_EPOCH=0
RECORDING_LAST_DISPLAY_SECOND=-1
RECORDING_LAST_VALID=0
RECORDING_LAST_VERIFIED=0
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

# mpv/FFmpeg suele necesitar que stream-record escriba un formato compatible
# con el stream de entrada. Forzar siempre Matroska puede producir archivos de
# 0 bytes, especialmente con HLS. Esta función elige una extensión conservadora
# a partir del demuxer, la URL y, como último recurso, el codec de audio.
recording_extension_for_stream() {
    local format="${1:-}"
    local codec="${2:-}"
    local url="${3:-}"
    local clean_url

    format="${format,,}"
    codec="${codec,,}"
    clean_url="${url%%#*}"
    clean_url="${clean_url%%\?*}"
    clean_url="${clean_url,,}"

    case "$format" in
        hls|mpegts|mpeg-ts)
            printf 'ts'
            return 0
            ;;
        mp3)
            printf 'mp3'
            return 0
            ;;
        aac|adts)
            printf 'aac'
            return 0
            ;;
        ogg|oga|opus)
            printf 'ogg'
            return 0
            ;;
        flac)
            printf 'flac'
            return 0
            ;;
        wav|wave)
            printf 'wav'
            return 0
            ;;
        matroska|webm)
            printf 'mka'
            return 0
            ;;
    esac

    case "$clean_url" in
        *.m3u8|*.m3u)
            printf 'ts'
            return 0
            ;;
        *.mp3)
            printf 'mp3'
            return 0
            ;;
        *.aac)
            printf 'aac'
            return 0
            ;;
        *.ogg|*.oga|*.opus)
            printf 'ogg'
            return 0
            ;;
        *.flac)
            printf 'flac'
            return 0
            ;;
        *.wav)
            printf 'wav'
            return 0
            ;;
    esac

    case "$codec" in
        mp3)
            printf 'mp3'
            ;;
        aac|aac_*|*aac*)
            printf 'aac'
            ;;
        opus|vorbis)
            printf 'ogg'
            ;;
        flac)
            printf 'flac'
            ;;
        *)
            # La mayoría de radios sin extensión visible que llegan por HLS
            # pueden almacenarse de forma segura como MPEG-TS.
            printf 'ts'
            ;;
    esac
}

# Pregunta a mpv qué demuxer/formato está usando para la entrada actual.
# Si la consulta falla, recording_extension_for_stream todavía puede decidir
# usando la URL o el codec ya conocido por la TUI.
recording_stream_format() {
    [[ -S "${PLAYER_SOCKET:-}" ]] || return 1

    local response
    response=$(
        printf '%s\n' '{"command":["get_property","file-format"],"request_id":71}' |
            socat -t 1 - UNIX-CONNECT:"$PLAYER_SOCKET" 2>/dev/null
    ) || return 1

    jq -r 'select(.request_id == 71 and .error == "success") | .data // empty' <<< "$response" |
        head -n 1
}

recording_next_file() {
    local station_name="$1"
    local extension="${2:-mka}"
    local safe timestamp base file counter

    [[ -n "$RECORDINGS_DIR" ]] || return 1
    mkdir -p "$RECORDINGS_DIR" || return 1

    [[ "$extension" =~ ^[a-z0-9]+$ ]] || extension='ts'

    safe=$(recording_sanitize_name "$station_name")
    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    base="$RECORDINGS_DIR/${safe}_${timestamp}"
    file="${base}.${extension}"
    counter=2

    # No sobreescribimos una grabación si por casualidad se inicia otra en el
    # mismo segundo con el mismo nombre de emisora.
    while [[ -e "$file" ]]; do
        file="${base}_${counter}.${extension}"
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

# Comprueba que mpv puede abrir y reproducir brevemente el archivo recién
# cerrado. El probe usa salida nula y está acotado: nunca debe convertir una
# validación de grabación en un bloqueo indefinido.
#
# Retornos:
#   0  mpv confirmó que el archivo es reproducible
#   1  mpv terminó indicando que no pudo reproducirlo
#   2  no se pudo completar el probe de forma fiable (mpv ausente/timeout)
recording_probe_file() {
    local file="$1"
    local pid attempt status=0

    command -v mpv >/dev/null 2>&1 || return 2

    mpv \
        --no-config \
        --really-quiet \
        --no-terminal \
        --no-video \
        --audio-display=no \
        --ao=null \
        --length=0.20 \
        -- "$file" \
        >/dev/null 2>&1 &
    pid=$!

    # Archivo local: dos segundos son margen amplio y evitan cualquier espera
    # patológica ante un contenedor dañado.
    for ((attempt = 0; attempt < 40; attempt++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null || status=$?
            ((status == 0)) && return 0
            return 1
        fi
        sleep 0.05
    done

    kill "$pid" 2>/dev/null || true
    for ((attempt = 0; attempt < 10; attempt++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
    return 2
}

recording_verify_file() {
    local file="${1:-$RECORDING_FILE}"

    RECORDING_LAST_VALID=0
    RECORDING_LAST_VERIFIED=0
    RECORDING_LAST_SIZE=0
    RECORDING_LAST_ERROR=""

    if [[ -z "$file" ]]; then
        RECORDING_LAST_ERROR="No hay una ruta de grabación para verificar."
        return 1
    fi

    # Algunos muxers tardan algo más en cerrar cabeceras/buffers. Damos hasta
    # 1,5 s antes de considerar el archivo realmente vacío.
    local attempt
    for ((attempt = 0; attempt < 30; attempt++)); do
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

    # Un archivo con datos nunca se descarta solo porque el probe sea demasiado
    # estricto para un formato raro. El tamaño permite conservarlo; el probe
    # añade un segundo nivel de confianza que la UI puede comunicar al usuario.
    RECORDING_LAST_VALID=1

    local probe_status=0
    recording_probe_file "$file" || probe_status=$?
    case "$probe_status" in
        0)
            RECORDING_LAST_VERIFIED=1
            return 0
            ;;
        1)
            RECORDING_LAST_ERROR="El archivo contiene datos, pero mpv no pudo confirmar audio reproducible."
            return 0
            ;;
        *)
            RECORDING_LAST_ERROR="El archivo contiene datos, pero no se pudo completar la verificación de reproducción."
            return 0
            ;;
    esac
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

    local stream_format extension file payload
    stream_format=$(recording_stream_format 2>/dev/null || true)
    extension=$(recording_extension_for_stream "$stream_format" "${PLAYER_CODEC:-}" "${PLAYER_URL:-}")

    file=$(recording_next_file "$station_name" "$extension") || return 1
    payload=$(jq -cn --arg path "$file" '{command:["set_property","stream-record",$path]}') || return 1

    player_ipc "$payload" || return 1

    RECORDING_ACTIVE=1
    RECORDING_FILE="$file"
    RECORDING_STARTED_EPOCH="${EPOCHSECONDS:-$(date +%s)}"
    RECORDING_LAST_DISPLAY_SECOND=0
    RECORDING_LAST_VALID=0
    RECORDING_LAST_VERIFIED=0
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
            if ((RECORDING_LAST_VERIFIED)); then
                RECORDING_LAST_ERROR="mpv no confirmó el cierre, pero el archivo fue verificado y contiene audio reproducible."
            elif [[ -z "$RECORDING_LAST_ERROR" ]]; then
                RECORDING_LAST_ERROR="mpv no confirmó el cierre, pero el archivo contiene datos."
            fi
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
    RECORDING_LAST_VALID=0
    RECORDING_LAST_VERIFIED=0
}

recording_filename() {
    printf '%s' "${RECORDING_FILE##*/}"
}
