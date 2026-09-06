#!/usr/bin/env bash

# Política conservadora de reconexión automática para Keila 2.1.
#
# Solo se activa después de que una emisora haya alcanzado reproducción real.
# No reinicia mpv durante una grabación activa y nunca espera con sleep: los
# reintentos se programan por tiempo y el loop principal sigue atendiendo input.

APP_RECONNECT_STALL_TIMEOUT="${KEILA_RECONNECT_STALL_TIMEOUT:-15}"
APP_RECONNECT_START_TIMEOUT="${KEILA_RECONNECT_START_TIMEOUT:-12}"
APP_RECONNECT_MAX_ATTEMPTS="${KEILA_RECONNECT_MAX_ATTEMPTS:-3}"
APP_RECONNECT_BASE_DELAY="${KEILA_RECONNECT_BASE_DELAY:-2}"

APP_RECONNECT_ELIGIBLE=0
APP_RECONNECT_ATTEMPTS=0
APP_RECONNECT_WAITING=0
APP_RECONNECT_ATTEMPT_STARTED_AT=0
APP_RECONNECT_NEXT_AT=0
APP_RECONNECT_RECORDING_WARNED=0
APP_RECONNECT_EXHAUSTED=0

app_reconnect_now() {
    printf '%s\n' "${EPOCHSECONDS:-$(date +%s)}"
}

