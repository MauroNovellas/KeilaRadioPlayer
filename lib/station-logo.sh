#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck source=lib/station-logo-worker.sh
source "$(dirname "${BASH_SOURCE[0]}")/station-logo-worker.sh"
LOGO_WORKER="$(dirname "${BASH_SOURCE[0]}")/station-logo-worker.sh"
LOGO_PID='' LOGO_JOB='' LOGO_REQUEST='' LOGO_READY_URL='' LOGO_BACKEND=initials
LOGO_PIXELS_BASE64='' LOGO_PIXELS_HEX='' LOGO_GENERATION=0 LOGO_UPLOADED=-1 LOGO_DRAWN=0
LOGO_IMAGE_ID=$((100000+$$)) LOGO_CHECK_AT=0 LOGO_CATALOG_GENERATION=0
LOGO_STATUS='Desactivado' UI_LOGO_LAYOUT=0
LOGO_SIXEL_BODY='' LOGO_SIXEL_SIDE=0 LOGO_DRAW_COLUMN=0 LOGO_DRAW_BACKEND=''
LOGO_DRAW_KEY='' UI_LOGO_PRESERVE=0
LOGO_CELL_QUERY_KEY='' LOGO_CELL_QUERY_UNTIL=0 LOGO_QUERY_CHANGED=0
LOGO_SIXEL_FAILED_KEY=''
LOGO_JOB_MODE=''
declare -a LOGO_ROWS=()

logo_platform_allowed() {
    [[ -z ${TERMUX_VERSION:-} && ${PREFIX:-} != *com.termux* && ${TERM:-dumb} != dumb ]]
}

logo_choose_backend() {
    LOGO_BACKEND=initials
    logo_platform_allowed || return 0
    [[ -t 1 ]] || return 0
    ((${UI_COLOR:-0})) || return 0
    if [[ ${TERM:-} == xterm-kitty && ${KITTY_WINDOW_ID:-} =~ ^[0-9]+$ && -z ${TMUX:-}${STY:-} ]]; then
        LOGO_BACKEND=kitty
    elif [[ ${TERM:-} == foot || ${TERM:-} == foot-direct ]] && [[ -z ${TMUX:-}${STY:-} ]]; then
        LOGO_BACKEND=sixel
    elif ((${UI_UNICODE:-0})) && { [[ ${COLORTERM:-} == truecolor || ${COLORTERM:-} == 24bit ]] || [[ ${VTE_VERSION:-} =~ ^[0-9]+$ ]]; }; then
        LOGO_BACKEND=blocks
    fi
}

logo_choose_fallback() {
    LOGO_BACKEND=initials
    ((${UI_COLOR:-0} && ${UI_UNICODE:-0})) && LOGO_BACKEND=blocks
    return 0
}

logo_prepare_backend() {
    local key
    LOGO_QUERY_CHANGED=0 LOGO_SIXEL_SIDE=0
    logo_choose_backend
    [[ $LOGO_BACKEND == sixel ]] || return 0
    key="${TERM:-}|${UI_COLS:-0}|${UI_LINES:-0}"
    if [[ $LOGO_SIXEL_FAILED_KEY == "$key|${PLAYER_URL:-}|${PLAYER_NAME:-}" ]]; then
        logo_choose_fallback
        return 0
    fi
    if [[ $key != "$LOGO_CELL_QUERY_KEY" ]]; then
        LOGO_CELL_QUERY_KEY=$key LOGO_CELL_QUERY_UNTIL=$((EPOCHSECONDS+1))
        INPUT_CELL_WIDTH=0 INPUT_CELL_HEIGHT=0 LOGO_QUERY_CHANGED=1
        logo_cleanup
        LOGO_STATUS='Midiendo espacio del logo'
        # Consulta asíncrona: input.sh conserva las teclas anteriores/posteriores.
        # No abrir /dev/tty ni esperar aquí, tampoco al cambiar de emisora.
        printf '\033[16t'
        return 1
    fi
    if ((${INPUT_CELL_WIDTH:-0} == 0 || ${INPUT_CELL_HEIGHT:-0} == 0)); then
        ((EPOCHSECONDS >= LOGO_CELL_QUERY_UNTIL)) || return 1
        logo_choose_fallback
        return 0
    fi
    LOGO_SIXEL_SIDE=$((INPUT_CELL_WIDTH*12))
    ((LOGO_SIXEL_SIDE <= INPUT_CELL_HEIGHT*6)) || LOGO_SIXEL_SIDE=$((INPUT_CELL_HEIGHT*6))
    ((LOGO_SIXEL_SIDE <= 96)) || LOGO_SIXEL_SIDE=96
    LOGO_SIXEL_SIDE=$((LOGO_SIXEL_SIDE/6*6))
    if ((LOGO_SIXEL_SIDE < 6)); then LOGO_BACKEND=initials; LOGO_SIXEL_SIDE=0; fi
    return 0
}

