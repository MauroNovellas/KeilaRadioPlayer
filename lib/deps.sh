#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

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
        sudo -n "$@"
    else
        printf 'Keila necesita privilegios de administrador para instalar dependencias.\n' >&2
        return 1
    fi
}

deps_describe_command() {
    case "$1" in
        mpv) printf 'Reproduce el audio de las emisoras y grabaciones.' ;;
        socat) printf 'Comunica Keila con el reproductor para controlar el audio.' ;;
        curl) printf 'Descarga el catálogo, metadatos y logos de las emisoras.' ;;
        jq) printf 'Lee los datos JSON del catálogo y del reproductor.' ;;
        fzf) printf 'Permite usar el selector externo de búsqueda de emisoras.' ;;
        tput) printf 'Controla colores, cursor y tamaño de la terminal.' ;;
        *) printf 'Herramienta necesaria para ejecutar Keila.' ;;
    esac
}

deps_show_manual_command() {
    local manager=$1
    ((${#KEILA_MISSING_PACKAGES[@]})) || return 0
    printf 'Puedes instalarlas por tu cuenta con: ' >&2
    case "$manager" in
        pkg) printf 'pkg install' >&2 ;;
        apt) printf 'sudo apt-get install' >&2 ;;
        pacman) printf 'sudo pacman -S --needed' >&2 ;;
        dnf) printf 'sudo dnf install' >&2 ;;
        *) return 1 ;;
    esac
    printf ' %q' "${KEILA_MISSING_PACKAGES[@]}" >&2
    printf '\n' >&2
}

deps_confirm_changes() {
    local manager=$1 repair=$2 command_name spec package answer suffix=''
    printf '\nKeila necesita preparar estas dependencias:\n' >&2
    for command_name in "${KEILA_MISSING_COMMANDS[@]}"; do
        package=$command_name
        for spec in "${KEILA_DEPENDENCIES[@]}"; do
            [[ $spec == "$command_name|"* ]] || continue
            package=$(deps_package_for_manager "$spec" "$manager") || package=$command_name
            break
        done
        printf '  %s: %s\n' "$package" "$(deps_describe_command "$command_name")" >&2
    done
    ((repair == 0)) || printf '  Reparación: Termux tiene paquetes a medio configurar o bibliotecas dañadas.\n' >&2
    printf 'El gestor instalará también las bibliotecas necesarias para esos paquetes.\n' >&2
    if [[ $manager == pkg ]]; then
        printf 'En Termux, una reparación puede actualizar el entorno completo y configurar paquetes pendientes.\n' >&2
        suffix=' y la posible reparación de Termux'
    else
        printf 'La instalación puede solicitar tu contraseña de administrador.\n' >&2
    fi
    # Una tubería (incluso yes) nunca equivale al consentimiento de una persona.
    if [[ ! -t 0 ]]; then
        printf 'Sin terminal interactiva: no se instalará ni reparará ningún paquete.\n' >&2
        return 1
    fi
    printf '¿Quieres continuar con la instalación%s? [s/N] ' "$suffix" >&2
    if ! IFS= read -r answer; then
        printf '\nInstalación cancelada. No se han modificado paquetes.\n' >&2
        return 1
    fi
    answer=${answer,,}
    case "$answer" in
        s|si|sí|y|yes) return 0 ;;
        *) printf 'Instalación cancelada. No se han modificado paquetes.\n' >&2; return 1 ;;
    esac
}

deps_authorize_root() {
    [[ $1 == pkg ]] && return 0
    ((EUID == 0)) && return 0
    if ! command -v sudo >/dev/null 2>&1; then
        printf 'Keila necesita privilegios de administrador para instalar dependencias.\n' >&2
        return 1
    fi
    # La autenticación debe verse; no enviarla al registro silencioso.
    sudo -v
}

