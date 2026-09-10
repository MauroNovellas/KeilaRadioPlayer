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

app_pending_menu() {
    local selected=0 offset=0 width height row file name date size confirm='' signature='' redraw=1 event key selected_file index
    pending_scan_start || true
    PENDING_NOTICE='Buscando pendientes…'
    PREFERENCES_ACTIVE=1
    while true; do
        if ((redraw)); then
            ui_refresh_size
            width=$((UI_COLS-1)); ((width<1)) && width=1
            height=$(((UI_LINES-5)/2)); ((height<1)) && height=1
            ((selected>=${#PENDING_FILES[@]})) && selected=$((${#PENDING_FILES[@]}-1))
            ((selected<0)) && selected=0
            ((selected<offset)) && offset=$selected
            ((selected>=offset+height)) && offset=$((selected-height+1))
            tput cup 0 0 2>/dev/null || true
            ui_print_styled_padded "$width" 'GRABACIONES' title; printf '\n'
            for ((row=offset; row<offset+height && row<${#PENDING_FILES[@]}; row++)); do
                file=${PENDING_FILES[row]} name=${PENDING_FILES[row]##*/}
                name=${name//[[:cntrl:]]/ }
                local mark='  ' state='Finalizada'; ((row==selected)) && mark='> '
                [[ -e "$file.pending" ]] && state='Pendiente'
                ui_print_styled_padded "$width" "$mark$name" accent; printf '\n'
                date=$(stat -c '%y' -- "$file" 2>/dev/null) || date='no disponible'
                size=$(stat -c '%s' -- "$file" 2>/dev/null) || size='?'
                ui_print_padded "$width" "${date:0:16} · $size B · $state"; printf '\n'
            done
            if ((${#PENDING_FILES[@]}==0)); then ui_print_padded "$width" 'Sin pendientes / buscando…'; printf '\n'; fi
            ui_print_padded "$width" 'C comprobar · E escuchar/parar · X borrar'; printf '\n'
            ui_print_padded "$width" '↑↓ navegar · Esc volver'; printf '\n'
            ui_print_padded "$width" "$PENDING_NOTICE"
            tput ed 2>/dev/null || true
        fi
        input_read || break
        event=$INPUT_EVENT key=${INPUT_KEY,,} redraw=1
        if [[ "$event" == TICK ]]; then
            redraw=0
            app_poll_player || true
            ui_message_tick || true
            catalog_poll || true
            selected_file=${PENDING_FILES[selected]:-}
            if pending_scan_poll; then
                redraw=1
                for index in "${!PENDING_FILES[@]}"; do
                    if [[ ${PENDING_FILES[index]} == "$selected_file" ]]; then selected=$index; break; fi
                done
                if [[ -n "$confirm" ]]; then confirm=''; PENDING_NOTICE='Lista actualizada; confirma de nuevo.'; fi
            fi
            pending_probe_poll && redraw=1
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
            continue
        fi
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
            ESC) break ;;
            UP) ((selected>0)) && ((selected-=1)) ;;
            DOWN) ((selected+1<${#PENDING_FILES[@]})) && ((selected+=1)) ;;
            HOME) selected=0 ;;
            END) selected=$((${#PENDING_FILES[@]}-1)) ;;
            KEY)
                [[ -n "$file" ]] || continue
                case "$key" in
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
    PREFERENCES_ACTIVE=0
    ui_draw
}
