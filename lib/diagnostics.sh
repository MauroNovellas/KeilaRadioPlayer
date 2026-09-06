#!/usr/bin/env bash

# Diagnóstico no destructivo de Keila Radio Player v2.1.
#
# Este módulo no instala paquetes ni abre streams de red. Comprueba el entorno,
# las rutas de datos y un mpv local en modo idle con socket IPC propio.

DIAGNOSTICS_OK=0
DIAGNOSTICS_WARN=0
DIAGNOSTICS_FAIL=0

 diagnostics_reset() {
    DIAGNOSTICS_OK=0
    DIAGNOSTICS_WARN=0
    DIAGNOSTICS_FAIL=0
}

diagnostics_ok() {
    printf '[OK] %s\n' "$1"
    DIAGNOSTICS_OK=$((DIAGNOSTICS_OK + 1))
}

diagnostics_warn() {
    printf '[AVISO] %s\n' "$1"
    DIAGNOSTICS_WARN=$((DIAGNOSTICS_WARN + 1))
}

diagnostics_fail() {
    printf '[FALLO] %s\n' "$1"
    DIAGNOSTICS_FAIL=$((DIAGNOSTICS_FAIL + 1))
}

diagnostics_first_line() {
    local text="$1"
    text="${text%%$'\n'*}"
    text="${text//$'\r'/}"
    printf '%s' "$text"
}

diagnostics_command_version() {
    local command_name="$1"
    local output=''

    case "$command_name" in
        mpv) output=$(mpv --version 2>&1 || true) ;;
        socat) output=$(socat -V 2>&1 || true) ;;
        curl) output=$(curl --version 2>&1 || true) ;;
        jq) output=$(jq --version 2>&1 || true) ;;
        fzf) output=$(fzf --version 2>&1 || true) ;;
        tput) output=$(tput -V 2>&1 || true) ;;
        *) return 1 ;;
    esac

    diagnostics_first_line "$output"
}

diagnostics_check_environment() {
    local system=''

    if command -v uname >/dev/null 2>&1; then
        system=$(uname -srmo 2>/dev/null || uname -a 2>/dev/null || true)
    fi

    diagnostics_ok "Keila Radio Player ${KEILA_VERSION:-desconocida}"
    diagnostics_ok "Bash ${BASH_VERSION:-desconocida}"
    if [[ -n "$system" ]]; then
        diagnostics_ok "Sistema: $system"
    else
        diagnostics_warn 'No se pudo identificar el sistema con uname.'
    fi

    if deps_is_termux; then
        diagnostics_ok "Entorno: Termux ${TERMUX_VERSION:-versión desconocida}"
        if deps_termux_needs_repair; then
            diagnostics_fail 'Termux tiene paquetes multimedia sin configurar o dañados.'
        else
            diagnostics_ok 'Estado de paquetes multimedia de Termux correcto.'
        fi
    else
        diagnostics_ok 'Entorno: Unix/Linux estándar.'
    fi
}

diagnostics_check_dependencies() {
    local spec command_name version

    for spec in "${KEILA_DEPENDENCIES[@]}"; do
        IFS='|' read -r command_name _ <<< "$spec"
        if ! command -v "$command_name" >/dev/null 2>&1; then
            diagnostics_fail "Dependencia ausente: $command_name"
            continue
        fi

        version=$(diagnostics_command_version "$command_name" || true)
        if [[ -n "$version" ]]; then
            diagnostics_ok "$command_name: $version"
        else
            diagnostics_warn "$command_name está en PATH, pero no informó su versión."
        fi
    done
}

diagnostics_check_write_dir() {
    local label="$1" dir="$2"
    local probe

    if [[ -z "$dir" ]]; then
        diagnostics_fail "$label: ruta vacía."
        return 1
    fi

    if ! mkdir -p "$dir" 2>/dev/null; then
        diagnostics_fail "$label: no se puede crear $dir"
        return 1
    fi

    probe="$dir/.keila-check.$$.$RANDOM"
    if ! (umask 077; : > "$probe") 2>/dev/null; then
        diagnostics_fail "$label: no se puede escribir en $dir"
        return 1
    fi

    rm -f -- "$probe" 2>/dev/null || true
    diagnostics_ok "$label escribible: $dir"
}

diagnostics_check_data() {
    local base_dir="$1"

    if ! app_init_data; then
        diagnostics_fail 'No se pudieron inicializar configuración, favoritos, estado o grabaciones.'
        return 1
    fi

    diagnostics_ok "Configuración cargada: $KEILA_CONFIG_FILE"
    diagnostics_ok "Favoritos cargados: $KEILA_FAVORITES_FILE"
    diagnostics_ok "Estado: $KEILA_STATE_FILE"

    diagnostics_check_write_dir 'Configuración' "$KEILA_CONFIG_DIR" || true
    diagnostics_check_write_dir 'Estado' "$KEILA_STATE_DIR" || true
    diagnostics_check_write_dir 'Caché' "$KEILA_CACHE_DIR" || true
    diagnostics_check_write_dir 'Grabaciones' "$KEILA_RECORDINGS_DIR" || true
    diagnostics_check_write_dir 'Runtime IPC' "$PLAYER_RUNTIME_DIR" || true

    if [[ "$KEILA_RECORDINGS_DIR" == "$base_dir/grabaciones" ]]; then
        diagnostics_ok 'Carpeta de grabaciones: valor predeterminado junto a Keila.'
    else
        diagnostics_ok "Carpeta de grabaciones personalizada: $KEILA_RECORDINGS_DIR"
    fi
}

