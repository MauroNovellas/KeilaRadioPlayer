#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Identidad lógica separada del stream elegido; comprobación sobre los ticks
# existentes. Sin consultas de catálogo/red en la ruta normal de reproducción.
declare -A QUALITY_TARGETS=() QUALITY_RATES=()
QUALITY_PLAY_URL='' QUALITY_PLAY_RATE=0 QUALITY_NOTICE=''
QUALITY_JOB_PID='' QUALITY_JOB_DIR='' QUALITY_JOB_CATALOG_READ=0
QUALITY_WORKER="$(dirname "${BASH_SOURCE[0]}")/quality-worker.sh"
# Prueba de audio de la sesión actual: no se escribe la elección provisional.
QUALITY_CHECK_ACTIVE=0 QUALITY_CHECK_PID='' QUALITY_CHECK_ORIGIN='' QUALITY_CHECK_NAME=''
QUALITY_CHECK_TARGET='' QUALITY_CHECK_RATE=0 QUALITY_CHECK_OLD_INPUT='' QUALITY_CHECK_OLD_RATE=0
QUALITY_CHECK_LAST_AT=0 QUALITY_CHECK_ELAPSED=0 QUALITY_CHECK_TIMEOUT=12 QUALITY_CHECK_PAUSED=0
QUALITY_CHECK_POSITION=''

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

quality_validate_choice() {
    local origin=$1 target=$2 rate=$3
    if ! data_quality_url_valid "$origin" || ! data_quality_url_valid "$target"; then QUALITY_NOTICE='Dirección de emisión no válida; no se guarda.'; return 1; fi
    if [[ ! $rate =~ ^(0|[1-9][0-9]{0,6})$ ]] || ! ((rate == 0 || (rate >= 8000 && rate <= 2000000))); then QUALITY_NOTICE='Bitrate no válido; no se guarda.'; return 1; fi
    return 0
}

