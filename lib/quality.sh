#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Identidad lógica separada del stream elegido. Sin polling ni IO al reproducir.
declare -A QUALITY_TARGETS=() QUALITY_RATES=()
QUALITY_PLAY_URL='' QUALITY_PLAY_RATE=0 QUALITY_NOTICE=''
QUALITY_JOB_PID='' QUALITY_JOB_DIR='' QUALITY_JOB_CATALOG_READ=0
QUALITY_WORKER="$(dirname "${BASH_SOURCE[0]}")/quality-worker.sh"

quality_load() {
    local file="$KEILA_CONFIG_DIR/qualities" origin target rate
    local -A targets=() rates=()
    if [[ -e $file || -L $file ]]; then
        data_validate "$file" qualities || return 1
        while IFS='|' read -r origin target rate; do
            targets[$origin]=$target rates[$origin]=$rate
        done < "$file"
    fi
    QUALITY_TARGETS=() QUALITY_RATES=()
    for origin in "${!targets[@]}"; do QUALITY_TARGETS[$origin]=${targets[$origin]}; QUALITY_RATES[$origin]=${rates[$origin]}; done
}

quality_resolve_playback() {
    local origin=$1
    QUALITY_PLAY_URL=$origin QUALITY_PLAY_RATE=0
    if [[ -n ${QUALITY_OVERRIDE_URL:-} ]]; then
        QUALITY_PLAY_URL=$QUALITY_OVERRIDE_URL QUALITY_PLAY_RATE=${QUALITY_OVERRIDE_RATE:-0}
    elif [[ -n ${QUALITY_TARGETS[$origin]:-} ]]; then
        QUALITY_PLAY_URL=${QUALITY_TARGETS[$origin]} QUALITY_PLAY_RATE=${QUALITY_RATES[$origin]}
    fi
}

quality_save_choice() {
    local origin=$1 target=$2 rate=$3 file="$KEILA_CONFIG_DIR/qualities" tmp status=0 key
    QUALITY_NOTICE=''
    ((${BACKUP_DATA_BUSY:-0} == 0)) || { QUALITY_NOTICE='Espera al final de la restauración.'; return 1; }
    if ! data_quality_url_valid "$origin" || ! data_quality_url_valid "$target"; then QUALITY_NOTICE='Dirección de emisión no válida; no se guarda.'; return 1; fi
    if [[ ! $rate =~ ^(0|[1-9][0-9]{0,6})$ ]] || ! ((rate == 0 || (rate >= 8000 && rate <= 2000000))); then QUALITY_NOTICE='Bitrate no válido; no se guarda.'; return 1; fi
    if ! keila_init_paths || ! lock_acquire "$file.lock"; then QUALITY_NOTICE='No se pudo bloquear el archivo de calidades; no se cambia la emisión.'; return 1; fi
    if ! quality_load; then lock_release "$file.lock" || true; QUALITY_NOTICE='Preferencias dañadas: no se sobrescriben.'; return 1; fi
    QUALITY_PREVIOUS_TARGET=${QUALITY_TARGETS[$origin]:-} QUALITY_PREVIOUS_RATE=${QUALITY_RATES[$origin]:-0}
    if [[ $origin == "$target" && $rate == 0 ]]; then
        unset 'QUALITY_TARGETS[$origin]' 'QUALITY_RATES[$origin]'
    else
        QUALITY_TARGETS[$origin]=$target QUALITY_RATES[$origin]=$rate
    fi
    tmp=$(umask 077; mktemp "$KEILA_CONFIG_DIR/.qualities.XXXXXX") || status=1
    if ((status == 0)); then
        { for key in "${!QUALITY_TARGETS[@]}"; do printf '%s|%s|%s\n' "$key" "${QUALITY_TARGETS[$key]}" "${QUALITY_RATES[$key]}"; done; } > "$tmp" || status=1
        ((status != 0)) || data_publish "$tmp" "$file" qualities || status=1
        rm -f -- "$tmp"
    fi
    if ((status)); then
        if [[ -n $QUALITY_PREVIOUS_TARGET ]]; then
            QUALITY_TARGETS[$origin]=$QUALITY_PREVIOUS_TARGET QUALITY_RATES[$origin]=$QUALITY_PREVIOUS_RATE
        else unset 'QUALITY_TARGETS[$origin]' 'QUALITY_RATES[$origin]'; fi
        QUALITY_NOTICE='No se pudo guardar; no se cambia la reproducción.'
    fi
    # El documento ya está publicado: un fallo al retirar el lock no deshace
    # esa escritura ni debe presentarla como un guardado fallido.
    lock_release "$file.lock" || QUALITY_NOTICE+=' No se pudo retirar el bloqueo; revisa el archivo de calidades.'
    return "$status"
}

