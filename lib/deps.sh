#!/usr/bin/env bash

# Dependencias de ejecución de Keila Radio Player v2.
# Formato: comando|debian|termux|arch|fedora
KEILA_DEPENDENCIES=(
    "mpv|mpv|mpv|mpv|mpv"
    "socat|socat|socat|socat|socat"
    "curl|curl|curl|curl|curl"
    "jq|jq|jq|jq|jq"
    "fzf|fzf|fzf|fzf|fzf"
    "tput|ncurses-bin|ncurses-utils|ncurses|ncurses"
)

deps_is_termux() {
    [[ -n "${TERMUX_VERSION:-}" ]] || [[ "${PREFIX:-}" == *com.termux* ]]
}

deps_detect_manager() {
    if deps_is_termux && command -v pkg >/dev/null 2>&1; then
        printf 'pkg\n'
    elif command -v apt-get >/dev/null 2>&1; then
        printf 'apt\n'
    elif command -v pacman >/dev/null 2>&1; then
        printf 'pacman\n'
    elif command -v dnf >/dev/null 2>&1; then
        printf 'dnf\n'
    else
        printf '\n'
    fi
}

deps_package_for_manager() {
    local spec="$1"
    local manager="$2"
    local command_name debian termux arch fedora

    IFS='|' read -r command_name debian termux arch fedora <<< "$spec"

    case "$manager" in
        pkg) printf '%s\n' "$termux" ;;
        apt) printf '%s\n' "$debian" ;;
        pacman) printf '%s\n' "$arch" ;;
        dnf) printf '%s\n' "$fedora" ;;
        *) return 1 ;;
    esac
}

deps_run_root() {
    if ((EUID == 0)); then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        printf 'Keila necesita privilegios de administrador para instalar dependencias.\n' >&2
        return 1
    fi
}

deps_collect_missing() {
    KEILA_MISSING_COMMANDS=()
    KEILA_MISSING_PACKAGES=()

    local spec command_name package
    local manager="$1"

    for spec in "${KEILA_DEPENDENCIES[@]}"; do
        IFS='|' read -r command_name _ <<< "$spec"

        if command -v "$command_name" >/dev/null 2>&1; then
            continue
        fi

        KEILA_MISSING_COMMANDS+=("$command_name")
        package=$(deps_package_for_manager "$spec" "$manager") || continue

        local already=0 existing
        for existing in "${KEILA_MISSING_PACKAGES[@]}"; do
            if [[ "$existing" == "$package" ]]; then
                already=1
                break
            fi
        done

        ((already)) || KEILA_MISSING_PACKAGES+=("$package")
    done
}

deps_termux_repair() {
    printf 'Preparando y reparando el entorno de paquetes de Termux...\n'

    # Termux no soporta upgrades parciales de forma fiable: paquetes multimedia
    # como ffmpeg/mpv pueden quedar enlazados contra versiones antiguas de sus
    # librerías. Antes de instalar Keila dejamos todo el entorno consistente.
    if ! DEBIAN_FRONTEND=noninteractive pkg update -y; then
        printf 'No se pudieron actualizar los índices de Termux.\n' >&2
        return 1
    fi

    if ! DEBIAN_FRONTEND=noninteractive pkg upgrade -y; then
        printf 'La actualización normal de Termux encontró paquetes rotos; intentando repararlos...\n' >&2

        if command -v apt >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt --fix-broken install -y || true
        fi

        if command -v dpkg >/dev/null 2>&1; then
            dpkg --configure -a || true
        fi

        # Tras la reparación hacemos un segundo intento completo. Si vuelve a
        # fallar, dejamos el error visible para no ocultar un problema de mirror
        # o de la propia instalación de Termux.
        DEBIAN_FRONTEND=noninteractive pkg upgrade -y || return 1
    fi

    if command -v dpkg >/dev/null 2>&1; then
        if ! dpkg --configure -a; then
            printf 'Quedan paquetes sin configurar; intentando una última reparación...\n' >&2
            if command -v apt >/dev/null 2>&1; then
                DEBIAN_FRONTEND=noninteractive apt --fix-broken install -y || return 1
            fi
            dpkg --configure -a || return 1
        fi
    fi
}

deps_install_packages() {
    local manager="$1"
    shift
    local -a packages=("$@")

    ((${#packages[@]} > 0)) || return 0

    case "$manager" in
        pkg)
            deps_termux_repair || return 1

            if ! DEBIAN_FRONTEND=noninteractive pkg install -y "${packages[@]}"; then
                printf 'La instalación falló; reparando Termux y reintentando una vez...\n' >&2
                deps_termux_repair || return 1
                DEBIAN_FRONTEND=noninteractive pkg install -y "${packages[@]}"
            fi
            ;;
        apt)
            if ((EUID == 0)); then
                apt-get update &&
                    DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
            else
                deps_run_root apt-get update &&
                    deps_run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
            fi
            ;;
        pacman)
            deps_run_root pacman -S --needed --noconfirm "${packages[@]}"
            ;;
        dnf)
            deps_run_root dnf install -y "${packages[@]}"
            ;;
        *)
            return 1
            ;;
    esac
}

deps_verify() {
    local spec command_name missing=0

    for spec in "${KEILA_DEPENDENCIES[@]}"; do
        IFS='|' read -r command_name _ <<< "$spec"
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'Dependencia no disponible después de la instalación: %s\n' "$command_name" >&2
            missing=1
        fi
    done

    ((missing == 0))
}

deps_ensure() {
    local manager
    manager=$(deps_detect_manager)

    deps_collect_missing "$manager"
    ((${#KEILA_MISSING_COMMANDS[@]} == 0)) && return 0

    printf 'Keila necesita instalar: %s\n' "${KEILA_MISSING_COMMANDS[*]}"

    if [[ -z "$manager" ]]; then
        printf 'No encuentro un gestor de paquetes compatible para instalarlas automáticamente.\n' >&2
        return 1
    fi

    if ((${#KEILA_MISSING_PACKAGES[@]} == 0)); then
        printf 'No conozco los paquetes necesarios para este sistema.\n' >&2
        return 1
    fi

    printf 'Instalando automáticamente con %s: %s\n' "$manager" "${KEILA_MISSING_PACKAGES[*]}"

    if ! deps_install_packages "$manager" "${KEILA_MISSING_PACKAGES[@]}"; then
        printf 'No se pudieron instalar todas las dependencias de Keila.\n' >&2
        if [[ "$manager" == "pkg" ]]; then
            printf 'Si Termux sigue fallando, ejecuta termux-change-repo y cambia el mirror principal; después vuelve a abrir Keila.\n' >&2
        fi
        return 1
    fi

    deps_verify
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    deps_ensure
fi