quality_save_choice() {
    local origin=$1 target=$2 rate=$3 file="$KEILA_CONFIG_DIR/qualities" tmp status=0 key
    QUALITY_NOTICE=''
    ((${BACKUP_DATA_BUSY:-0} == 0)) || { QUALITY_NOTICE='Espera al final de la restauración.'; return 1; }
    quality_validate_choice "$origin" "$target" "$rate" || return 1
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

quality_check_now() {
    QUALITY_CHECK_NOW_VALUE=${EPOCHSECONDS:-$(date +%s)}
}

# También se invoca desde player_stop: salir, parar o elegir otra emisora nunca
# guarda una prueba pendiente ni puede resucitar la radio anterior en otro tick.
quality_check_cancel() {
    QUALITY_CHECK_ACTIVE=0 QUALITY_CHECK_PID='' QUALITY_CHECK_ORIGIN='' QUALITY_CHECK_NAME=''
    QUALITY_CHECK_TARGET='' QUALITY_CHECK_RATE=0 QUALITY_CHECK_OLD_INPUT='' QUALITY_CHECK_OLD_RATE=0
    QUALITY_CHECK_LAST_AT=0 QUALITY_CHECK_ELAPSED=0 QUALITY_CHECK_PAUSED=0 QUALITY_CHECK_POSITION=''
}

quality_check_revert() {
    local reason=$1 origin=$QUALITY_CHECK_ORIGIN name=$QUALITY_CHECK_NAME
    local input=$QUALITY_CHECK_OLD_INPUT rate=$QUALITY_CHECK_OLD_RATE paused=$QUALITY_CHECK_PAUSED
    if player_is_running; then paused=$PLAYER_PAUSED; fi
    quality_check_cancel
    # La preferencia en disco sigue siendo la anterior. El override recupera
    # exactamente lo que se escuchaba, incluso si otra sesión editó el archivo.
    local QUALITY_OVERRIDE_URL=$input QUALITY_OVERRIDE_RATE=$rate PLAYER_PRESERVE_MUTE=1 PLAYER_START_PAUSED=$paused
    if player_start "$name" "$origin" >/dev/null 2>&1; then
        QUALITY_NOTICE="$reason Recuperando la versión anterior; se conserva volumen, silencio y pausa."
    else
        QUALITY_NOTICE="$reason Tampoco se pudo abrir la anterior; vuelve a elegir la emisora. La preferencia guardada no se cambia."
    fi
    app_message "$QUALITY_NOTICE" 9
    return 0
}

# Normalizar solo números de mpv, sin jq/awk ni aritmética con datos sin validar.
# Dos posiciones crecientes son necesarias: ni códec, ni IPC, ni reloj congelado
# prueban que la nueva conexión está entregando audio.
quality_check_position() {
    local position=$1 whole fraction
    [[ $position =~ ^([0-9]{1,10})([.]([0-9]{1,9}))?$ ]] || return 1
    whole=${BASH_REMATCH[1]} fraction=${BASH_REMATCH[3]:-0}000
    fraction=${fraction:0:3}
    QUALITY_POSITION_MS=$((10#$whole * 1000 + 10#$fraction))
}

quality_check_tick() {
    ((QUALITY_CHECK_ACTIVE)) || return 1
    local now gap changed=1 notice
    if [[ $PLAYER_URL != "$QUALITY_CHECK_ORIGIN" ||
          (-n $PLAYER_PID && $PLAYER_PID != "$QUALITY_CHECK_PID") ||
          ${PLAYER_INPUT_URL:-} != "$QUALITY_CHECK_TARGET" || ${PLAYER_HLS_RATE:-0} != "$QUALITY_CHECK_RATE" ]]; then
        quality_check_cancel
        return 0
    fi
    if ! player_is_running; then
        quality_check_revert 'La nueva calidad se detuvo antes de confirmar el audio.'
        return 0
    fi
    # Defensa adicional: nunca reiniciar un mpv que ya está grabando.
    if ((${RECORDING_ACTIVE:-0})); then
        quality_check_cancel
        QUALITY_NOTICE='Comprobación cancelada: hay una grabación activa. No se cambia el audio ni la preferencia.'
        app_message "$QUALITY_NOTICE" 9
        return 0
    fi
    quality_check_now; now=$QUALITY_CHECK_NOW_VALUE
    gap=$((now - QUALITY_CHECK_LAST_AT))
    QUALITY_CHECK_LAST_AT=$now
    if ((PLAYER_PAUSED)); then
        if ((QUALITY_CHECK_PAUSED == 0)); then
            QUALITY_NOTICE='Calidad pendiente de comprobar: reanuda para verificar el audio.'
            app_message "$QUALITY_NOTICE" 9
            changed=0
        fi
        QUALITY_CHECK_PAUSED=1 QUALITY_CHECK_POSITION=''
        return "$changed"
    fi
    # Pausa y suspensión no consumen el plazo de arranque. Tras reanudar se
    # exigen muestras nuevas, sin utilizar relojes anteriores a la suspensión.
    if ((QUALITY_CHECK_PAUSED || gap < 0 || gap >= ${APP_RECONNECT_RESUME_GAP:-30})); then
        QUALITY_CHECK_ELAPSED=0 QUALITY_CHECK_POSITION=''
        QUALITY_NOTICE='Comprobando calidad… esperando audio; la preferencia anterior sigue guardada.'
        app_message "$QUALITY_NOTICE" 9
        changed=0
    else
        QUALITY_CHECK_ELAPSED=$((QUALITY_CHECK_ELAPSED + gap))
    fi
    QUALITY_CHECK_PAUSED=0
    if ((PLAYER_STREAM_READY && !PLAYER_BUFFERING && PLAYER_STREAM_CORE_IDLE == 0)) &&
        quality_check_position "${PLAYER_STREAM_LAST_POSITION:-}"; then
        if [[ -n $QUALITY_CHECK_POSITION ]] && ((QUALITY_POSITION_MS > QUALITY_CHECK_POSITION)); then
            # Una copia/restauración puede estar bloqueando datos temporalmente.
            # Con audio que avanza, esperar sin cortar ni vencer por ese bloqueo.
            if ((${BACKUP_DATA_BUSY:-0})); then
                notice='Audio comprobado; esperando a que termine la operación de datos para guardar la calidad.'
                if [[ $QUALITY_NOTICE != "$notice" ]]; then QUALITY_NOTICE=$notice; app_message "$notice" 9; return 0; fi
                return "$changed"
            fi
            if quality_save_choice "$QUALITY_CHECK_ORIGIN" "$QUALITY_CHECK_TARGET" "$QUALITY_CHECK_RATE"; then
                notice=${QUALITY_NOTICE:+ $QUALITY_NOTICE}
                quality_check_cancel
                app_reconnect_cancel_pending
                APP_RECONNECT_ELIGIBLE=1 APP_RECONNECT_INITIAL_START=0
                QUALITY_NOTICE="Calidad comprobada y guardada: se está recibiendo audio.$notice"
                app_message "$QUALITY_NOTICE" 7
            else
                notice=$QUALITY_NOTICE
                quality_check_revert "No se pudo guardar la calidad comprobada: $notice"
            fi
            return 0
        fi
        QUALITY_CHECK_POSITION=$QUALITY_POSITION_MS
    else
        QUALITY_CHECK_POSITION=''
    fi
    if ((QUALITY_CHECK_ELAPSED >= QUALITY_CHECK_TIMEOUT)); then
        quality_check_revert "La nueva calidad no entregó audio con progreso en ${QUALITY_CHECK_TIMEOUT}s."
        return 0
    fi
    return "$changed"
}

quality_apply_choice() {
    local origin=$1 pid=$2 target=$3 rate=$4 old_input=${PLAYER_INPUT_URL:-$1} old_hls=${PLAYER_HLS_RATE:-0}
    local name=$PLAYER_NAME paused=$PLAYER_PAUSED status=0
    QUALITY_NOTICE=''
    if [[ $PLAYER_URL != "$origin" || $PLAYER_PID != "$pid" ]] || ! player_is_running; then
        QUALITY_NOTICE='La reproducción cambió. Vuelve a abrir el selector.'; return 1
    fi
    if ((RECORDING_ACTIVE)) || record_plan_busy || [[ -n ${PENDING_PREVIEW_PID:-} ]]; then
        QUALITY_NOTICE='No se cambia durante una grabación, programación en curso o escucha de archivo.'; return 1
    fi
    ((QUALITY_CHECK_ACTIVE == 0)) || { QUALITY_NOTICE='Ya hay una calidad pendiente de comprobar; reanuda si está en pausa.'; return 1; }
    ((${BACKUP_DATA_BUSY:-0} == 0)) || { QUALITY_NOTICE='Espera al final de la operación de datos.'; return 1; }
    quality_validate_choice "$origin" "$target" "$rate" || return 1
    quality_load || { QUALITY_NOTICE='Preferencias dañadas: no se cambia la reproducción ni se sobrescriben.'; return 1; }
    if [[ $old_input == "$target" && $old_hls == "$rate" ]] && ((PLAYER_STREAM_READY)); then
        quality_save_choice "$origin" "$target" "$rate" || return 1
        QUALITY_NOTICE="Elección guardada; ya estás escuchando esta versión.${QUALITY_NOTICE:+ $QUALITY_NOTICE}"
        return 0
    fi
    local PLAYER_PRESERVE_MUTE=1 PLAYER_START_PAUSED=$paused QUALITY_OVERRIDE_URL=$target QUALITY_OVERRIDE_RATE=$rate
    if [[ $old_input != "$target" || $old_hls != "$rate" ]]; then
        player_start "$name" "$origin" >/dev/null 2>&1 || status=$?
    fi
    # player_start llama a player_stop: instalar el estado solo después de ese
    # cierre intencional, también para recuperar un fallo inmediato de IPC.
    QUALITY_CHECK_ACTIVE=1 QUALITY_CHECK_PID=$PLAYER_PID QUALITY_CHECK_ORIGIN=$origin QUALITY_CHECK_NAME=$name
    QUALITY_CHECK_TARGET=$target QUALITY_CHECK_RATE=$rate QUALITY_CHECK_OLD_INPUT=$old_input QUALITY_CHECK_OLD_RATE=$old_hls
    quality_check_now; QUALITY_CHECK_LAST_AT=$QUALITY_CHECK_NOW_VALUE
    QUALITY_CHECK_ELAPSED=0 QUALITY_CHECK_PAUSED=$paused QUALITY_CHECK_POSITION=''
    QUALITY_CHECK_TIMEOUT=${APP_RECONNECT_START_TIMEOUT:-12}
    if ((status)); then quality_check_revert 'No se pudo abrir la versión elegida.'; return 1; fi
    if ((paused)); then QUALITY_NOTICE='Calidad pendiente de comprobar: reanuda para verificar el audio. No se guarda todavía.'
    else QUALITY_NOTICE='Comprobando calidad… esperando audio; la preferencia anterior sigue guardada.'; fi
    return 0
}
