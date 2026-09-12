#!/usr/bin/env bash
# Gestor de pendientes. No reutiliza el reproductor de radio para las escuchas.
PENDING_FILES=()
PENDING_SCAN_PID='' PENDING_SCAN_DIR='' PENDING_PROBE_PID='' PENDING_PROBE_DIR=''
PENDING_PREVIEW_PID='' PENDING_RADIO_PID='' PENDING_RADIO_URL=''
PENDING_NOTICE='' PENDING_TARGET='' PENDING_SIGNATURE=''

pending_signature() {
    [[ -f "$1" && ! -L "$1" && ! -L "$1.pending" ]] || return 1
    stat -c '%d:%i:%s:%y:%z' -- "$1" || return 1
    if [[ -f "$1.pending" ]]; then stat -c '%d:%i:%s:%y:%z' -- "$1.pending"; else printf 'closed\n'; fi
}

pending_busy() {
    local file=$1 owner='' proc comm
    [[ "$file" == "${RECORDING_FILE:-}" && ${RECORDING_ACTIVE:-0} == 1 ]] && return 0
    [[ -e "$file.pending" ]] || return 1
    IFS= read -r owner < "$file.pending" || true
    [[ "$owner" == closed ]] && return 1
    if [[ "$owner" =~ ^[1-9][0-9]*$ ]]; then
        kill -0 "$owner" 2>/dev/null
        return
    fi
    # Marcadores antiguos vacíos: ser conservadores ante otros mpv activos.
    [[ -d /proc ]] || return 0
    for proc in /proc/[0-9]*/comm; do
        IFS= read -r comm < "$proc" 2>/dev/null || continue
        if [[ "$comm" == mpv && "${proc#/proc/}" != "${PLAYER_PID:-none}/comm" ]]; then return 0; fi
    done
    return 1
}