app_reconnect_configure() {
    [[ "$APP_RECONNECT_STALL_TIMEOUT" =~ ^[0-9]+$ ]] || APP_RECONNECT_STALL_TIMEOUT=15
    [[ "$APP_RECONNECT_START_TIMEOUT" =~ ^[0-9]+$ ]] || APP_RECONNECT_START_TIMEOUT=12
    [[ "$APP_RECONNECT_MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || APP_RECONNECT_MAX_ATTEMPTS=3
    [[ "$APP_RECONNECT_BASE_DELAY" =~ ^[0-9]+$ ]] || APP_RECONNECT_BASE_DELAY=2

    ((APP_RECONNECT_STALL_TIMEOUT < 5)) && APP_RECONNECT_STALL_TIMEOUT=5
    ((APP_RECONNECT_STALL_TIMEOUT > 120)) && APP_RECONNECT_STALL_TIMEOUT=120
    ((APP_RECONNECT_START_TIMEOUT < 5)) && APP_RECONNECT_START_TIMEOUT=5
    ((APP_RECONNECT_START_TIMEOUT > 60)) && APP_RECONNECT_START_TIMEOUT=60
    ((APP_RECONNECT_MAX_ATTEMPTS < 1)) && APP_RECONNECT_MAX_ATTEMPTS=1
    ((APP_RECONNECT_MAX_ATTEMPTS > 5)) && APP_RECONNECT_MAX_ATTEMPTS=5
    ((APP_RECONNECT_BASE_DELAY < 1)) && APP_RECONNECT_BASE_DELAY=1
    ((APP_RECONNECT_BASE_DELAY > 30)) && APP_RECONNECT_BASE_DELAY=30
}

app_reconnect_reset() {
    APP_RECONNECT_ELIGIBLE=0
    APP_RECONNECT_ATTEMPTS=0
    APP_RECONNECT_WAITING=0
    APP_RECONNECT_ATTEMPT_STARTED_AT=0
    APP_RECONNECT_NEXT_AT=0
    APP_RECONNECT_RECORDING_WARNED=0
    APP_RECONNECT_EXHAUSTED=0
}

# Cancela únicamente una secuencia automática pendiente. La emisora sigue
# siendo elegible si ya reprodujo de verdad; esto se usa al pausar o grabar.
app_reconnect_cancel_pending() {
    APP_RECONNECT_ATTEMPTS=0
    APP_RECONNECT_WAITING=0
    APP_RECONNECT_ATTEMPT_STARTED_AT=0
    APP_RECONNECT_NEXT_AT=0
    APP_RECONNECT_RECORDING_WARNED=0
    APP_RECONNECT_EXHAUSTED=0
}

app_reconnect_delay_after_attempt() {
    local attempt="${1:-$APP_RECONNECT_ATTEMPTS}"
    local delay="$APP_RECONNECT_BASE_DELAY"
    local i

    [[ "$attempt" =~ ^[0-9]+$ ]] || attempt=1
    ((attempt < 1)) && attempt=1
    for ((i = 1; i < attempt; i++)); do
        delay=$((delay * 2))
        ((delay >= 30)) && { delay=30; break; }
    done
    printf '%s\n' "$delay"
}

app_reconnect_stream_stalled() {
    local now="${1:-$(app_reconnect_now)}"

    ((APP_RECONNECT_ELIGIBLE)) || return 1
    ((APP_RECONNECT_WAITING == 0)) || return 1
    ((APP_RECONNECT_NEXT_AT == 0)) || return 1
    ((APP_RECONNECT_EXHAUSTED == 0)) || return 1
    ((PLAYER_STREAM_READY)) || return 1
    ((PLAYER_PAUSED == 0)) || return 1
    ((PLAYER_STREAM_LAST_PROGRESS_AT > 0)) || return 1

    ((now - PLAYER_STREAM_LAST_PROGRESS_AT >= APP_RECONNECT_STALL_TIMEOUT))
}

app_reconnect_schedule_retry() {
    local now="${1:-$(app_reconnect_now)}"
    local delay

    APP_RECONNECT_WAITING=0
    APP_RECONNECT_ATTEMPT_STARTED_AT=0

    if ((APP_RECONNECT_ATTEMPTS >= APP_RECONNECT_MAX_ATTEMPTS)); then
        APP_RECONNECT_NEXT_AT=0
        APP_RECONNECT_EXHAUSTED=1
        return 1
    fi

    delay=$(app_reconnect_delay_after_attempt "$APP_RECONNECT_ATTEMPTS")
    APP_RECONNECT_NEXT_AT=$((now + delay))
    return 0
}

app_reconnect_message_retry_or_exhausted() {
    local name="$1" now="${2:-$(app_reconnect_now)}"
    local delay

    if app_reconnect_schedule_retry "$now"; then
        delay=$((APP_RECONNECT_NEXT_AT - now))
        app_message "Reconexión ${APP_RECONNECT_ATTEMPTS}/${APP_RECONNECT_MAX_ATTEMPTS} falló · Nuevo intento en ${delay}s." 7
    else
        app_message "No se pudo recuperar $name tras ${APP_RECONNECT_ATTEMPTS} intentos." 9
    fi
}

app_reconnect_start_attempt() {
    local reason="${1:-retry}"
    local now="${2:-$(app_reconnect_now)}"
    local name="$PLAYER_NAME" url="$PLAYER_URL"
    local attempt

    ((RECORDING_ACTIVE == 0)) || return 1
    ((PLAYER_PAUSED == 0)) || return 1
    ((APP_RECONNECT_ELIGIBLE)) || return 1
    ((APP_RECONNECT_EXHAUSTED == 0)) || return 1
    ((APP_RECONNECT_ATTEMPTS < APP_RECONNECT_MAX_ATTEMPTS)) || return 1
    [[ -n "$url" ]] || return 1

    APP_RECONNECT_ATTEMPTS=$((APP_RECONNECT_ATTEMPTS + 1))
    attempt=$APP_RECONNECT_ATTEMPTS
    APP_RECONNECT_WAITING=1
    APP_RECONNECT_ATTEMPT_STARTED_AT=$now
    APP_RECONNECT_NEXT_AT=0

    case "$reason" in
        stall)
            app_message "Stream estancado · Reconectando: $name ($attempt/$APP_RECONNECT_MAX_ATTEMPTS)..." 7
            ;;
        exit)
            app_message "Reproducción interrumpida · Reconectando: $name ($attempt/$APP_RECONNECT_MAX_ATTEMPTS)..." 7
            ;;
        *)
            app_message "Reconectando: $name ($attempt/$APP_RECONNECT_MAX_ATTEMPTS)..." 7
            ;;
    esac

    if player_start "$name" "$url"; then
        return 0
    fi

    app_reconnect_message_retry_or_exhausted "$name" "$(app_reconnect_now)"
    return 0
}

# Intercepta una caída de mpv antes del manejador genérico del launcher. Las
# grabaciones quedan fuera deliberadamente: allí se conserva el flujo de
# recuperación/validación del archivo existente.
app_reconnect_handle_dead() {
    [[ -n "${PLAYER_PID:-}" ]] || return 1
    player_is_running && return 1
    ((RECORDING_ACTIVE == 0)) || return 1
    ((APP_RECONNECT_ELIGIBLE)) || return 1
    ((APP_RECONNECT_EXHAUSTED == 0)) || return 1

    local was_waiting=$APP_RECONNECT_WAITING
    local name="$PLAYER_NAME"
    local now
    now=$(app_reconnect_now)

    player_collect_exit_status >/dev/null 2>&1 || true

    if ((was_waiting)); then
        app_reconnect_message_retry_or_exhausted "$name" "$now"
    else
        app_reconnect_start_attempt exit "$now" || true
    fi
    return 0
}

