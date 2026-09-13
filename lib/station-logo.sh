#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck source=lib/station-logo-worker.sh
source "$(dirname "${BASH_SOURCE[0]}")/station-logo-worker.sh"
LOGO_WORKER="$(dirname "${BASH_SOURCE[0]}")/station-logo-worker.sh"
LOGO_PID='' LOGO_JOB='' LOGO_REQUEST='' LOGO_READY_URL='' LOGO_BACKEND=initials
LOGO_PIXELS_BASE64='' LOGO_PIXELS_HEX='' LOGO_GENERATION=0 LOGO_UPLOADED=-1 LOGO_DRAWN=0
LOGO_IMAGE_ID=$((100000+$$)) LOGO_CHECK_AT=0 LOGO_CATALOG_GENERATION=0
LOGO_STATUS='Desactivado' UI_LOGO_LAYOUT=0
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
    elif ((${UI_UNICODE:-0})) && { [[ ${COLORTERM:-} == truecolor || ${COLORTERM:-} == 24bit ]] || [[ ${VTE_VERSION:-} =~ ^[0-9]+$ ]]; }; then
        LOGO_BACKEND=blocks
    fi
}

logo_hide() {
    # Elimina solo la colocación visible. Conservamos los píxeles subidos para
    # que un redibujado completo pueda volver a colocarlos sin retransmitirlos.
    if ((LOGO_DRAWN)); then printf '\033_Ga=d,d=i,i=%s,p=1,q=2\033\134' "$LOGO_IMAGE_ID"; fi
    LOGO_DRAWN=0
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
    LOGO_JOB=''
}

logo_cleanup() {
    logo_stop_job
    logo_forget
    LOGO_REQUEST='' LOGO_READY_URL='' LOGO_ROWS=() LOGO_PIXELS_BASE64='' LOGO_PIXELS_HEX=''
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

logo_poll() {
    local request cache have_catalog=0
    if ((!${PREF_LOGO:-0})) || ! logo_platform_allowed || [[ -z ${PLAYER_PID:-} ]] ||
        ! player_is_running || ((${UI_COLS:-0} < 120 || ${UI_LINES:-0} < 24)); then
        if [[ -n "$LOGO_REQUEST" || -n "$LOGO_PID" ]]; then logo_cleanup; LOGO_STATUS='Oculto'; return 0; fi
        return 1
    fi
    [[ ! -f ${KEILA_STATIONS_JSON:-} ]] || have_catalog=1
    request="$PLAYER_URL|$LOGO_CATALOG_GENERATION|$have_catalog|${UI_COLOR:-0}|${UI_UNICODE:-0}"
    if [[ "$request" != "$LOGO_REQUEST" ]]; then
        logo_cleanup
        LOGO_REQUEST=$request LOGO_CHECK_AT=0 LOGO_STATUS='Iniciales'
        logo_choose_backend
        [[ "$LOGO_BACKEND" != initials ]] || return 0
        if ! command -v ffmpeg >/dev/null 2>&1; then LOGO_STATUS='Iniciales: falta ffmpeg'; return 0; fi
        cache="${KEILA_CACHE_DIR:-}/logos"
        [[ -n ${KEILA_CACHE_DIR:-} && ! -L "$cache" ]] || return 0
        (umask 077; mkdir -p "$cache") || return 0
        LOGO_JOB=$(mktemp -d "$cache/.job.XXXXXX") || return 0
        LOGO_STATUS='Cargando logo'
        setsid -- timeout --kill-after=1s 35s bash "$LOGO_WORKER" "$PLAYER_URL" "${KEILA_STATIONS_JSON:-}" "$cache" "$LOGO_JOB" </dev/null >/dev/null 2>&1 &
        LOGO_PID=$!
        return 0
    fi
    [[ -n "$LOGO_PID" ]] || return 1
    ((EPOCHSECONDS >= LOGO_CHECK_AT)) || return 1
    LOGO_CHECK_AT=$((EPOCHSECONDS+1))
    # El resultado solo se lee cuando terminó el escritor, no a medio publicar.
    kill -0 "$LOGO_PID" 2>/dev/null && return 1
    wait "$LOGO_PID" 2>/dev/null || true
    LOGO_PID=''
    if logo_read_render "$LOGO_JOB/result"; then
        LOGO_READY_URL=$PLAYER_URL LOGO_GENERATION=$((LOGO_GENERATION+1))
        logo_build_rows
        LOGO_STATUS='Logo en bloques'; [[ "$LOGO_BACKEND" != kitty ]] || LOGO_STATUS='Logo Kitty'
    else
        LOGO_PIXELS_BASE64='' LOGO_PIXELS_HEX='' LOGO_STATUS='Sin logo disponible'
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
    ((${UI_LOGO_LAYOUT:-0} && ${UI_ACTIVE:-0} && !${UI_SUSPENDED:-0} && !${PREFERENCES_ACTIVE:-0})) || return 0
    [[ "$LOGO_BACKEND" == kitty && "$LOGO_READY_URL" == "${PLAYER_URL:-}" && -n "$LOGO_PIXELS_BASE64" ]] || return 0
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
    LOGO_DRAWN=1
}

app_toggle_logo() {
    local previous=$PREF_LOGO
    PREF_LOGO=$((1-PREF_LOGO))
    if ! preferences_save; then PREF_LOGO=$previous; app_message 'No se pudo guardar la opción del logo.' 6; return 1; fi
    logo_cleanup
    if ((PREF_LOGO)); then
        LOGO_STATUS='Pendiente de mostrar'
        app_message 'Logo activado en escritorio amplio. Kitty, bloques de color o iniciales según soporte; ffmpeg es opcional.' 9
    else
        # El estado se consume desde Opciones, que es otro módulo.
        # shellcheck disable=SC2034
        LOGO_STATUS='Desactivado'
        app_message 'Logo desactivado.' 5
    fi
}
