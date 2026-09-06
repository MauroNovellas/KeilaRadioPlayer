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
APP_RECONNECT_AUTOMATIC_START=0
APP_RECONNECT_RECORDING_GUARD=0
APP_RECONNECT_RECORDING_EXIT_EVENT=0

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
    local attempt status=0

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

    APP_RECONNECT_AUTOMATIC_START=1
    player_start "$name" "$url" || status=$?
    APP_RECONNECT_AUTOMATIC_START=0

    if ((status == 0)); then
        return 0
    fi

    app_reconnect_message_retry_or_exhausted "$name" "$(app_reconnect_now)"
    return 0
}

# Este tick corre después de app_poll_player: para entonces mpv ya ha actualizado
# readiness/progreso o el launcher ya ha recogido una caída del proceso.
# Devuelve 0 solo cuando cambia algo visible y conviene redibujar.
app_reconnect_tick() {
    local now name attempt delay
    now=$(app_reconnect_now)

    # Si mpv murió mientras se grababa, app_poll_player ya ha validado/recuperado
    # el archivo. No arrancamos otro mpv a espaldas del usuario.
    if ((APP_RECONNECT_RECORDING_EXIT_EVENT)); then
        APP_RECONNECT_RECORDING_EXIT_EVENT=0
        APP_RECONNECT_RECORDING_GUARD=0
        app_reconnect_reset
        return 1
    fi

    if ((PLAYER_STREAM_READY)); then
        APP_RECONNECT_ELIGIBLE=1
    fi

    # Una reproducción sana obtenida fuera de un intento automático (por ejemplo
    # un Enter manual sobre la misma emisora) vuelve a dejar el presupuesto limpio.
    if player_is_running && ((PLAYER_STREAM_READY && APP_RECONNECT_WAITING == 0)); then
        if ((APP_RECONNECT_ATTEMPTS > 0 || APP_RECONNECT_NEXT_AT > 0 || APP_RECONNECT_EXHAUSTED)); then
            app_reconnect_cancel_pending
            APP_RECONNECT_ELIGIBLE=1
        fi
    fi

    if ((RECORDING_ACTIVE)); then
        APP_RECONNECT_RECORDING_GUARD=1
        if ((APP_RECONNECT_WAITING || APP_RECONNECT_NEXT_AT > 0)); then
            app_reconnect_cancel_pending
            APP_RECONNECT_ELIGIBLE=$((PLAYER_STREAM_READY ? 1 : APP_RECONNECT_ELIGIBLE))
        fi

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

    APP_RECONNECT_RECORDING_GUARD=0
    APP_RECONNECT_RECORDING_WARNED=0

    # Una pausa manual cancela cualquier secuencia automática. Al reanudar, el
    # wrapper de player_toggle_pause concede una ventana completa de progreso.
    ((PLAYER_PAUSED == 0)) || return 1

    if ! player_is_running; then
        if ((APP_RECONNECT_WAITING)); then
            name="$PLAYER_NAME"
            app_reconnect_message_retry_or_exhausted "$name" "$now"
            return 0
        fi

        if ((APP_RECONNECT_NEXT_AT > 0)); then
            if ((now >= APP_RECONNECT_NEXT_AT)); then
                app_reconnect_start_attempt retry "$now" || true
                return 0
            fi
            return 1
        fi

        if ((APP_RECONNECT_ELIGIBLE && APP_RECONNECT_EXHAUSTED == 0)) && [[ -n "${PLAYER_URL:-}" ]]; then
            app_reconnect_start_attempt exit "$now" || true
            return 0
        fi
        return 1
    fi

    if ((APP_RECONNECT_WAITING)); then
        if ((PLAYER_STREAM_READY && PLAYER_STREAM_LAST_PROGRESS_AT > 0)); then
            name="$PLAYER_NAME"
            app_reconnect_cancel_pending
            APP_RECONNECT_ELIGIBLE=1
            app_message "Conexión recuperada: $name" 5
            return 0
        fi

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

    if app_reconnect_stream_stalled "$now"; then
        app_reconnect_start_attempt stall "$now" || true
        return 0
    fi

    return 1
}

app_reconnect_configure

