#!/usr/bin/env bash

# Integra la reconexión automática con el estado estructurado de fallos.
# Se carga después de app-reconnect.sh y no cambia tiempos, mensajes ni política.

if declare -F app_reconnect_message_retry_or_exhausted >/dev/null 2>&1 && ! declare -F app_reconnect_message_retry_or_exhausted_without_failure_state >/dev/null 2>&1; then
    APP_RECONNECT_FAILURE_DEF=$(declare -f app_reconnect_message_retry_or_exhausted)
    APP_RECONNECT_FAILURE_DEF=${APP_RECONNECT_FAILURE_DEF/app_reconnect_message_retry_or_exhausted ()/app_reconnect_message_retry_or_exhausted_without_failure_state ()}
    eval "$APP_RECONNECT_FAILURE_DEF"

    app_reconnect_message_retry_or_exhausted() {
        local name="$1" now="${2:-$(app_reconnect_now)}"
        local status=0

        app_reconnect_message_retry_or_exhausted_without_failure_state "$name" "$now" || status=$?
        if ((APP_RECONNECT_EXHAUSTED)); then
            player_failure_set reconnect_exhausted \
                "No se pudo recuperar $name tras ${APP_RECONNECT_ATTEMPTS} intentos." \
                "${PLAYER_LAST_EXIT_STATUS:-}"
        fi
        return "$status"
    }
fi

# El arranque base limpia fallos al crear correctamente el socket. Durante una
# reconexión mantenemos un motivo vivo hasta que vuelva a existir audio real.
if declare -F app_reconnect_start_attempt >/dev/null 2>&1 && ! declare -F app_reconnect_start_attempt_without_failure_state >/dev/null 2>&1; then
    APP_RECONNECT_FAILURE_DEF=$(declare -f app_reconnect_start_attempt)
    APP_RECONNECT_FAILURE_DEF=${APP_RECONNECT_FAILURE_DEF/app_reconnect_start_attempt ()/app_reconnect_start_attempt_without_failure_state ()}
    eval "$APP_RECONNECT_FAILURE_DEF"

    app_reconnect_start_attempt() {
        local reason="${1:-retry}" now="${2:-$(app_reconnect_now)}"
        local status=0

        app_reconnect_start_attempt_without_failure_state "$reason" "$now" || status=$?

        # Si player_start falló antes de crear socket, conserva su motivo más
        # preciso (startup_socket/runtime_dir/etc.). Solo anotamos reconexión
        # cuando el nuevo mpv está vivo y esperando audio.
        if ((status == 0 && APP_RECONNECT_WAITING)) && player_is_running; then
            case "$reason" in
                stall)
                    player_failure_set stream_stalled \
                        "Sin progreso durante ${APP_RECONNECT_STALL_TIMEOUT}s; reconectando intento ${APP_RECONNECT_ATTEMPTS}/${APP_RECONNECT_MAX_ATTEMPTS}."
                    ;;
                exit)
                    player_failure_set process_exit \
                        "mpv terminó; reconectando intento ${APP_RECONNECT_ATTEMPTS}/${APP_RECONNECT_MAX_ATTEMPTS}." \
                        "${PLAYER_LAST_EXIT_STATUS:-}"
                    ;;
                *)
                    player_failure_set reconnect_retry \
                        "Reintentando conexión ${APP_RECONNECT_ATTEMPTS}/${APP_RECONNECT_MAX_ATTEMPTS}."
                    ;;
            esac
        fi

        return "$status"
    }
fi

# Detecta transiciones de la política sin duplicar su lógica: recuperación real,
# timeout sin audio, agotamiento y bloqueo de reconexión durante una grabación.
if declare -F app_reconnect_tick >/dev/null 2>&1 && ! declare -F app_reconnect_tick_without_failure_state >/dev/null 2>&1; then
    APP_RECONNECT_FAILURE_DEF=$(declare -f app_reconnect_tick)
    APP_RECONNECT_FAILURE_DEF=${APP_RECONNECT_FAILURE_DEF/app_reconnect_tick ()/app_reconnect_tick_without_failure_state ()}
    eval "$APP_RECONNECT_FAILURE_DEF"

    app_reconnect_tick() {
        local before_waiting=$APP_RECONNECT_WAITING
        local before_exhausted=$APP_RECONNECT_EXHAUSTED
        local before_recording_warned=$APP_RECONNECT_RECORDING_WARNED
        local before_attempts=$APP_RECONNECT_ATTEMPTS
        local status=0

        app_reconnect_tick_without_failure_state || status=$?

        if ((before_recording_warned == 0 && APP_RECONNECT_RECORDING_WARNED)); then
            player_failure_set stream_stalled \
                'El stream dejó de avanzar durante una grabación; la reconexión automática quedó bloqueada para proteger el archivo.'
        fi

        if ((before_waiting && APP_RECONNECT_WAITING == 0)); then
            if player_is_running && ((PLAYER_STREAM_READY)) && \
                ((APP_RECONNECT_ATTEMPTS == 0 && APP_RECONNECT_NEXT_AT == 0 && APP_RECONNECT_EXHAUSTED == 0)); then
                player_failure_clear
            elif ((APP_RECONNECT_EXHAUSTED)); then
                player_failure_set reconnect_exhausted \
                    "No se pudo recuperar $PLAYER_NAME tras ${before_attempts} intentos." \
                    "${PLAYER_LAST_EXIT_STATUS:-}"
            elif ((APP_RECONNECT_NEXT_AT > 0)); then
                player_failure_set reconnect_start_timeout \
                    "El intento ${before_attempts}/${APP_RECONNECT_MAX_ATTEMPTS} abrió mpv pero no alcanzó audio real dentro de ${APP_RECONNECT_START_TIMEOUT}s."
            fi
        elif ((before_exhausted == 0 && APP_RECONNECT_EXHAUSTED)); then
            player_failure_set reconnect_exhausted \
                "No se pudo recuperar $PLAYER_NAME tras ${APP_RECONNECT_ATTEMPTS} intentos." \
                "${PLAYER_LAST_EXIT_STATUS:-}"
        fi

        return "$status"
    }
fi

unset APP_RECONNECT_FAILURE_DEF