deps_apply_changes() {
    local manager=$1 repair=$2 log status=0
    deps_authorize_root "$manager" || return 1
    log=$(umask 077; mktemp "${TMPDIR:-/tmp}/keila-deps.XXXXXX") || {
        printf 'No se pudo crear el registro de instalación. No se han modificado paquetes.\n' >&2
        return 1
    }
    printf 'Preparando dependencias… Esto puede tardar unos minutos.\n' >&2
    # Guardar la salida completa, pero mantener visible cualquier fallo y su
    # registro privado. No inicia la TUI hasta terminar esta preparación.
    {
        if ((repair)) && ! deps_termux_repair; then status=1; fi
        if ((status == 0)); then
            deps_install_packages "$manager" "${KEILA_MISSING_PACKAGES[@]}" || status=1
        fi
        if ((status == 0)); then deps_verify || status=1; fi
    } > "$log" 2>&1 </dev/null
    if ((status)); then
        printf 'No se pudieron preparar las dependencias. Últimos mensajes:\n' >&2
        # El log de un gestor también es entrada externa: no emitir controles
        # de terminal ni secuencias de escape sobre la pantalla.
        tail -n 12 -- "$log" | LC_ALL=C tr -cd '\11\12\40-\176' >&2
        printf '\nRegistro completo: %s\n' "$log" >&2
        if [[ $manager == pkg ]]; then
            printf 'Si falla el repositorio, prueba termux-change-repo y cambia el mirror principal.\n' >&2
        fi
        return 1
    fi
    rm -f -- "$log"
    printf 'Dependencias listas.\n' >&2
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
        -y -q -o Dpkg::Use-Pty=0 \
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
    if ! deps_termux_apt_get update; then
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
            # Actualizar solo índices antes de instalar; un índice antiguo no
            # debe provocar por sí solo una actualización de todo Termux.
            deps_termux_apt_get update || return 1
            if ! deps_termux_apt_get install "${packages[@]}"; then
                printf 'La instalación falló; reparando Termux y reintentando una vez...\n' >&2
                deps_termux_repair || return 1
                deps_termux_apt_get install "${packages[@]}"
            fi
            ;;
        apt)
            deps_run_root apt-get -q update &&
                deps_run_root env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none \
                    apt-get -q -y -o Dpkg::Use-Pty=0 \
                    -o Dpkg::Options::="--force-confdef" \
                    -o Dpkg::Options::="--force-confold" install "${packages[@]}"
            ;;
        pacman)
            deps_run_root pacman -S --needed --noconfirm --noprogressbar "${packages[@]}"
            ;;
        dnf)
            deps_run_root dnf -q install -y "${packages[@]}"
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
    local manager repair=0
    manager=$(deps_detect_manager)

    # Reparamos también instalaciones parciales en las que el ejecutable de mpv
    # ya existe pero ffmpeg/dpkg siguen sin estar configurados correctamente.
    if [[ "$manager" == "pkg" ]] && deps_termux_needs_repair; then
        repair=1
    fi

    deps_collect_missing "$manager"
    if ((${#KEILA_MISSING_COMMANDS[@]} == 0 && repair == 0)); then
        deps_verify
        return $?
    fi

    if [[ -z "$manager" ]]; then
        printf 'Faltan dependencias: %s\n' "${KEILA_MISSING_COMMANDS[*]}" >&2
        printf 'No encuentro un gestor de paquetes compatible para instalarlas automáticamente.\n' >&2
        return 1
    fi

    if ((${#KEILA_MISSING_COMMANDS[@]} > 0 && ${#KEILA_MISSING_PACKAGES[@]} == 0)); then
        printf 'No conozco los paquetes necesarios para este sistema.\n' >&2
        return 1
    fi

    if ! deps_confirm_changes "$manager" "$repair"; then
        deps_show_manual_command "$manager"
        if ((repair)); then printf 'Para reparar Termux manualmente: pkg update && pkg upgrade\n' >&2; fi
        return 1
    fi
    deps_apply_changes "$manager" "$repair"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    deps_ensure
fi
