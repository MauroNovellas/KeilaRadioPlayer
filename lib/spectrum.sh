#!/usr/bin/env bash

# Analizador de espectro real sobre el monitor de salida PulseAudio/PipeWire.
# No abre una segunda conexión a la emisora y se degrada de forma limpia cuando
# el sistema no expone un monitor compatible (por ejemplo, algunos Termux).
SPECTRUM_ENABLED=1
SPECTRUM_AVAILABLE='unknown'
SPECTRUM_PID=''
SPECTRUM_DIR=''
SPECTRUM_SOURCE=''
SPECTRUM_FOUND_SOURCE=''
SPECTRUM_ERROR=''
SPECTRUM_NOTICE_PENDING=0
SPECTRUM_FRAME_ROWS=16
SPECTRUM_LEVELS=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)

spectrum_find_source() {
    SPECTRUM_FOUND_SOURCE=''
    command -v ffmpeg >/dev/null 2>&1 || { SPECTRUM_ERROR='Falta ffmpeg.'; return 1; }
    command -v pactl >/dev/null 2>&1 || { SPECTRUM_ERROR='Falta pactl.'; return 1; }
    command -v timeout >/dev/null 2>&1 || { SPECTRUM_ERROR='Falta timeout (coreutils).'; return 1; }
    command -v stdbuf >/dev/null 2>&1 || { SPECTRUM_ERROR='Falta stdbuf (coreutils).'; return 1; }

    local sink source sources fallback
    sink=$(timeout 1 pactl get-default-sink 2>/dev/null) || sink=''
    if [[ -z "$sink" ]]; then
        sink=$(timeout 1 pactl info 2>/dev/null | awk -F ': ' '$1 == "Default Sink" { print $2; exit }')
    fi
    [[ -n "$sink" ]] || { SPECTRUM_ERROR='PulseAudio/PipeWire no informó de una salida predeterminada.'; return 1; }
    source="${sink}.monitor"
    sources=$(timeout 1 pactl list short sources 2>/dev/null) || {
        SPECTRUM_ERROR='No se pudo consultar los monitores de salida.'
        return 1
    }
    if ! awk -v wanted="$source" '$2 == wanted { found=1 } END { exit !found }' <<< "$sources"; then
        fallback=$(awk '$2 ~ /\.monitor$/ { print $2; exit }' <<< "$sources")
        [[ -n "$fallback" ]] || { SPECTRUM_ERROR='No existe ningún monitor de salida de audio.'; return 1; }
        source=$fallback
    fi
    SPECTRUM_FOUND_SOURCE=$source
}

spectrum_worker_stop() {
    local child
    for child in $(jobs -pr); do kill "$child" 2>/dev/null || true; done
    wait
    exit 0
}