# Los hooks se instalan tarde desde ui-safe-width.sh, cuando player, recording y
# el ui_message_tick refinado por el chequeo de updates ya existen.
if declare -F player_start >/dev/null 2>&1 && ! declare -F player_start_without_reconnect >/dev/null 2>&1; then
    APP_RECONNECT_DEF=$(declare -f player_start)
    APP_RECONNECT_DEF=${APP_RECONNECT_DEF/player_start ()/player_start_without_reconnect ()}
    eval "$APP_RECONNECT_DEF"

    player_start() {
        local name="$1" url="$2"

        if ((APP_RECONNECT_AUTOMATIC_START)); then
            player_start_without_reconnect "$name" "$url"
            return $?
        fi

        app_reconnect_reset
        player_start_without_reconnect "$name" "$url"
    }
fi

if declare -F player_toggle_pause >/dev/null 2>&1 && ! declare -F player_toggle_pause_without_reconnect >/dev/null 2>&1; then
    APP_RECONNECT_DEF=$(declare -f player_toggle_pause)
    APP_RECONNECT_DEF=${APP_RECONNECT_DEF/player_toggle_pause ()/player_toggle_pause_without_reconnect ()}
    eval "$APP_RECONNECT_DEF"

    player_toggle_pause() {
        player_toggle_pause_without_reconnect || return $?

        if ((PLAYER_PAUSED)); then
            app_reconnect_cancel_pending
        elif ((PLAYER_STREAM_READY)); then
            APP_RECONNECT_ELIGIBLE=1
            PLAYER_STREAM_LAST_PROGRESS_AT=$(app_reconnect_now)
        fi
    }
fi

if declare -F recording_start >/dev/null 2>&1 && ! declare -F recording_start_without_reconnect >/dev/null 2>&1; then
    APP_RECONNECT_DEF=$(declare -f recording_start)
    APP_RECONNECT_DEF=${APP_RECONNECT_DEF/recording_start ()/recording_start_without_reconnect ()}
    eval "$APP_RECONNECT_DEF"

    recording_start() {
        local station_name="$1"

        recording_start_without_reconnect "$station_name" || return $?
        APP_RECONNECT_RECORDING_GUARD=1
        app_reconnect_cancel_pending
    }
fi

if declare -F recording_stop >/dev/null 2>&1 && ! declare -F recording_stop_without_reconnect >/dev/null 2>&1; then
    APP_RECONNECT_DEF=$(declare -f recording_stop)
    APP_RECONNECT_DEF=${APP_RECONNECT_DEF/recording_stop ()/recording_stop_without_reconnect ()}
    eval "$APP_RECONNECT_DEF"

    recording_stop() {
        local status=0
        recording_stop_without_reconnect || status=$?
        APP_RECONNECT_RECORDING_GUARD=0
        return "$status"
    }
fi

if declare -F recording_finalize_after_player_exit >/dev/null 2>&1 && ! declare -F recording_finalize_after_player_exit_without_reconnect >/dev/null 2>&1; then
    APP_RECONNECT_DEF=$(declare -f recording_finalize_after_player_exit)
    APP_RECONNECT_DEF=${APP_RECONNECT_DEF/recording_finalize_after_player_exit ()/recording_finalize_after_player_exit_without_reconnect ()}
    eval "$APP_RECONNECT_DEF"

    recording_finalize_after_player_exit() {
        local status=0
        recording_finalize_after_player_exit_without_reconnect || status=$?
        APP_RECONNECT_RECORDING_EXIT_EVENT=1
        APP_RECONNECT_RECORDING_GUARD=0
        return "$status"
    }
fi

if declare -F ui_message_tick >/dev/null 2>&1 && ! declare -F ui_message_tick_without_reconnect >/dev/null 2>&1; then
    APP_RECONNECT_DEF=$(declare -f ui_message_tick)
    APP_RECONNECT_DEF=${APP_RECONNECT_DEF/ui_message_tick ()/ui_message_tick_without_reconnect ()}
    eval "$APP_RECONNECT_DEF"

    ui_message_tick() {
        local changed=1

        if ui_message_tick_without_reconnect; then
            changed=0
        fi
        if app_reconnect_tick; then
            changed=0
        fi

        return "$changed"
    }
fi

unset APP_RECONNECT_DEF
