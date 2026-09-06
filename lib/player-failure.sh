#!/usr/bin/env bash

# Estado estructurado del último fallo significativo del motor de reproducción.
#
# Mantiene códigos estables separados de los mensajes de la TUI. No persiste
# URLs ni crea logs; describe únicamente el fallo vivo de la sesión actual.

PLAYER_FAILURE_REASON="${PLAYER_FAILURE_REASON:-}"
PLAYER_FAILURE_DETAIL="${PLAYER_FAILURE_DETAIL:-}"
PLAYER_FAILURE_AT="${PLAYER_FAILURE_AT:-0}"
PLAYER_FAILURE_EXIT_STATUS="${PLAYER_FAILURE_EXIT_STATUS:-}"
PLAYER_FAILURE_SEQUENCE="${PLAYER_FAILURE_SEQUENCE:-0}"
PLAYER_LAST_IPC_ERROR="${PLAYER_LAST_IPC_ERROR:-}"

player_failure_now() {
    printf '%s\n' "${EPOCHSECONDS:-$(date +%s)}"
}

player_failure_clear() {
    PLAYER_FAILURE_REASON=""
    PLAYER_FAILURE_DETAIL=""
    PLAYER_FAILURE_AT=0
    PLAYER_FAILURE_EXIT_STATUS=""
    PLAYER_LAST_IPC_ERROR=""
}

player_failure_set() {
    local reason="$1"
    local detail="${2:-}"
    local exit_status="${3:-}"

    [[ "$reason" =~ ^[a-z0-9_]+$ ]] || reason='unknown'

    PLAYER_FAILURE_REASON="$reason"
    PLAYER_FAILURE_DETAIL="$detail"
    PLAYER_FAILURE_AT=$(player_failure_now)
    PLAYER_FAILURE_EXIT_STATUS="$exit_status"
    PLAYER_FAILURE_SEQUENCE=$((PLAYER_FAILURE_SEQUENCE + 1))
}

player_failure_description() {
    local reason="${1:-$PLAYER_FAILURE_REASON}"

    case "$reason" in
        '') printf 'sin fallo' ;;
        invalid_url) printf 'URL de emisora no válida' ;;
        runtime_dir) printf 'runtime IPC no disponible' ;;
        startup_socket) printf 'mpv no inicializó el socket IPC' ;;
        ipc_payload) printf 'comando IPC no válido' ;;
        ipc_transport) printf 'fallo de transporte IPC' ;;
        ipc_rejected) printf 'mpv rechazó el comando IPC' ;;
        ipc_response) printf 'respuesta IPC inválida' ;;
        process_exit) printf 'mpv terminó inesperadamente' ;;
        stream_stalled) printf 'stream sin progreso' ;;
        reconnect_retry) printf 'reintento de reconexión en curso' ;;
        reconnect_start_timeout) printf 'reconexión sin audio dentro del plazo' ;;
        reconnect_exhausted) printf 'reconexión automática agotada' ;;
        *) printf 'fallo del reproductor: %s' "$reason" ;;
    esac
}

player_failure_ipc_error() {
    local response="$1" request_id="$2"

    [[ "$request_id" =~ ^[0-9]+$ ]] || return 1
    jq -r --argjson request_id "$request_id" '
        select(type == "object" and .request_id? == $request_id)
        | .error // empty
    ' <<< "$response" 2>/dev/null | head -n 1
}