pending_stop_child() {
    local pid=${1:-} attempt
    [[ -n "$pid" ]] || return 0
    kill "$pid" 2>/dev/null || true
    for ((attempt=0; attempt<20; attempt++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
    done
    if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; fi
    wait "$pid" 2>/dev/null || true
}

pending_scan_start() {
    [[ -z "$PENDING_SCAN_PID" ]] || return 0
    PENDING_SCAN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keila-pending.XXXXXX") || return 1
    (
        trap - EXIT
        shopt -s nullglob
        for file in "$RECORDINGS_DIR"/*; do
            case "$file" in *.mp3|*.aac|*.ts|*.ogg|*.flac|*.wav|*.mka|*.mp4|*.m4a) : ;; *) continue ;; esac
            [[ -f "$file" && ! -L "$file" ]] || continue
            pending_busy "$file" && continue
            printf '%s\0' "$file"
        done > "$PENDING_SCAN_DIR/files"
        : > "$PENDING_SCAN_DIR/done"
    ) &
    PENDING_SCAN_PID=$!
}

pending_scan_poll() {
    [[ -n "$PENDING_SCAN_PID" && -f "$PENDING_SCAN_DIR/done" ]] || return 1
    wait "$PENDING_SCAN_PID" 2>/dev/null || true
    PENDING_SCAN_PID=''
    mapfile -d '' -t PENDING_FILES < "$PENDING_SCAN_DIR/files"
    rm -rf -- "$PENDING_SCAN_DIR"
    PENDING_SCAN_DIR=''
    local notice="${#PENDING_FILES[@]} grabaciones · ; abrir"
    if [[ -z "$PENDING_NOTICE" || "$PENDING_NOTICE" == Buscando* ]]; then PENDING_NOTICE=$notice; fi
    if ((${#PENDING_FILES[@]})); then app_message "$notice" 12; fi
    return 0
}

pending_preview_stop() {
    pending_stop_child "$PENDING_PREVIEW_PID"
    PENDING_PREVIEW_PID=''
    if [[ -n "$PENDING_RADIO_PID" && "$PENDING_RADIO_PID" == "${PLAYER_PID:-}" && "$PENDING_RADIO_URL" == "${PLAYER_URL:-}" ]] && ((${PLAYER_PAUSED:-0})); then
        player_toggle_pause || true
    fi
    PENDING_RADIO_PID='' PENDING_RADIO_URL=''
}

pending_preview_start() {
    local file=$1
    pending_signature "$file" >/dev/null && ! pending_busy "$file" || return 1
    ((${RECORDING_ACTIVE:-0} == 0)) || { PENDING_NOTICE='Detén la grabación antes de escuchar.'; return 1; }
    pending_preview_stop
    if player_is_running && ((${PLAYER_PAUSED:-0} == 0)); then
        player_toggle_pause || return 1
        PENDING_RADIO_PID=$PLAYER_PID PENDING_RADIO_URL=$PLAYER_URL
    fi
    local mute=no
    ((${PLAYER_MUTED:-0})) && mute=yes
    mpv --no-config --really-quiet --no-terminal --no-video --audio-display=no \
        --volume="${PLAYER_VOLUME:-50}" --mute="$mute" -- "$file" >/dev/null 2>&1 &
    PENDING_PREVIEW_PID=$!
    PENDING_NOTICE='Escuchando · E detiene · Esc vuelve'
}

pending_probe_start() {
    local file=$1
    [[ -z "$PENDING_PROBE_PID" ]] || return 1
    ! pending_busy "$file" || return 1
    PENDING_SIGNATURE=$(pending_signature "$file") || return 1
    PENDING_TARGET=$file
    PENDING_PROBE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keila-probe.XXXXXX") || return 1
    (
        trap - EXIT
        # El probe tiene su propio mpv; no tocar el de radio ni otras sesiones.
        local child=''
        trap 'for child in $(jobs -pr); do kill -KILL "$child" 2>/dev/null || true; done; exit 1' TERM INT
        status=0
        recording_probe_file "$file" || status=$?
        printf '%s\n' "$status" > "$PENDING_PROBE_DIR/result.tmp"
        mv -- "$PENDING_PROBE_DIR/result.tmp" "$PENDING_PROBE_DIR/result"
    ) &
    PENDING_PROBE_PID=$!
    PENDING_NOTICE='Comprobando audio… puedes seguir navegando.'
}

pending_probe_poll() {
    [[ -n "$PENDING_PROBE_PID" && -f "$PENDING_PROBE_DIR/result" ]] || return 1
    local result signature
    result=$(<"$PENDING_PROBE_DIR/result")
    wait "$PENDING_PROBE_PID" 2>/dev/null || true
    PENDING_PROBE_PID=''
    signature=$(pending_signature "$PENDING_TARGET") || signature=''
    PENDING_NOTICE='Dudosa: se conserva el audio y su marcador.'
    if [[ "$result" == 0 && -s "$PENDING_TARGET" && "$signature" == "$PENDING_SIGNATURE" ]] && ! pending_busy "$PENDING_TARGET"; then
        if [[ ! -e "$PENDING_TARGET.pending" ]] || rm -- "$PENDING_TARGET.pending"; then
            PENDING_NOTICE='Verificada y finalizada. Audio conservado.'
            pending_scan_start || true
        else
            PENDING_NOTICE='Audio verificado; no se pudo finalizar.'
        fi
    elif [[ "$signature" != "$PENDING_SIGNATURE" ]]; then
        PENDING_NOTICE='El archivo cambió; no se finaliza.'
    fi
    rm -rf -- "$PENDING_PROBE_DIR"
    PENDING_PROBE_DIR=''
    return 0
}

# Solo se llama después de confirmar la ruta y firma mostradas al usuario.
pending_trash() {
    local file=$1 expected=$2 signature destination
    [[ "${file%/*}" == "$RECORDINGS_DIR" ]] || return 1
    signature=$(pending_signature "$file") || return 1
    [[ "$signature" == "$expected" ]] && ! pending_busy "$file" || return 1
    [[ "$file" != "$PENDING_TARGET" || -z "$PENDING_PROBE_PID" ]] || return 1
    mkdir -p -- "$RECORDINGS_DIR/.trash" || return 1
    [[ ! -L "$RECORDINGS_DIR/.trash" ]] || return 1
    destination=$(mktemp -d "$RECORDINGS_DIR/.trash/recording.XXXXXX") || return 1
    mv -- "$file" "$destination/" || return 1
    if [[ -e "$file.pending" ]] && ! mv -- "$file.pending" "$destination/"; then
        PENDING_NOTICE="Audio en papelera; marcador no movido: $destination"
        return 1
    fi
    PENDING_NOTICE='Movida a .trash; se puede recuperar manualmente.'
    pending_scan_start || true
}

pending_cleanup() {
    pending_preview_stop
    pending_stop_child "$PENDING_PROBE_PID"
    pending_stop_child "$PENDING_SCAN_PID"
    PENDING_PROBE_PID='' PENDING_SCAN_PID=''
    [[ -z "$PENDING_PROBE_DIR" ]] || rm -rf -- "$PENDING_PROBE_DIR"
    [[ -z "$PENDING_SCAN_DIR" ]] || rm -rf -- "$PENDING_SCAN_DIR"
    PENDING_PROBE_DIR='' PENDING_SCAN_DIR=''
}

pending_build_panel() {
    local selected=$1 offset=$2 index file name state info size date size_label badge
    PANEL_ROWS=()
    for index in "${!PENDING_FILES[@]}"; do
        file=${PENDING_FILES[index]} name=${PENDING_FILES[index]##*/}
        state=Finalizada
        [[ ! -e "$file.pending" ]] || state=Pendiente
        info=${PENDING_METADATA[$file]:-}
        if [[ -z "$info" ]] && ((index == selected || (index >= offset && index < offset + UI_LINES))); then
            info=$(stat -c '%s|%y' -- "$file" 2>/dev/null) || info='?|No disponible'
            PENDING_METADATA[$file]=$info
        fi
        size=${info%%|*} date=${info#*|}
        size_label="${size:-?}B" badge=$state
        if [[ "$size" =~ ^[0-9]+$ ]]; then
            if ((size >= 1048576)); then size_label="$((size/1048576))MiB"
            elif ((size >= 1024)); then size_label="$((size/1024))KiB"; fi
            badge="${state:0:1} ${date:0:10} $size_label"
        fi
        panel_add_row '' "$name" "Archivo: $file. Fecha: ${date:0:16}. Tamaño: ${size:-?} B. Estado: $state. C comprueba y finaliza los verificados; E escucha o detiene; X prepara la eliminación a papelera. Enter confirma y Esc cancela." "$badge"
    done
    if ((${#PENDING_FILES[@]} == 0)); then
        if [[ -n "$PENDING_SCAN_PID" ]]; then
            panel_add_row '' 'Buscando grabaciones' 'La detección se hace en segundo plano. Puedes volver al reproductor mientras termina.'
        else
            panel_add_row '' 'No hay grabaciones guardadas' 'Para grabar una emisora, vuelve al reproductor y pulsa G. No se incluyen archivos que siguen en uso.'
        fi
    fi
}

pending_draw() {
    local selected=$1 offset=$2 confirm=${3:-} footer='C comprobar | E escuchar | X borrar | Esc volver'
    local -a PANEL_ROWS=()
    ui_refresh_size
    pending_build_panel "$selected" "$offset"
    [[ -z "$confirm" ]] || footer='Enter confirma | Esc cancela'
    panel_draw GRABACIONES "$selected" "$offset" "$footer" "$PENDING_NOTICE" "${#PENDING_FILES[@]} archivos | ${PENDING_PREVIEW_PID:+Escucha activa}"
}

app_pending_menu() {
    local selected=0 offset=0 file confirm='' signature='' redraw=1 event key selected_file index snapshot
    local previous_preferences=$PREFERENCES_ACTIVE
    local -A PENDING_METADATA=()
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    pending_scan_start || true
    PENDING_NOTICE='Buscando grabaciones...'
    PREFERENCES_ACTIVE=1
    while true; do
        if ((redraw)); then
            pending_draw "$selected" "$offset" "$confirm"
            selected=$PANEL_SELECTED offset=$PANEL_SCROLL
        fi
        input_read || break
        event=$INPUT_EVENT key=${INPUT_KEY,,} redraw=1
        if [[ "$event" == TICK ]]; then
            redraw=0
            panel_snapshot; snapshot=$PANEL_SNAPSHOT
            app_poll_player || true
            ui_message_tick || true
            catalog_poll || true
            selected_file=${PENDING_FILES[selected]:-}
            if pending_scan_poll; then
                redraw=1
                PENDING_METADATA=()
                for index in "${!PENDING_FILES[@]}"; do
                    if [[ ${PENDING_FILES[index]} == "$selected_file" ]]; then selected=$index; break; fi
                done
                if [[ -n "$confirm" ]]; then confirm=''; PENDING_NOTICE='Lista actualizada; confirma de nuevo.'; fi
            fi
            if pending_probe_poll; then redraw=1; PENDING_METADATA=(); fi
            if [[ -n "$PENDING_RADIO_PID" && "$PENDING_RADIO_PID" != "${PLAYER_PID:-}" ]]; then
                pending_preview_stop; PENDING_NOTICE='Escucha detenida por cambio de reproducción.'; redraw=1
            fi
            if [[ -n "$PENDING_PREVIEW_PID" ]] && ! kill -0 "$PENDING_PREVIEW_PID" 2>/dev/null; then
                local preview_status=0
                wait "$PENDING_PREVIEW_PID" 2>/dev/null || preview_status=$?
                PENDING_PREVIEW_PID=''
                pending_preview_stop
                if ((preview_status)); then PENDING_NOTICE='No se pudo reproducir el archivo.'; else PENDING_NOTICE='Escucha terminada.'; fi
                redraw=1
            fi
            panel_snapshot
            [[ "$snapshot" == "$PANEL_SNAPSHOT" ]] || redraw=1
            continue
        fi
        [[ "$event" != RESIZE ]] || continue
        if [[ -n "$confirm" ]]; then
            if [[ "$event" == ENTER ]]; then
                pending_preview_stop
                PENDING_NOTICE='No se eliminó: archivo ocupado, cambiado o error.'
                pending_trash "$confirm" "$signature" || true
            else PENDING_NOTICE='Eliminación cancelada.'; fi
            confirm=''
            continue
        fi
        file=${PENDING_FILES[selected]:-}
        case "$event" in
            ESC|LEFT) break ;;
            UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                panel_move "$event" "$selected" "${#PENDING_FILES[@]}" "$PANEL_VISIBLE"
                selected=$PANEL_SELECTED ;;
            ENTER)
                local -a PANEL_ROWS=()
                pending_build_panel "$selected" "$offset"
                panel_detail GRABACIONES "$selected" ;;
            KEY)
                [[ -n "$file" ]] || continue
                case "$key" in
                    '?')
                        local -a PANEL_ROWS=()
                        pending_build_panel "$selected" "$offset"
                        panel_detail GRABACIONES "$selected" ;;
                    c) pending_probe_start "$file" || PENDING_NOTICE='No se puede comprobar: archivo ocupado.' ;;
                    e) if [[ -n "$PENDING_PREVIEW_PID" ]]; then pending_preview_stop; PENDING_NOTICE='Escucha detenida.'; else pending_preview_start "$file" || PENDING_NOTICE='No se puede escuchar: archivo ocupado.'; fi ;;
                    x) signature=$(pending_signature "$file") || continue
                       confirm=$file; PENDING_NOTICE='¿Mover selección a papelera? Enter sí; otra tecla no.' ;;
                esac ;;
        esac
    done
    pending_preview_stop
    # No finalizar archivos a espaldas del usuario al salir del panel.
    pending_stop_child "$PENDING_PROBE_PID"
    PENDING_PROBE_PID=''
    [[ -z "$PENDING_PROBE_DIR" ]] || rm -rf -- "$PENDING_PROBE_DIR"
    PENDING_PROBE_DIR=''
    PREFERENCES_ACTIVE=$previous_preferences
    ((previous_preferences)) || ui_draw
    return 0
}
