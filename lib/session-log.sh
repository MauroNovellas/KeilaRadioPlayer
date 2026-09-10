#!/usr/bin/env bash

# Registro local de la sesión y memoria visual de canciones recientes.
#
# El historial de emisoras recientes vive en personal.sh. Este módulo registra
# títulos de canciones/programas emitidos por la emisora actual y escribe un
# archivo de texto privado por sesión interactiva.

SESSION_LOG_DIR=''
SESSION_LOG_FILE=''
SESSION_LOG_CLOSED=0
SESSION_LOG_LAST_URL=''
SESSION_LOG_LAST_TITLE=''

TRACK_HISTORY_URL=''
TRACK_HISTORY_STATION=''
TRACK_HISTORY_STATION_LOGGED=0
TRACK_HISTORY_TITLES=()
TRACK_HISTORY_TIMES=()

session_log_now() {
    date '+%Y-%m-%d %H:%M:%S'
}

session_log_clock() {
    date '+%H:%M:%S'
}

session_log_text() {
    local text="$1" max="${2:-180}"

    text="${text//[[:cntrl:]]/ }"
    text="${text//$'\t'/ }"
    text="${text//|/-}"
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    printf '%s' "${text:0:max}"
}

session_log_truncate() {
    local text="$1" max="$2"

    if ((max <= 0)); then
        printf ''
    elif ((${#text} <= max)); then
        printf '%s' "$text"
    elif ((max <= 3)); then
        printf '%s' "${text:0:max}"
    else
        printf '%s...' "${text:0:max-3}"
    fi
}

session_log_init() {
    local stamp id

    SESSION_LOG_DIR="$KEILA_STATE_DIR/sessions"
    mkdir -p "$SESSION_LOG_DIR" || return 1
    chmod 700 "$SESSION_LOG_DIR" 2>/dev/null || true

    stamp=$(date '+%Y-%m-%d_%H-%M-%S')
    id="${KEILA_INSTANCE_ID:-${BASHPID:-$$}}"
    id="${id//[^A-Za-z0-9_.-]/_}"
    SESSION_LOG_FILE="$SESSION_LOG_DIR/keila-session-${stamp}-${id}.txt"

    {
        printf '# Keila Radio Player session\n'
        printf '# Started: %s\n' "$(session_log_now)"
        printf '# Format: fecha y hora<TAB>emisora<TAB>canción o evento\n'
    } > "$SESSION_LOG_FILE" || {
        SESSION_LOG_FILE=''
        return 1
    }
    chmod 600 "$SESSION_LOG_FILE" 2>/dev/null || true
    SESSION_LOG_CLOSED=0
    SESSION_LOG_LAST_URL=''
    SESSION_LOG_LAST_TITLE=''
}

session_log_append() {
    local station="$1" title="$2"

    [[ -n "${SESSION_LOG_FILE:-}" ]] || return 0
    [[ -f "$SESSION_LOG_FILE" && ! -L "$SESSION_LOG_FILE" ]] || return 1

    station=$(session_log_text "$station")
    title=$(session_log_text "$title" 240)
    [[ -n "$station" ]] || station='(emisora desconocida)'
    [[ -n "$title" ]] || title='(sin título)'

    printf '%s\t%s\t%s\n' "$(session_log_now)" "$station" "$title" >> "$SESSION_LOG_FILE"
}

session_log_station() {
    local station="$1" url="$2"

    [[ -n "${SESSION_LOG_FILE:-}" ]] || return 0
    station=$(session_log_text "$station")
    [[ -n "$station" ]] || station='(emisora desconocida)'
    SESSION_LOG_LAST_URL="$url"
    SESSION_LOG_LAST_TITLE=''
    session_log_append "$station" '(sintonizada)'
}

session_log_title() {
    local station="$1" url="$2" title="$3"

    [[ -n "$title" ]] || return 1
    title=$(session_log_text "$title" 240)
    [[ -n "$title" ]] || return 1

    if [[ "${SESSION_LOG_LAST_URL:-}" == "$url" && "${SESSION_LOG_LAST_TITLE:-}" == "$title" ]]; then
        return 1
    fi

    SESSION_LOG_LAST_URL="$url"
    SESSION_LOG_LAST_TITLE="$title"
    session_log_append "$station" "$title" || return 1
}

session_log_close() {
    ((SESSION_LOG_CLOSED)) && return 0
    [[ -n "${SESSION_LOG_FILE:-}" && -f "$SESSION_LOG_FILE" && ! -L "$SESSION_LOG_FILE" ]] || return 0
    {
        printf '# Ended: %s\n' "$(session_log_now)"
    } >> "$SESSION_LOG_FILE" 2>/dev/null || true
    SESSION_LOG_CLOSED=1
}

track_history_start_station() {
    local station="$1" url="$2"

    TRACK_HISTORY_URL="$url"
    TRACK_HISTORY_STATION=$(session_log_text "$station")
    TRACK_HISTORY_STATION_LOGGED=0
    TRACK_HISTORY_TITLES=()
    TRACK_HISTORY_TIMES=()
}

track_history_ensure_station_logged() {
    local station="$1" url="$2"

    [[ -n "$url" ]] || return 1
    ((${PLAYER_STREAM_READY:-0})) || return 1

    if [[ "$url" != "${TRACK_HISTORY_URL:-}" ]]; then
        TRACK_HISTORY_URL="$url"
        TRACK_HISTORY_STATION=$(session_log_text "$station")
        TRACK_HISTORY_STATION_LOGGED=0
        TRACK_HISTORY_TITLES=()
        TRACK_HISTORY_TIMES=()
    fi

    ((TRACK_HISTORY_STATION_LOGGED == 0)) || return 1
    TRACK_HISTORY_STATION_LOGGED=1
    session_log_station "$station" "$url" || true
    return 0
}

track_history_observe() {
    local station="${PLAYER_NAME:-}" url="${PLAYER_URL:-}" title="${PLAYER_STREAM_TITLE:-}" now last

    [[ -n "$url" ]] || return 1
    ((${PLAYER_STREAM_READY:-0})) || return 1
    track_history_ensure_station_logged "$station" "$url" >/dev/null 2>&1 || true

    [[ -n "$title" ]] || return 1
    title=$(session_log_text "$title" 240)
    [[ -n "$title" ]] || return 1

    [[ "${TRACK_HISTORY_TITLES[0]:-}" != "$title" ]] || return 1

    now=$(session_log_clock)
    TRACK_HISTORY_TITLES=("$title" "${TRACK_HISTORY_TITLES[@]}")
    TRACK_HISTORY_TIMES=("$now" "${TRACK_HISTORY_TIMES[@]}")

    while ((${#TRACK_HISTORY_TITLES[@]} > 4)); do
        last=$((${#TRACK_HISTORY_TITLES[@]} - 1))
        unset "TRACK_HISTORY_TITLES[$last]"
        last=$((${#TRACK_HISTORY_TIMES[@]} - 1))
        unset "TRACK_HISTORY_TIMES[$last]"
        TRACK_HISTORY_TITLES=("${TRACK_HISTORY_TITLES[@]}")
        TRACK_HISTORY_TIMES=("${TRACK_HISTORY_TIMES[@]}")
    done

    session_log_title "$station" "$url" "$title" || true
    return 0
}

track_history_visible_count() {
    local count=$((${#TRACK_HISTORY_TITLES[@]} - 1))
    ((count < 0)) && count=0
    ((count > 3)) && count=3
    printf '%s\n' "$count"
}

track_history_summary() {
    local width="${1:-80}" count available sep=' · ' sep_total each output title i

    count=$(track_history_visible_count)
    ((count > 0)) || return 1
    [[ "$width" =~ ^[0-9]+$ ]] || width=80

    output='  Anteriores: '
    available=$((width - ${#output}))
    ((available >= 8)) || return 1
    sep_total=$(((count - 1) * ${#sep}))
    each=$(((available - sep_total) / count))
    ((each < 4)) && each=4

    for ((i = 1; i <= count; i++)); do
        ((i > 1)) && output+="$sep"
        title="${TRACK_HISTORY_TITLES[i]:-}"
        output+="$(session_log_truncate "$title" "$each")"
    done

    printf '%s' "$output"
}