logo_request_signature() {
    LOGO_SIGNATURE="$PLAYER_URL|${PLAYER_NAME:-}|$LOGO_CATALOG_GENERATION|$1|${UI_COLOR:-0}|${UI_UNICODE:-0}|$LOGO_BACKEND|$LOGO_SIXEL_SIDE"
}

logo_hide() {
    # Elimina solo la colocación visible. Conservamos los píxeles subidos para
    # que un redibujado completo pueda volver a colocarlos sin retransmitirlos.
    if ((LOGO_DRAWN)); then
        if [[ ${LOGO_DRAW_BACKEND:-$LOGO_BACKEND} == sixel ]]; then
            local row
            printf '\0337'
            # ECH borra solo nuestras celdas, sin avanzar ni hacer autowrap.
            for ((row=4; row<10; row++)); do printf '\033[%d;%dH\033[12X' "$row" "$LOGO_DRAW_COLUMN"; done
            printf '\0338'
        else
            printf '\033_Ga=d,d=i,i=%s,p=1,q=2\033\134' "$LOGO_IMAGE_ID"
        fi
    fi
    LOGO_DRAWN=0 LOGO_DRAW_KEY='' UI_LOGO_PRESERVE=0
}

logo_can_draw() {
    ((${UI_LOGO_LAYOUT:-0} && ${UI_ACTIVE:-0} && !${UI_SUSPENDED:-0} && !${PREFERENCES_ACTIVE:-0})) || return 1
    [[ $LOGO_READY_URL == "${PLAYER_URL:-}" && -n $LOGO_READY_URL ]] || return 1
    case $LOGO_BACKEND in
        sixel) [[ -n $LOGO_SIXEL_BODY ]] ;;
        kitty) [[ -n $LOGO_PIXELS_BASE64 ]] ;;
        *) return 1 ;;
    esac
}

logo_current_draw_key() {
    LOGO_FRAME_KEY="${TERM:-}|${UI_COLS:-0}|${UI_LINES:-0}|${UI_DESKTOP_LEFT_WIDTH:-0}|$LOGO_BACKEND|$LOGO_GENERATION|$LOGO_SIXEL_SIDE|$LOGO_READY_URL|${UI_COLOR:-0}|${UI_UNICODE:-0}"
}

logo_prepare_frame() {
    UI_LOGO_PRESERVE=0
    if logo_can_draw; then
        logo_current_draw_key
        if ((LOGO_DRAWN)) && [[ $LOGO_DRAW_KEY == "$LOGO_FRAME_KEY" ]]; then
            UI_LOGO_PRESERVE=1
            return 0
        fi
    fi
    # Solo borrar al abandonar el layout o cambiar imagen/geometría. Las filas
    # de un frame normal saltarán estas celdas, conservando SIXEL y Kitty.
    logo_hide
}

logo_forget() {
    logo_hide
    if ((LOGO_UPLOADED >= 0)); then printf '\033_Ga=d,d=I,i=%s,q=2\033\134' "$LOGO_IMAGE_ID"; fi
    LOGO_UPLOADED=-1
}