# El monitor de audio es auxiliar y nunca debe bloquear la entrada de la TUI.
# Cerramos primero sus hijos y acotamos la espera antes de forzar la salida.
spectrum_terminate_bounded() {
    local pid="$1" attempt
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || { wait "$pid" 2>/dev/null || true; return 0; }

    if command -v pkill >/dev/null 2>&1; then
        pkill -TERM -P "$pid" 2>/dev/null || true
    fi
    kill -TERM "$pid" 2>/dev/null || true
    for ((attempt=0; attempt<10; attempt++)); do
        kill -0 "$pid" 2>/dev/null || { wait "$pid" 2>/dev/null || true; return 0; }
        sleep 0.05
    done

    if command -v pkill >/dev/null 2>&1; then
        pkill -KILL -P "$pid" 2>/dev/null || true
    fi
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

spectrum_start() {
    ((SPECTRUM_ENABLED)) || return 1
    [[ -z "$SPECTRUM_PID" ]] || return 0

    if [[ -z "$SPECTRUM_SOURCE" ]]; then
        spectrum_find_source || {
            SPECTRUM_AVAILABLE='no'
            return 1
        }
        SPECTRUM_SOURCE=$SPECTRUM_FOUND_SOURCE
    fi

    mkdir -p "$PLAYER_RUNTIME_DIR" || return 1
    SPECTRUM_DIR=$(mktemp -d "${PLAYER_RUNTIME_DIR}/spectrum.XXXXXX") || return 1
    SPECTRUM_AVAILABLE='yes'
    SPECTRUM_ERROR=''
    (
        trap spectrum_worker_stop TERM INT
        if command -v parec >/dev/null 2>&1; then
            parec --device="$SPECTRUM_SOURCE" --format=s16le --rate=44100 --channels=1 2>/dev/null |
                ffmpeg -hide_banner -loglevel error -probesize 32 -analyzeduration 0 -f s16le -ar 44100 -ac 1 -i - \
                    -lavfi 'showfreqs=s=16x16:rate=20:mode=bar:ascale=cbrt:fscale=log:win_size=1024:overlap=0.5:colors=white' \
                    -r 20 -f rawvideo -pix_fmt gray -flush_packets 1 - 2>/dev/null
        else
            ffmpeg -hide_banner -loglevel error \
                -f pulse -i "$SPECTRUM_SOURCE" \
                -lavfi 'showfreqs=s=16x16:rate=20:mode=bar:ascale=cbrt:fscale=log:win_size=1024:overlap=0.5:colors=white' \
                -r 20 -f rawvideo -pix_fmt gray -flush_packets 1 - 2>/dev/null
        fi |
            stdbuf -oL od -An -tu1 -w16 -v |
            spectrum_publish_frames
    ) </dev/null >/dev/null 2>&1 &
    SPECTRUM_PID=$!
}

# Procesamos cada fila al recibirla: od con salida por líneas y read de Bash
# evitan el buffering de entrada de awk sobre un flujo que nunca termina.
spectrum_publish_frames() {
    local row=0 i
    local -a pixels heights=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
    while read -r -a pixels; do
        (("${#pixels[@]}" == 16)) || return 1
        for ((i=0; i<16; i++)); do
            if ((pixels[i] > 20)); then heights[i]=$((heights[i] + 1)); fi
        done
        row=$((row + 1))
        if ((row == SPECTRUM_FRAME_ROWS)); then
            printf '%s\n' "${heights[*]}" > "$SPECTRUM_DIR/levels.tmp" || return 1
            mv -f "$SPECTRUM_DIR/levels.tmp" "$SPECTRUM_DIR/levels" || return 1
            heights=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
            row=0
        fi
    done
}

spectrum_stop() {
    if [[ -n "$SPECTRUM_PID" ]]; then
        spectrum_terminate_bounded "$SPECTRUM_PID" || true
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
        spectrum_start || {
            SPECTRUM_NOTICE_PENDING=1
            return 0
        }
        return 0
    fi
    if ! kill -0 "$SPECTRUM_PID" 2>/dev/null; then
        spectrum_stop
        SPECTRUM_AVAILABLE='no'
        SPECTRUM_ERROR='La captura de audio del analizador se detuvo.'
        SPECTRUM_NOTICE_PENDING=1
        return 0
    fi

    local file="$SPECTRUM_DIR/levels" raw values i changed=1
    [[ -s "$file" ]] || return 1
    IFS= read -r raw < "$file" || return 1
    IFS=' ' read -r -a values <<< "$raw"
    ((${#values[@]} == 16)) || return 1
    for ((i=0; i<16; i++)); do
        [[ "${values[i]}" =~ ^[0-9]+$ ]] && ((values[i] >= 0 && values[i] <= SPECTRUM_FRAME_ROWS)) || return 1
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
    SPECTRUM_ERROR=''
    SPECTRUM_NOTICE_PENDING=0
    if player_is_running && ((PLAYER_STREAM_READY && !PLAYER_PAUSED)); then
        spectrum_start || return 2
    fi
    return 0
}