# Atiende reintentos programados cuando el intento anterior dejó mpv detenido.
app_reconnect_handle_no_player() {
    local now

    player_is_running && return 1
    ((RECORDING_ACTIVE == 0)) || return 1
    ((PLAYER_PAUSED == 0)) || return 1
    ((APP_RECONNECT_ELIGIBLE)) || return 1
    ((APP_RECONNECT_EXHAUSTED == 0)) || return 1
    ((APP_RECONNECT_NEXT_AT > 0)) || return 1

    now=$(app_reconnect_now)
    ((now >= APP_RECONNECT_NEXT_AT)) || return 1

    app_reconnect_start_attempt retry "$now" || true
    return 0
}

# Se llama después de refrescar el snapshot de mpv. Detecta recuperación,
# timeout de un intento, bloqueo seguro por grabación y estancamiento real.
app_reconnect_after_refresh() {
    local now name attempt delay
    now=$(app_reconnect_now)

    if ((PLAYER_STREAM_READY)); then
        APP_RECONNECT_ELIGIBLE=1
    fi

    # Si el usuario empieza a grabar mientras había una reconexión en curso,
    # deja de haber reinicios automáticos desde ese momento.
    if ((RECORDING_ACTIVE && APP_RECONNECT_WAITING)); then
        app_reconnect_cancel_pending
    fi

    if ((APP_RECONNECT_WAITING)); then
        if ((PLAYER_STREAM_READY && PLAYER_STREAM_LAST_PROGRESS_AT > 0)); then
            name="$PLAYER_NAME"
            app_reconnect_cancel_pending
            APP_RECONNECT_ELIGIBLE=1
            app_message "Conexión recuperada: $name" 5
            return 0
        fi

        ((PLAYER_PAUSED == 0)) || return 1
        if ((now - APP_RECONNECT_ATTEMPT_STARTED_AT >= APP_RECONNECT_START_TIMEOUT)); then
            name="$PLAYER_NAME"
            attempt=$APP_RECONNECT_ATTEMPTS
            player_stop >/dev/null 2>&1 || true
            if app_reconnect_schedule_retry "$(app_reconnect_now)"; then
                now=$(app_reconnect_now)
                delay=$((APP_RECONNECT_NEXT_AT - now))
                ((delay < 0)) && delay=0
                app_message "Reconexión $attempt/$APP_RECONNECT_MAX_ATTEMPTS sin audio · Nuevo intento en ${delay}s." 7
            else
                app_message "No se pudo recuperar $name tras $attempt intentos." 9
            fi
            return 0
        fi
        return 1
    fi

    if ((RECORDING_ACTIVE)); then
        if app_reconnect_stream_stalled "$now"; then
            if ((APP_RECONNECT_RECORDING_WARNED == 0)); then
                APP_RECONNECT_RECORDING_WARNED=1
                app_message "Stream estancado durante la grabación · Reconexión automática desactivada para proteger el archivo." 9
                return 0
            fi
        else
            APP_RECONNECT_RECORDING_WARNED=0
        fi
        return 1
    fi

    APP_RECONNECT_RECORDING_WARNED=0
    if app_reconnect_stream_stalled "$now"; then
        app_reconnect_start_attempt stall "$now" || true
        return 0
    fi

    return 1
}

app_reconnect_on_pause_change() {
    if ((PLAYER_PAUSED)); then
        app_reconnect_cancel_pending
        return 0
    fi

    # Al reanudar concedemos una ventana completa antes de considerar un nuevo
    # estancamiento, incluso si el reloj llevaba mucho tiempo quieto por la pausa.
    if ((PLAYER_STREAM_READY)); then
        APP_RECONNECT_ELIGIBLE=1
        PLAYER_STREAM_LAST_PROGRESS_AT=$(app_reconnect_now)
    fi
}

app_reconnect_on_recording_start() {
    app_reconnect_cancel_pending
}

app_reconnect_configure