# Reemplaza únicamente la envoltura de player_ipc. Conserva el intercambio y la
# validación base, pero clasifica por separado payload, transporte y rechazo.
if declare -F player_ipc >/dev/null 2>&1; then
    player_ipc() {
        local payload="$1"
        local request_id response ipc_error

        PLAYER_IPC_REQUEST_ID=$((PLAYER_IPC_REQUEST_ID + 1))
        request_id="$PLAYER_IPC_REQUEST_ID"

        if ! payload=$(jq -c --argjson request_id "$request_id" '.request_id = $request_id' <<< "$payload" 2>/dev/null); then
            player_failure_set ipc_payload 'No se pudo construir el comando JSON para mpv.'
            return 1
        fi

        if ! response=$(player_ipc_exchange "$payload"); then
            player_failure_set ipc_transport 'No se pudo intercambiar el comando con el socket de mpv.'
            return 1
        fi

        if player_ipc_response_success "$response" "$request_id"; then
            case "$PLAYER_FAILURE_REASON" in
                ipc_*) player_failure_clear ;;
            esac
            return 0
        fi

        ipc_error=$(player_failure_ipc_error "$response" "$request_id" || true)
        if [[ -n "$ipc_error" && "$ipc_error" != 'success' ]]; then
            PLAYER_LAST_IPC_ERROR="$ipc_error"
            player_failure_set ipc_rejected "$ipc_error"
        else
            player_failure_set ipc_response 'La respuesta no contenía el request_id esperado con error=success.'
        fi
        return 1
    }
fi

# Envolvemos el arranque para distinguir URL/ruta inválida de un mpv que no
# alcanza a crear el socket. app-reconnect se carga después y clonará esta capa.
if declare -F player_start >/dev/null 2>&1 && ! declare -F player_start_without_failure_state >/dev/null 2>&1; then
    PLAYER_FAILURE_DEF=$(declare -f player_start)
    PLAYER_FAILURE_DEF=${PLAYER_FAILURE_DEF/player_start ()/player_start_without_failure_state ()}
    eval "$PLAYER_FAILURE_DEF"

    player_start() {
        local name="$1" url="$2" status=0

        if [[ -z "$url" ]]; then
            player_failure_set invalid_url 'La URL de la emisora está vacía.'
            return 1
        fi

        if ! mkdir -p "$PLAYER_RUNTIME_DIR" 2>/dev/null; then
            player_failure_set runtime_dir "No se pudo crear $PLAYER_RUNTIME_DIR"
            return 1
        fi

        player_start_without_failure_state "$name" "$url" || status=$?
        if ((status != 0)); then
            player_failure_set startup_socket 'mpv no pudo inicializar el socket IPC.' "${PLAYER_LAST_EXIT_STATUS:-}"
            return "$status"
        fi

        player_failure_clear
        return 0
    }
fi

# Una salida recogida por el launcher es inesperada por definición: los stops
# intencionales consumen su wait dentro de player_stop y no pasan por aquí.
if declare -F player_collect_exit_status >/dev/null 2>&1 && ! declare -F player_collect_exit_status_without_failure_state >/dev/null 2>&1; then
    PLAYER_FAILURE_DEF=$(declare -f player_collect_exit_status)
    PLAYER_FAILURE_DEF=${PLAYER_FAILURE_DEF/player_collect_exit_status ()/player_collect_exit_status_without_failure_state ()}
    eval "$PLAYER_FAILURE_DEF"

    player_collect_exit_status() {
        local status

        player_collect_exit_status_without_failure_state || return $?
        status="${PLAYER_LAST_EXIT_STATUS:-}"
        player_failure_set process_exit "mpv terminó con código ${status:-desconocido}." "$status"
        return 0
    }
fi

# Un stop explícito cancela cualquier fallo vivo. Si el stop forma parte de una
# política automática, la capa de reconexión fijará después el motivo preciso.
if declare -F player_stop >/dev/null 2>&1 && ! declare -F player_stop_without_failure_state >/dev/null 2>&1; then
    PLAYER_FAILURE_DEF=$(declare -f player_stop)
    PLAYER_FAILURE_DEF=${PLAYER_FAILURE_DEF/player_stop ()/player_stop_without_failure_state ()}
    eval "$PLAYER_FAILURE_DEF"

    player_stop() {
        local status=0

        player_stop_without_failure_state || status=$?
        player_failure_clear
        return "$status"
    }
fi

unset PLAYER_FAILURE_DEF
