#!/usr/bin/env bash

# Núcleo de reproducción de Keila Radio Player v2.
# Este archivo está pensado para ser cargado con `source`.

PLAYER_PID=""
PLAYER_NAME=""
PLAYER_URL=""
PLAYER_VOLUME="${KEILA_VOLUME:-50}"
PLAYER_PAUSED=0

# Información real del stream obtenida desde mpv por JSON IPC.
PLAYER_STREAM_TITLE=""
PLAYER_CODEC=""
PLAYER_BITRATE_KBPS=""
PLAYER_SAMPLE_RATE=""
PLAYER_CHANNELS=""
PLAYER_BUFFERING=0
PLAYER_INFO_READY=0
PLAYER_INFO_LAST_REFRESH=0
PLAYER_INFO_INTERVAL="${KEILA_PLAYER_INFO_INTERVAL:-1}"

if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    PLAYER_RUNTIME_DIR="$XDG_RUNTIME_DIR/keila-radio"
else
    PLAYER_RUNTIME_DIR="${TMPDIR:-/tmp}/keila-radio-${UID:-$(id -u)}"
fi

PLAYER_SOCKET="$PLAYER_RUNTIME_DIR/mpv.sock"

player_require_dependencies() {
    local missing=0
    local dep

    for dep in mpv socat jq; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            printf 'Falta la dependencia: %s\n' "$dep" >&2
            missing=1
        fi
    done

    if ((missing)); then
        printf 'En Debian puedes instalarlas con: sudo apt install mpv socat jq\n' >&2
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

player_reset_info() {
    PLAYER_STREAM_TITLE=""
    PLAYER_CODEC=""
    PLAYER_BITRATE_KBPS=""
    PLAYER_SAMPLE_RATE=""
    PLAYER_CHANNELS=""
    PLAYER_BUFFERING=0
    PLAYER_INFO_READY=0
    PLAYER_INFO_LAST_REFRESH=0
}

# Consulta varias propiedades en una única conexión IPC. Además del objeto
# metadata pedimos directamente campos ICY y media-title porque algunos streams
# actualizan esos valores durante la reproducción sin reflejarlos igual en todos
# los demuxers/versiones de mpv.
player_query_snapshot() {
    [[ -S "$PLAYER_SOCKET" ]] || return 1

    {
        printf '%s\n' '{"command":["get_property","metadata"],"request_id":1}'
        printf '%s\n' '{"command":["get_property","current-tracks/audio/codec"],"request_id":2}'
        printf '%s\n' '{"command":["get_property","audio-bitrate"],"request_id":3}'
        printf '%s\n' '{"command":["get_property","audio-params"],"request_id":4}'
        printf '%s\n' '{"command":["get_property","paused-for-cache"],"request_id":5}'
        printf '%s\n' '{"command":["get_property","metadata/by-key/icy-title"],"request_id":6}'
        printf '%s\n' '{"command":["get_property","metadata/by-key/StreamTitle"],"request_id":7}'
        printf '%s\n' '{"command":["get_property","metadata/by-key/title"],"request_id":8}'
        printf '%s\n' '{"command":["get_property","media-title"],"request_id":9}'
    } | socat -t 1 - UNIX-CONNECT:"$PLAYER_SOCKET" 2>/dev/null |
        jq -cs '
            reduce .[] as $response ({};
                if ($response.error == "success" and $response.request_id != null) then
                    .[($response.request_id | tostring)] = $response.data
                else
                    .
                end
            )
        '
}

# Actualiza la información técnica como máximo una vez por segundo. Devuelve 0
# únicamente cuando algo visible ha cambiado, para evitar redibujados inútiles.
player_refresh_info() {
    player_is_running || return 1

    local now="${EPOCHSECONDS:-$(date +%s)}"
    [[ "$PLAYER_INFO_INTERVAL" =~ ^[0-9]+$ ]] || PLAYER_INFO_INTERVAL=1
    ((PLAYER_INFO_INTERVAL < 1)) && PLAYER_INFO_INTERVAL=1

    if ((PLAYER_INFO_LAST_REFRESH > 0 && now - PLAYER_INFO_LAST_REFRESH < PLAYER_INFO_INTERVAL)); then
        return 1
    fi
    PLAYER_INFO_LAST_REFRESH=$now

    local snapshot
    snapshot=$(player_query_snapshot) || return 1
    [[ -n "$snapshot" ]] || return 1

    local -a fields=()
    mapfile -t fields < <(
        jq -r '
            def clean:
                (if . == null then ""
                 elif type == "string" then .
                 else tostring
                 end)
                | gsub("[\\r\\n\\t]+"; " ")
                | gsub("^ +| +$"; "");

            def metadata_value($names):
                (. ["1"] // {}) as $metadata
                | if ($metadata | type) == "object" then
                    ($metadata
                        | to_entries
                        | map(select(
                            (.key | ascii_downcase) as $key
                            | ($names | index($key)) != null
                        ))
                        | .[0].value // "")
                  else ""
                  end;

            def stream_title:
                [
                    .["6"],
                    .["7"],
                    metadata_value(["icy-title", "streamtitle", "stream-title", "now-playing", "now_playing"]),
                    .["8"],
                    metadata_value(["title"]),
                    .["9"]
                ]
                | map(clean | select(length > 0))
                | .[0] // "";

            stream_title,
            ((.["2"] // "") | clean),
            ((.["3"] // 0) | if type == "number" and . > 0 then ((. / 1000) | round | tostring) else "" end),
            ((.["4"].samplerate // "") | if type == "number" then tostring else . end),
            ((.["4"]["hr-channels"] // .["4"].channels // "") | clean),
            ((.["5"] // false) | if . == true then "1" else "0" end)
        ' <<< "$snapshot"
    )

    local new_title="${fields[0]:-}"
    local new_codec="${fields[1]:-}"
    local new_bitrate="${fields[2]:-}"
    local new_samplerate="${fields[3]:-}"
    local new_channels="${fields[4]:-}"
    local new_buffering="${fields[5]:-0}"
    local new_ready=0

    if [[ -n "$new_codec" || -n "$new_bitrate" || "$new_samplerate" =~ ^[1-9][0-9]*$ ]]; then
        new_ready=1
    fi

    # media-title puede caer al nombre/URL del stream si no hay metadatos de la
    # canción. No mostramos ese fallback como si fuese el tema en emisión.
    case "$new_title" in
        ""|"$PLAYER_NAME"|"$PLAYER_URL"|http://*|https://*)
            new_title=""
            ;;
    esac

    local old_state
    old_state="$PLAYER_STREAM_TITLE|$PLAYER_CODEC|$PLAYER_BITRATE_KBPS|$PLAYER_SAMPLE_RATE|$PLAYER_CHANNELS|$PLAYER_BUFFERING|$PLAYER_INFO_READY"
    local new_state
    new_state="$new_title|$new_codec|$new_bitrate|$new_samplerate|$new_channels|$new_buffering|$new_ready"

    PLAYER_STREAM_TITLE="$new_title"
    PLAYER_CODEC="$new_codec"
    PLAYER_BITRATE_KBPS="$new_bitrate"
    PLAYER_SAMPLE_RATE="$new_samplerate"
    PLAYER_CHANNELS="$new_channels"
    PLAYER_BUFFERING="$new_buffering"
    PLAYER_INFO_READY="$new_ready"

    [[ "$old_state" != "$new_state" ]]
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
    player_reset_info

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
    player_reset_info
    rm -f "$PLAYER_SOCKET"
}
