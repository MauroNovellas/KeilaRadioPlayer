#!/usr/bin/env bash
# Biblioteca de grabaciones. El listado nunca decodifica audio.
PENDING_FILES=()
PENDING_SCAN_PID='' PENDING_SCAN_DIR='' PENDING_PROBE_PID='' PENDING_PROBE_DIR=''
PENDING_NOTICE='' PENDING_TARGET='' PENDING_SIGNATURE=''
PENDING_SCAN_GENERATION=0 PENDING_SUMMARY='' PENDING_SCAN_DEADLINE=0 PENDING_SCAN_AGAIN=0
declare -A PENDING_METADATA=() PENDING_STATES=() PENDING_DOUBTFUL=()
# shellcheck source=lib/recording-preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/recording-preview.sh"

pending_signature() {
    [[ -f "$1" && ! -L "$1" && ! -L "$1.pending" ]] || return 1
    [[ ! -e "$1.pending" || -f "$1.pending" ]] || return 1
    stat -c '%d:%i:%s:%y:%z' -- "$1" || return 1
    if [[ -f "$1.pending" ]]; then stat -c '%d:%i:%s:%y:%z' -- "$1.pending"; else printf 'closed\n'; fi
}

pending_busy() {
    local file=$1 owner='' proc comm
    [[ "$file" == "${RECORDING_FILE:-}" && ${RECORDING_ACTIVE:-0} == 1 ]] && return 0
    [[ -e "$file.pending" || -L "$file.pending" ]] || return 1
    [[ -f "$file.pending" && ! -L "$file.pending" ]] || return 0
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
    [[ -z "$PENDING_SCAN_PID" ]] || { PENDING_SCAN_AGAIN=1; return 0; }
    PENDING_SCAN_AGAIN=0
    PENDING_SCAN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keila-pending.XXXXXX") || return 1
    PENDING_SCAN_DEADLINE=$((EPOCHSECONDS+30))
    (
        trap - EXIT
        shopt -s nullglob
        local file info state status=0 signature
        for file in "$RECORDINGS_DIR"/*; do
            case "${file,,}" in *.mp3|*.aac|*.ts|*.ogg|*.flac|*.wav|*.mka|*.mp4|*.m4a|*.opus) : ;; *) continue ;; esac
            [[ -f "$file" && ! -L "$file" ]] || continue
            info=$(stat -c $'%Y\t%s\t%y' -- "$file") || continue
            state=Finalizada
            [[ ! -e "$file.pending" ]] || state=Pendiente
            [[ -s "$file" ]] || state=Vacía
            if [[ -n "${PENDING_DOUBTFUL[$file]:-}" ]]; then
                signature=$(pending_signature "$file") || signature=''
                [[ "$signature" != "${PENDING_DOUBTFUL[$file]}" ]] || state=Dudosa
            fi
            if pending_busy "$file"; then state='En curso'; fi
            if [[ -L "$file.pending" || ( -e "$file.pending" && ! -f "$file.pending" ) || ! -r "$file" ]]; then state='No disponible'; fi
            printf '%s\t%s\t%s\0' "$info" "$state" "$file"
        done > "$PENDING_SCAN_DIR/unsorted" || status=1
        LC_ALL=C sort -z -s -t $'\t' -k1,1nr "$PENDING_SCAN_DIR/unsorted" > "$PENDING_SCAN_DIR/files" || status=1
        printf '%s\n' "$status" > "$PENDING_SCAN_DIR/done"
    ) 2> "$PENDING_SCAN_DIR/error.log" &
    PENDING_SCAN_PID=$!
}

pending_scan_poll() {
    [[ -n "$PENDING_SCAN_PID" ]] || return 1
    if [[ ! -f "$PENDING_SCAN_DIR/done" ]]; then
        if ((EPOCHSECONDS < PENDING_SCAN_DEADLINE)) && kill -0 "$PENDING_SCAN_PID" 2>/dev/null; then return 1; fi
        pending_stop_child "$PENDING_SCAN_PID"
    fi
    wait "$PENDING_SCAN_PID" 2>/dev/null || true
    PENDING_SCAN_PID=''
    if [[ ! -f "$PENDING_SCAN_DIR/done" || $(<"$PENDING_SCAN_DIR/done") != 0 ]]; then
        PENDING_NOTICE='No se pudo actualizar la lista. Se conserva la anterior; U reintenta.'
        rm -rf -- "$PENDING_SCAN_DIR"; PENDING_SCAN_DIR=''
        return 0
    fi
    local row rest file size date state finished=0 pending=0 active=0 doubtful=0
    PENDING_FILES=() PENDING_METADATA=() PENDING_STATES=()
    while IFS= read -r -d '' row; do
        rest=${row#*$'\t'}; size=${rest%%$'\t'*}; rest=${rest#*$'\t'}
        date=${rest%%$'\t'*}; rest=${rest#*$'\t'}
        state=${rest%%$'\t'*}; file=${rest#*$'\t'}
        PENDING_FILES+=("$file") PENDING_METADATA[$file]="$size|$date" PENDING_STATES[$file]=$state
        case "$state" in
            Finalizada) ((finished+=1)) ;; Pendiente) ((pending+=1)) ;;
            'En curso') ((active+=1)) ;; *) ((doubtful+=1)) ;;
        esac
    done < "$PENDING_SCAN_DIR/files"
    ((PENDING_SCAN_GENERATION+=1))
    PENDING_SUMMARY="$finished finalizadas | $pending pendientes | $active en curso | $doubtful por revisar"
    rm -rf -- "$PENDING_SCAN_DIR"
    PENDING_SCAN_DIR=''
    local notice="${#PENDING_FILES[@]} grabaciones · Más recientes primero · U actualiza"
    if [[ -z "$PENDING_NOTICE" || "$PENDING_NOTICE" == Buscando* ]]; then PENDING_NOTICE=$notice; fi
    if ((${#PENDING_FILES[@]})); then app_message "${#PENDING_FILES[@]} grabaciones · ; abrir" 12; fi
    ((PENDING_SCAN_AGAIN == 0)) || pending_scan_start || true
    return 0
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
    if [[ -n "$signature" && "$signature" == "$PENDING_SIGNATURE" ]]; then
        PENDING_DOUBTFUL[$PENDING_TARGET]=$signature
        PENDING_STATES[$PENDING_TARGET]=Dudosa
    fi
    if [[ "$result" == 0 && -s "$PENDING_TARGET" && "$signature" == "$PENDING_SIGNATURE" ]] && ! pending_busy "$PENDING_TARGET"; then
        if [[ ! -e "$PENDING_TARGET.pending" ]] || rm -- "$PENDING_TARGET.pending"; then
            PENDING_NOTICE='Verificada y finalizada. Audio conservado.'
            unset 'PENDING_DOUBTFUL[$PENDING_TARGET]'
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
    PENDING_PROBE_PID='' PENDING_SCAN_PID='' PENDING_SCAN_AGAIN=0
    [[ -z "$PENDING_PROBE_DIR" ]] || rm -rf -- "$PENDING_PROBE_DIR"
    [[ -z "$PENDING_SCAN_DIR" ]] || rm -rf -- "$PENDING_SCAN_DIR"
    PENDING_PROBE_DIR='' PENDING_SCAN_DIR=''
}

pending_build_panel() {
    local selected=$1 offset=$2 index file name state info size date size_label badge
    PANEL_ROWS=()
    for index in "${!PENDING_FILES[@]}"; do
        file=${PENDING_FILES[index]} name=${PENDING_FILES[index]##*/}
        state=${PENDING_STATES[$file]:-Finalizada}
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
            badge="$state $size_label"
            if ((UI_COLS >= 80)); then printf -v badge '%-13s %-10s %7s' "$state" "${date:0:10}" "$size_label"; fi
        fi
        local reason=''
        case "$state" in 'En curso'|'No disponible') reason='No se puede escuchar, comprobar ni borrar mientras esté ocupado o no sea accesible.' ;; esac
        panel_add_row '' "$name" "Archivo: $file. Fecha de modificación: ${date:0:16}. Tamaño: ${size:-?} B. Estado: $state. Finalizada significa sin cierre pendiente; C comprueba el audio. E abre la escucha con pausa y saltos de 10 segundos. X prepara el traslado a papelera, con confirmación. U actualiza la lista." "$badge" "$reason"
    done
    if ((${#PENDING_FILES[@]} == 0)); then
        if [[ -n "$PENDING_SCAN_PID" ]]; then
            panel_add_row '' 'Buscando grabaciones' 'La detección se hace en segundo plano. Puedes volver al reproductor mientras termina.'
        else
            panel_add_row '' 'No hay grabaciones guardadas' "Para grabar una emisora, vuelve al reproductor y pulsa G. Carpeta: $RECORDINGS_DIR. U vuelve a buscar."
        fi
    fi
}

pending_draw() {
    local selected=$1 offset=$2 confirm=${3:-} footer='E escuchar | C comprobar | U actualizar | X papelera | Esc volver'
    local -a PANEL_ROWS=()
    # Una biblioteca necesita ancho para nombre + estado/fecha/tamaño. Conserva
    # el marco común y el detalle inferior; no estrecharla con un segundo panel.
    local PANEL_FULL_WIDTH=1 PANEL_BADGE_MAX_WIDTH=0
    ui_refresh_size
    ((UI_COLS < 80)) || PANEL_BADGE_MAX_WIDTH=32
    pending_build_panel "$selected" "$offset"
    [[ -z "$confirm" ]] || footer='Enter confirma | Esc cancela'
    panel_draw GRABACIONES "$selected" "$offset" "$footer" "$PENDING_NOTICE" "${PENDING_SUMMARY:-${#PENDING_FILES[@]} archivos}"
}

app_pending_menu() {
    local selected=0 offset=0 file confirm='' signature='' redraw=1 event key selected_file=${PENDING_FILES[0]:-} index snapshot
    local generation=$PENDING_SCAN_GENERATION
    local previous_preferences=$PREFERENCES_ACTIVE
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    pending_scan_start || true
    PENDING_NOTICE='Buscando grabaciones...'
    PREFERENCES_ACTIVE=1
    while true; do
        if ((generation != PENDING_SCAN_GENERATION)); then
            generation=$PENDING_SCAN_GENERATION
            for index in "${!PENDING_FILES[@]}"; do
                if [[ ${PENDING_FILES[index]} == "$selected_file" ]]; then selected=$index; break; fi
            done
            if [[ -n "$confirm" ]]; then confirm=''; PENDING_NOTICE='Lista actualizada; confirma de nuevo.'; fi
            redraw=1
        fi
        if ((redraw)); then
            pending_draw "$selected" "$offset" "$confirm"
            selected=$PANEL_SELECTED offset=$PANEL_SCROLL
        fi
        selected_file=${PENDING_FILES[selected]:-}
        input_read || break
        event=$INPUT_EVENT key=${INPUT_KEY,,} redraw=1
        if [[ "$event" == TICK ]]; then
            redraw=0
            panel_snapshot; snapshot=$PANEL_SNAPSHOT
            app_poll_player || true
            ui_message_tick || true
            catalog_poll || true
            pending_scan_poll && redraw=1
            pending_probe_poll && redraw=1
            pending_preview_poll && redraw=1
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
                if [[ "$key" == u ]]; then pending_scan_start || true; PENDING_NOTICE='Buscando grabaciones...'; continue; fi
                [[ -n "$file" ]] || continue
                case "$key" in
                    '?')
                        local -a PANEL_ROWS=()
                        pending_build_panel "$selected" "$offset"
                        panel_detail GRABACIONES "$selected" ;;
                    c) pending_probe_start "$file" || PENDING_NOTICE='No se puede comprobar: archivo ocupado.' ;;
                    e) app_recording_preview "$file" || true ;;
                    x) signature=$(pending_signature "$file") || { PENDING_NOTICE='Archivo no disponible; U actualiza la lista.'; continue; }
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