quality_cleanup() {
    if [[ -n $QUALITY_JOB_PID ]]; then
        player_terminate_group_bounded "$QUALITY_JOB_PID" "$QUALITY_JOB_PID" || true
        wait "$QUALITY_JOB_PID" 2>/dev/null || true
    fi
    QUALITY_JOB_PID=''
    if [[ -n $QUALITY_JOB_DIR && $QUALITY_JOB_DIR == "${TMPDIR:-/tmp}/keila-quality."* && ! -L $QUALITY_JOB_DIR ]]; then rm -rf -- "$QUALITY_JOB_DIR"; fi
    QUALITY_JOB_DIR='' QUALITY_JOB_CATALOG_READ=0
}

quality_start_job() {
    quality_cleanup
    QUALITY_JOB_DIR=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/keila-quality.XXXXXX") || return 1
    setsid -- timeout --kill-after=1s 25s bash "$QUALITY_WORKER" "$1" "$2" "$3" "${KEILA_STATIONS_JSON:-}" "$QUALITY_JOB_DIR" </dev/null >/dev/null 2>&1 &
    QUALITY_JOB_PID=$!
}

quality_apply_choice() {
    local origin=$1 pid=$2 target=$3 rate=$4 old_target old_rate old_input=${PLAYER_INPUT_URL:-$1} old_hls=${PLAYER_HLS_RATE:-0}
    QUALITY_NOTICE=''
    if [[ $PLAYER_URL != "$origin" || $PLAYER_PID != "$pid" ]] || ! player_is_running; then
        QUALITY_NOTICE='La reproducción cambió. Vuelve a abrir el selector.'; return 1
    fi
    if ((RECORDING_ACTIVE)) || record_plan_busy || [[ -n ${PENDING_PREVIEW_PID:-} ]]; then
        QUALITY_NOTICE='No se cambia durante una grabación, programación en curso o escucha de archivo.'; return 1
    fi
    quality_save_choice "$origin" "$target" "$rate" || return 1
    old_target=$QUALITY_PREVIOUS_TARGET old_rate=$QUALITY_PREVIOUS_RATE
    if [[ $old_input == "$target" && $old_hls == "$rate" ]]; then QUALITY_NOTICE='Elección guardada; ya estás escuchando esta versión.'; return 0; fi
    local PLAYER_PRESERVE_MUTE=1 PLAYER_START_PAUSED=$PLAYER_PAUSED
    if player_start "$PLAYER_NAME" "$origin"; then
        QUALITY_NOTICE='Calidad/versión guardada. Conectando; se conserva volumen, silencio y pausa.'
        return 0
    fi
    QUALITY_NOTICE='No se pudo abrir la versión elegida.'
    local rollback_notice=''
    quality_save_choice "$origin" "${old_target:-$origin}" "$old_rate" || rollback_notice=' No se pudo restaurar la preferencia guardada.'
    local QUALITY_OVERRIDE_URL=$old_input QUALITY_OVERRIDE_RATE=$old_hls
    if player_start "$PLAYER_NAME" "$origin"; then QUALITY_NOTICE="No se pudo abrir la versión elegida; reconectando la anterior.$rollback_notice"
    else QUALITY_NOTICE="No se pudo abrir ninguna conexión; vuelve a elegir la emisora.$rollback_notice"; fi
    return 1
}