diagnostics_check_terminal() {
    local cols='' lines=''

    if [[ -z "${TERM:-}" ]]; then
        diagnostics_warn 'TERM no está definido; no se pueden validar capacidades de terminal.'
        return 0
    fi

    if ! command -v tput >/dev/null 2>&1; then
        return 0
    fi

    cols=$(tput cols 2>/dev/null || true)
    lines=$(tput lines 2>/dev/null || true)

    if [[ "$cols" =~ ^[0-9]+$ && "$lines" =~ ^[0-9]+$ ]]; then
        diagnostics_ok "Terminal: TERM=$TERM, ${cols}x${lines}"
    elif [[ -t 1 ]]; then
        diagnostics_warn "TERM=$TERM, pero tput no pudo obtener las dimensiones."
    else
        diagnostics_warn "Salida no interactiva; TERM=$TERM disponible, dimensiones TUI no comprobadas."
    fi
}

diagnostics_stop_probe_pid() {
    local pid="$1" attempt

    [[ "$pid" =~ ^[0-9]+$ ]] || return 0
    kill -0 "$pid" 2>/dev/null || {
        wait "$pid" 2>/dev/null || true
        return 0
    }

    kill "$pid" 2>/dev/null || true
    for ((attempt = 0; attempt < 10; attempt++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
}

diagnostics_check_mpv_ipc() {
    local socket="$PLAYER_RUNTIME_DIR/diag-${PLAYER_INSTANCE_ID}.sock"
    local pid='' attempt response=''
    local socket_ready=0

    for command_name in mpv socat jq; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            diagnostics_warn 'Prueba IPC omitida porque faltan mpv, socat o jq.'
            return 0
        fi
    done

    rm -f -- "$socket"
    mpv \
        --no-config \
        --really-quiet \
        --no-video \
        --no-terminal \
        --ao=null \
        --idle=yes \
        --input-ipc-server="$socket" \
        >/dev/null 2>&1 &
    pid=$!

    for ((attempt = 0; attempt < 60; attempt++)); do
        if [[ -S "$socket" ]]; then
            socket_ready=1
            break
        fi
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
    done

    if ((socket_ready == 0)); then
        diagnostics_stop_probe_pid "$pid"
        rm -f -- "$socket"
        diagnostics_fail 'mpv no pudo crear un socket IPC local en el runtime de Keila.'
        return 1
    fi

    response=$(
        printf '%s\n' '{"command":["get_property","mpv-version"],"request_id":901}' |
            socat -t 1 - UNIX-CONNECT:"$socket" 2>/dev/null
    ) || true

    if jq -e 'select(.request_id == 901 and .error == "success" and (.data | type) == "string" and (.data | length) > 0)' \
        <<< "$response" >/dev/null 2>&1; then
        local ipc_version
        ipc_version=$(jq -r 'select(.request_id == 901) | .data' <<< "$response" 2>/dev/null || true)
        diagnostics_ok "mpv IPC operativo: ${ipc_version:-respuesta válida}"
    else
        diagnostics_fail 'mpv creó el socket, pero Keila no recibió una respuesta JSON IPC válida.'
    fi

    printf '%s\n' '{"command":["quit"],"request_id":902}' |
        socat -t 1 - UNIX-CONNECT:"$socket" >/dev/null 2>&1 || true
    diagnostics_stop_probe_pid "$pid"
    rm -f -- "$socket"
}

diagnostics_summary() {
    printf '\nResumen: %d OK · %d avisos · %d fallos\n' \
        "$DIAGNOSTICS_OK" "$DIAGNOSTICS_WARN" "$DIAGNOSTICS_FAIL"

    if ((DIAGNOSTICS_FAIL == 0)); then
        printf 'Diagnóstico: Keila está lista para ejecutarse.\n'
        return 0
    fi

    printf 'Diagnóstico: hay problemas que deben corregirse antes de usar Keila con normalidad.\n'
    return 1
}

diagnostics_run() {
    local base_dir="$1"

    diagnostics_reset
    printf 'Keila Radio Player %s - diagnóstico\n\n' "${KEILA_VERSION:-desconocida}"

    diagnostics_check_environment
    diagnostics_check_dependencies
    diagnostics_check_data "$base_dir"
    diagnostics_check_terminal
    diagnostics_check_mpv_ipc

    diagnostics_summary
}