logo_stop_job() {
    if [[ -n "$LOGO_PID" ]]; then
        player_terminate_group_bounded "$LOGO_PID" "$LOGO_PID" >/dev/null 2>&1 || true
        wait "$LOGO_PID" 2>/dev/null || true
    fi
    LOGO_PID=''
    if [[ -n "$LOGO_JOB" && "$LOGO_JOB" == "${KEILA_CACHE_DIR:-}/logos/.job."* ]]; then rm -rf -- "$LOGO_JOB"; fi
    LOGO_JOB='' LOGO_JOB_MODE=''
}

logo_cleanup() {
    logo_stop_job
    logo_forget
    LOGO_REQUEST='' LOGO_READY_URL='' LOGO_ROWS=() LOGO_PIXELS_BASE64='' LOGO_PIXELS_HEX='' LOGO_SIXEL_BODY=''
}

logo_build_rows() {
    local row col offset top bottom fg_r fg_g fg_b bg_r bg_g bg_b cell line
    LOGO_ROWS=()
    for ((row=0; row<6; row++)); do
        line=''
        for ((col=0; col<12; col++)); do
            offset=$(((row*24+col)*6))
            top=${LOGO_PIXELS_HEX:offset:6} bottom=${LOGO_PIXELS_HEX:offset+72:6}
            fg_r=$((16#${top:0:2})) fg_g=$((16#${top:2:2})) fg_b=$((16#${top:4:2}))
            bg_r=$((16#${bottom:0:2})) bg_g=$((16#${bottom:2:2})) bg_b=$((16#${bottom:4:2}))
            printf -v cell '\033[38;2;%d;%d;%dm\033[48;2;%d;%d;%dm▀' "$fg_r" "$fg_g" "$fg_b" "$bg_r" "$bg_g" "$bg_b"
            line+=$cell
        done
        LOGO_ROWS+=("$line"$'\033[0m')
    done
}

logo_ready_status() {
    LOGO_STATUS='Logo en bloques'
    case $LOGO_BACKEND in
        kitty) LOGO_STATUS='Logo Kitty' ;;
        sixel)
            LOGO_STATUS='Logo guardado: preparando foot'
            [[ -z $LOGO_SIXEL_BODY ]] || LOGO_STATUS='Logo SIXEL (foot)' ;;
    esac
}

# Publicar solo datos validados. Una descarga idéntica no cambia la generación
# ni obliga a borrar/subir de nuevo la imagen que ya se está mostrando.
logo_accept_render() {
    local file=$1 sixel=$2 cached=${3:-0}
    local old_pixels=$LOGO_PIXELS_BASE64 old_hex=$LOGO_PIXELS_HEX old_sixel=$LOGO_SIXEL_BODY old_url=$LOGO_READY_URL
    logo_read_render "$file" || return 1
    if [[ $old_pixels != "$LOGO_PIXELS_BASE64" || $old_url != "$PLAYER_URL" ||
        $LOGO_SIXEL_BODY != "\"1;1;$LOGO_SIXEL_SIDE;$LOGO_SIXEL_SIDE"* ]]; then LOGO_SIXEL_BODY=''; fi
    if [[ $LOGO_BACKEND == sixel ]]; then
        if ((cached)); then logo_cache_read_sixel "$sixel" "$LOGO_SIXEL_SIDE" || true
        else logo_read_sixel "$sixel" "$LOGO_SIXEL_SIDE" || true; fi
    fi
    LOGO_READY_URL=$PLAYER_URL
    if [[ $old_pixels != "$LOGO_PIXELS_BASE64" || $old_hex != "$LOGO_PIXELS_HEX" ||
        $old_sixel != "$LOGO_SIXEL_BODY" || $old_url != "$LOGO_READY_URL" ]]; then LOGO_GENERATION=$((LOGO_GENERATION+1)); fi
    if [[ $old_hex != "$LOGO_PIXELS_HEX" || ${#LOGO_ROWS[@]} != 6 ]]; then logo_build_rows; fi
    logo_ready_status
}

logo_poll() {
    local request cache key have_catalog=0 reason='' cached=0 mode=normal status=0 finished_mode budget=35
    if ((!${PREF_LOGO:-0})) || ! logo_platform_allowed || [[ -z ${PLAYER_PID:-} ]] ||
        ! player_is_running || ((${UI_COLS:-0} < 120 || ${UI_LINES:-0} < 24)); then
        if [[ -n "$LOGO_REQUEST" || -n "$LOGO_PID" ]]; then logo_cleanup; LOGO_STATUS='Oculto'; return 0; fi
        return 1
    fi
    if ! logo_prepare_backend; then return "$((1-LOGO_QUERY_CHANGED))"; fi
    [[ ! -f ${KEILA_STATIONS_JSON:-} ]] || have_catalog=1
    logo_request_signature "$have_catalog"
    request=$LOGO_SIGNATURE
    if [[ "$request" != "$LOGO_REQUEST" ]]; then
        # Cambios de catálogo no ocultan el logo actual. Cambiar de emisora sí
        # elimina la imagen anterior antes de intentar cargar su propia copia.
        if [[ $LOGO_READY_URL != "$PLAYER_URL" ]]; then logo_cleanup; else logo_stop_job; fi
        LOGO_REQUEST=$request LOGO_CHECK_AT=0 LOGO_STATUS='Iniciales'
        [[ "$LOGO_BACKEND" != initials ]] || return 0
        cache="${KEILA_CACHE_DIR:-}/logos"
        [[ -n ${KEILA_CACHE_DIR:-} && ! -L "$cache" ]] || return 0
        (umask 077; mkdir -p "$cache") || return 0
        logo_cache_key "$PLAYER_URL" || return 0
        key=$LOGO_CACHE_KEY
        if logo_accept_render "$cache/$key.logo" "$cache/$key.sixel" 1; then
            cached=1
            if [[ $LOGO_BACKEND == sixel && -z $LOGO_SIXEL_BODY ]]; then mode=render; budget=10
            elif logo_cache_is_fresh "$cache/$key.logo"; then LOGO_STATUS+=' · guardado'; return 0; fi
        fi
        if [[ $mode != render ]]; then
            if logo_cache_read_check "$cache/$key.check"; then
                if ((cached)); then LOGO_STATUS+=' · revisión aplazada'; else LOGO_STATUS=$LOGO_CACHE_REASON; fi
                return 0
            fi
            if ((have_catalog == 0)); then
                if ((cached)); then LOGO_STATUS+=' · guardado, sin catálogo'; else LOGO_STATUS='Esperando catálogo para el logo'; fi
                return 0
            fi
            # Las copias ya preparadas funcionan incluso si falta ffmpeg.
            if ! command -v ffmpeg >/dev/null 2>&1; then
                if ((cached)); then LOGO_STATUS+=' · guardado, falta ffmpeg'; else LOGO_STATUS='Iniciales: falta ffmpeg'; fi
                return 0
            fi
        fi
        LOGO_JOB=$(mktemp -d "$cache/.job.XXXXXX") || return 0
        LOGO_STATUS='Cargando logo'
        ((cached == 0)) || LOGO_STATUS='Logo guardado · actualizando'
        [[ $mode != render ]] || LOGO_STATUS='Preparando logo guardado para foot'
        LOGO_JOB_MODE=$mode
        setsid -- timeout --kill-after=1s "${budget}s" bash "$LOGO_WORKER" "$PLAYER_URL" "${KEILA_STATIONS_JSON:-}" "$cache" "$LOGO_JOB" "${PLAYER_NAME:-}" "$LOGO_SIXEL_SIDE" "$mode" </dev/null >/dev/null 2>&1 &
        LOGO_PID=$!
        return 0
    fi
    [[ -n "$LOGO_PID" ]] || return 1
    ((EPOCHSECONDS >= LOGO_CHECK_AT)) || return 1
    LOGO_CHECK_AT=$((EPOCHSECONDS+1))
    # El resultado solo se lee cuando terminó el escritor, no a medio publicar.
    kill -0 "$LOGO_PID" 2>/dev/null && return 1
    wait "$LOGO_PID" 2>/dev/null || status=$?
    LOGO_PID=''
    finished_mode=$LOGO_JOB_MODE
    if logo_accept_render "$LOGO_JOB/result" "$LOGO_JOB/sixel"; then
        if [[ $LOGO_BACKEND == sixel ]]; then
            if [[ -z $LOGO_SIXEL_BODY ]]; then
                LOGO_SIXEL_FAILED_KEY="$LOGO_CELL_QUERY_KEY|${PLAYER_URL:-}|${PLAYER_NAME:-}"
                logo_choose_fallback
                LOGO_SIXEL_SIDE=0
                logo_request_signature "$have_catalog"; LOGO_REQUEST=$LOGO_SIGNATURE
                LOGO_STATUS='Iniciales: SIXEL no disponible'
                [[ $LOGO_BACKEND != blocks ]] || LOGO_STATUS='Logo en bloques: SIXEL no disponible'
            fi
        fi
        ((status == 0)) || LOGO_STATUS+=' · actualización fallida; se conserva'
        # Una preparación local de SIXEL no sustituye a la revisión diaria:
        # el siguiente tick decide si hay que actualizar el RGB antiguo.
        if [[ $finished_mode == render && $LOGO_BACKEND == sixel && -n $LOGO_SIXEL_BODY ]]; then LOGO_REQUEST=''; fi
    else
        LOGO_STATUS='Sin logo disponible'
        if [[ $LOGO_READY_URL == "$PLAYER_URL" && -n $LOGO_PIXELS_BASE64 ]]; then LOGO_STATUS='Logo guardado · no se pudo actualizar'; fi
        if [[ -f "$LOGO_JOB/status" && ! -L "$LOGO_JOB/status" ]]; then
            IFS= read -r -n 120 reason < "$LOGO_JOB/status" || true
            if [[ $LOGO_READY_URL != "$PLAYER_URL" ]]; then
                case $reason in
                    'No hay candidato seguro en el catálogo'|'No se pudo descargar el logo'|'Imagen no válida'|'Formato no admitido (SVG/HTML u otro)') LOGO_STATUS=$reason ;;
                esac
            fi
        fi
    fi
    logo_stop_job
    return 0
}

logo_prepare_layout() {
    UI_LOGO_LAYOUT=0
    if ((${PREF_LOGO:-0} && ${UI_COLS:-0} >= 120 && ${UI_LINES:-0} >= 24 && ${UI_DESKTOP_LEFT_WIDTH:-0} >= 46)) &&
        logo_platform_allowed && [[ -n ${PLAYER_PID:-} ]] && player_is_running; then UI_LOGO_LAYOUT=1; fi
}

logo_line_width() {
    UI_PLAYER_LINE_WIDTH=$UI_DESKTOP_LEFT_WIDTH
    if ((${UI_LOGO_LAYOUT:-0} && $1 < 6)); then UI_PLAYER_LINE_WIDTH=$((UI_PLAYER_LINE_WIDTH-14)); fi
}

logo_print_slot() {
    local row=$1 text='' word initials='' name=${PLAYER_NAME:-Radio}
    if [[ "$LOGO_READY_URL" == "${PLAYER_URL:-}" && -n "$LOGO_READY_URL" && "$LOGO_BACKEND" == blocks && ${#LOGO_ROWS[@]} == 6 ]]; then
        printf '%s' "${LOGO_ROWS[row]}"; return 0
    fi
    if [[ $LOGO_READY_URL == "${PLAYER_URL:-}" && -n $LOGO_READY_URL ]] &&
        { [[ $LOGO_BACKEND == sixel && -n $LOGO_SIXEL_BODY ]] || [[ $LOGO_BACKEND == kitty && -n $LOGO_PIXELS_BASE64 ]]; }; then
        # Escribir espacios también borra píxeles SIXEL. Avanzar el cursor no
        # toca la imagen ni cambia los anchos del resto de columnas.
        if ((UI_LOGO_PRESERVE)); then printf '\033[12C'; else printf '%12s' ''; fi
        return 0
    fi
    if ((row == 2)); then
        name=${name//[^a-zA-Z0-9 ]/}
        for word in $name; do initials+=${word:0:1}; ((${#initials} < 2)) || break; done
        text="[${initials^^}]"; [[ -n "$initials" ]] || text='[RADIO]'
    fi
    local margin=$(((12-${#text})/2))
    printf '%*s%-*s' "$margin" '' "$((12-margin))" "$text"
}

logo_print_left() {
    local text=$1 badge=$2 style=$3 badge_style=$4 row=$5
    logo_line_width "$row"
    ui_print_split_styled "$UI_PLAYER_LINE_WIDTH" "$text" "$badge" "$style" "$badge_style"
    if ((${UI_LOGO_LAYOUT:-0} && row < 6)); then printf '  '; logo_print_slot "$row"; fi
}

logo_draw() {
    logo_can_draw || return 0
    logo_current_draw_key
    ((LOGO_DRAWN)) && [[ $LOGO_DRAW_KEY == "$LOGO_FRAME_KEY" ]] && return 0
    logo_hide
    LOGO_DRAW_COLUMN=$((UI_DESKTOP_LEFT_WIDTH-9)) LOGO_DRAW_BACKEND=$LOGO_BACKEND
    if [[ $LOGO_BACKEND == sixel && -n $LOGO_SIXEL_BODY ]]; then
        printf '\0337\033[4;%dH\033P0;1;0q%s\033\134\0338' "$LOGO_DRAW_COLUMN" "$LOGO_SIXEL_BODY"
        LOGO_DRAWN=1 LOGO_DRAW_KEY=$LOGO_FRAME_KEY
        return 0
    fi
    [[ "$LOGO_BACKEND" == kitty && -n "$LOGO_PIXELS_BASE64" ]] || return 0
    local offset chunk more prefix
    if ((LOGO_UPLOADED != LOGO_GENERATION)); then
        logo_forget
        for ((offset=0; offset<36864; offset+=4096)); do
            chunk=${LOGO_PIXELS_BASE64:offset:4096} more=1 prefix=''
            ((offset+4096 < 36864)) || more=0
            ((offset != 0)) || prefix="a=t,f=24,s=96,v=96,i=$LOGO_IMAGE_ID,q=2,"
            printf '\033_G%sm=%d;%s\033\134' "$prefix" "$more" "$chunk"
        done
        LOGO_UPLOADED=$LOGO_GENERATION
    fi
    printf '\0337\033[4;%dH\033_Ga=p,i=%s,p=1,c=12,r=6,C=1,q=2\033\134\0338' "$((UI_DESKTOP_LEFT_WIDTH-9))" "$LOGO_IMAGE_ID"
    LOGO_DRAWN=1 LOGO_DRAW_KEY=$LOGO_FRAME_KEY
}

app_toggle_logo() {
    local previous=$PREF_LOGO
    PREF_LOGO=$((1-PREF_LOGO))
    if ! preferences_save; then PREF_LOGO=$previous; app_message 'No se pudo guardar la opción del logo.' 6; return 1; fi
    logo_cleanup
    LOGO_SIXEL_FAILED_KEY=''
    if ((PREF_LOGO)); then
        LOGO_STATUS='Pendiente de mostrar'
        app_message 'Logo activado: imagen en Kitty/foot (SIXEL); bloques o iniciales en el resto. ffmpeg es opcional.' 9
    else
        # El estado se consume desde Opciones, que es otro módulo.
        # shellcheck disable=SC2034
        LOGO_STATUS='Desactivado'
        app_message 'Logo desactivado.' 5
    fi
}
