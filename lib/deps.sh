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

deps_termux_needs_repair() {
    deps_is_termux || return 1

    # dpkg --audit puede detectar paquetes desempaquetados pero todavía no
    # configurados, justo el estado en el que puede quedar mpv si falla ffmpeg.
    if command -v dpkg >/dev/null 2>&1; then
        local audit
        audit=$(dpkg --audit 2>/dev/null || true)
        [[ -n "$audit" ]] && return 0
    fi

    # Un ejecutable puede existir en PATH aunque sus librerías estén rotas.
    # Comprobamos los dos componentes multimedia más sensibles de Termux.
    if command -v ffmpeg >/dev/null 2>&1 && ! ffmpeg -version >/dev/null 2>&1; then
        return 0
    fi

    if command -v mpv >/dev/null 2>&1 && ! mpv --version >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# En Termux usamos apt-get directamente para automatización. pkg es un wrapper
# pensado para uso interactivo y puede dejar pasar preguntas de dpkg sobre
# archivos de configuración modificados. Estas opciones conservan siempre la
# configuración local y aceptan automáticamente la opción por defecto.
deps_termux_apt_get() {
    DEBIAN_FRONTEND=noninteractive apt-get \
        -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "$@" </dev/null
}

deps_termux_dpkg_configure() {
    DEBIAN_FRONTEND=noninteractive dpkg \
        --force-confdef \
        --force-confold \
        --configure -a </dev/null
}

deps_termux_repair() {
    printf 'Preparando y reparando el entorno de paquetes de Termux...\n'

    # Termux recomienda mantener todos los paquetes actualizados conjuntamente:
    # paquetes multimedia como ffmpeg/mpv pueden fallar si quedan mezcladas
    # versiones nuevas y antiguas de sus librerías.
    if ! DEBIAN_FRONTEND=noninteractive apt-get update </dev/null; then
        printf 'No se pudieron actualizar los índices de Termux.\n' >&2
        return 1
    fi

    if ! deps_termux_apt_get upgrade; then
        printf 'La actualización normal de Termux encontró paquetes rotos; intentando repararlos...\n' >&2

        deps_termux_apt_get --fix-broken install || true

        if command -v dpkg >/dev/null 2>&1; then
            deps_termux_dpkg_configure || true
        fi

        # Tras la reparación hacemos un segundo intento completo. Si vuelve a
        # fallar, dejamos el error visible para no ocultar un problema de mirror
        # o de la propia instalación de Termux.
        deps_termux_apt_get upgrade || return 1
    fi

    if command -v dpkg >/dev/null 2>&1; then
        if ! deps_termux_dpkg_configure; then
            printf 'Quedan paquetes sin configurar; intentando una última reparación...\n' >&2
            deps_termux_apt_get --fix-broken install || return 1
            deps_termux_dpkg_configure || return 1
        fi
    fi

    if deps_termux_needs_repair; then
        printf 'Termux sigue teniendo paquetes multimedia sin configurar correctamente.\n' >&2
        return 1
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

            if ! deps_termux_apt_get install "${packages[@]}"; then
                printf 'La instalación falló; reparando Termux y reintentando una vez...\n' >&2
                deps_termux_repair || return 1
                deps_termux_apt_get install "${packages[@]}"
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

    if deps_is_termux && deps_termux_needs_repair; then
        printf 'El gestor de paquetes de Termux sigue en un estado inconsistente.\n' >&2
        missing=1
    fi

    ((missing == 0))
}

deps_ensure() {
    local manager
    manager=$(deps_detect_manager)

    # Reparamos también instalaciones parciales en las que el ejecutable de mpv
    # ya existe pero ffmpeg/dpkg siguen sin estar configurados correctamente.
    if [[ "$manager" == "pkg" ]] && deps_termux_needs_repair; then
        printf 'Keila ha detectado una instalación de Termux a medio configurar.\n'
        if ! deps_termux_repair; then
            printf 'No se pudo reparar automáticamente Termux.\n' >&2
            printf 'Prueba termux-change-repo, cambia el mirror principal y vuelve a ejecutar Keila.\n' >&2
            return 1
        fi
    fi

    deps_collect_missing "$manager"
    if ((${#KEILA_MISSING_COMMANDS[@]} == 0)); then
        deps_verify
        return $?
    fi

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
