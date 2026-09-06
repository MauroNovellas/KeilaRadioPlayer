#!/usr/bin/env bash

# Analizador de espectro real sobre el monitor de salida PulseAudio/PipeWire.
# No abre una segunda conexión a la emisora y se degrada de forma limpia cuando
# el sistema no expone un monitor compatible (por ejemplo, algunos Termux).
SPECTRUM_ENABLED=1
SPECTRUM_AVAILABLE='unknown'
SPECTRUM_PID=''
SPECTRUM_DIR=''
SPECTRUM_SOURCE=''
SPECTRUM_LEVELS=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)

spectrum_find_source() {
    command -v ffmpeg >/dev/null 2>&1 || return 1
    command -v pactl >/dev/null 2>&1 || return 1

    local sink source
    sink=$(pactl get-default-sink 2>/dev/null) || sink=''
    if [[ -z "$sink" ]]; then
        sink=$(pactl info 2>/dev/null | awk -F ': ' '$1 == "Default Sink" { print $2; exit }')
    fi
    [[ -n "$sink" ]] || return 1
    source="${sink}.monitor"
    pactl list short sources 2>/dev/null | awk -v wanted="$source" '$2 == wanted { found=1 } END { exit !found }' || return 1
    printf '%s\n' "$source"
}

spectrum_worker_stop() {
    local child
    for child in $(jobs -pr); do kill "$child" 2>/dev/null || true; done
    wait
    exit 0
}

spectrum_start() {
    ((SPECTRUM_ENABLED)) || return 1
    [[ -z "$SPECTRUM_PID" ]] || return 0

    if [[ -z "$SPECTRUM_SOURCE" ]]; then
        SPECTRUM_SOURCE=$(spectrum_find_source) || {
            SPECTRUM_AVAILABLE='no'
            return 1
        }
    fi

    mkdir -p "$PLAYER_RUNTIME_DIR" || return 1
    SPECTRUM_DIR=$(mktemp -d "${PLAYER_RUNTIME_DIR}/spectrum.XXXXXX") || return 1
    SPECTRUM_AVAILABLE='yes'
    (
        trap spectrum_worker_stop TERM INT
        ffmpeg -hide_banner -loglevel error \
            -f pulse -i "$SPECTRUM_SOURCE" \
            -lavfi 'showfreqs=s=16x8:mode=bar:ascale=cbrt:fscale=log:colors=white' \
            -r 10 -f rawvideo -pix_fmt gray - 2>/dev/null |
            od -An -tu1 -w16 -v |
            awk '
                {
                    row=(NR-1)%8
                    for (i=1; i<=16; i++) if ($i>20) height[i]++
                    if (row==7) {
                        for (i=1; i<=16; i++) printf "%d%s", height[i], (i==16 ? ORS : " ")
                        fflush()
                        delete height
                    }
                }
            ' |
            while IFS= read -r levels; do
                printf '%s\n' "$levels" > "$SPECTRUM_DIR/levels.tmp" || exit 1
                mv -f "$SPECTRUM_DIR/levels.tmp" "$SPECTRUM_DIR/levels" || exit 1
            done
    ) </dev/null >/dev/null 2>&1 &
    SPECTRUM_PID=$!
}

spectrum_stop() {
    if [[ -n "$SPECTRUM_PID" ]]; then
        kill "$SPECTRUM_PID" 2>/dev/null || true
        wait "$SPECTRUM_PID" 2>/dev/null || true
    fi
    SPECTRUM_PID=''
    if [[ -n "$SPECTRUM_DIR" && -d "$SPECTRUM_DIR" ]]; then
        rm -rf -- "${SPECTRUM_DIR:?}"
    fi
    SPECTRUM_DIR=''
    SPECTRUM_LEVELS=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
}

spectrum_tick() {
    if ((!SPECTRUM_ENABLED)) || ! player_is_running || ((PLAYER_PAUSED || !PLAYER_STREAM_READY)); then
        [[ -z "$SPECTRUM_PID" ]] || { spectrum_stop; return 0; }
        return 1
    fi

    if [[ -z "$SPECTRUM_PID" ]]; then
        [[ "$SPECTRUM_AVAILABLE" != no ]] || return 1
        spectrum_start || return 1
        return 0
    fi
    if ! kill -0 "$SPECTRUM_PID" 2>/dev/null; then
        spectrum_stop
        SPECTRUM_AVAILABLE='no'
        return 0
    fi

    local file="$SPECTRUM_DIR/levels" raw values i changed=1
    [[ -s "$file" ]] || return 1
    IFS= read -r raw < "$file" || return 1
    IFS=' ' read -r -a values <<< "$raw"
    ((${#values[@]} == 16)) || return 1
    for ((i=0; i<16; i++)); do
        [[ "${values[i]}" =~ ^[0-8]$ ]] || return 1
        if [[ "${SPECTRUM_LEVELS[i]}" != "${values[i]}" ]]; then changed=0; fi
    done
    SPECTRUM_LEVELS=("${values[@]}")
    return "$changed"
}

spectrum_toggle() {
    if ((SPECTRUM_ENABLED)); then
        SPECTRUM_ENABLED=0
        spectrum_stop
        return 0
    fi
    SPECTRUM_ENABLED=1
    SPECTRUM_AVAILABLE='unknown'
    SPECTRUM_SOURCE=''
    if player_is_running && ((PLAYER_STREAM_READY && !PLAYER_PAUSED)); then
        spectrum_start || return 2
    fi
    return 0
}
