#!/bin/bash

##############################################################################
# DEPENDENCIAS
# formato:
# bin:paquete_linux:paquete_termux
##############################################################################

DEPENDENCIAS=(
    "mpv:mpv:mpv"
    "fzf:fzf:fzf"
    "ip:iproute2:iproute2"
    "tput:ncurses-bin:ncurses"
    "socat:socat:socat"
)

##############################################################################
# DETECCIÓN DE ENTORNO
##############################################################################

es_termux() {
    [ -n "$TERMUX_VERSION" ] || command -v termux-info >/dev/null
}

##############################################################################
# DETECCIÓN DE GESTOR DE PAQUETES
##############################################################################

detectar_gestor_paquetes() {
    if es_termux; then
        echo "pkg"
    elif command -v apt >/dev/null; then
        echo "apt"
    elif command -v pacman >/dev/null; then
        echo "pacman"
    elif command -v dnf >/dev/null; then
        echo "dnf"
    else
        echo ""
    fi
}

##############################################################################
# INSTALACIÓN
##############################################################################

instalar_paquete() {
    local gestor="$1"
    local paquete="$2"

    case "$gestor" in
        pkg)
            pkg install -y "$paquete"
            ;;
        apt)
            sudo apt update && sudo apt install -y "$paquete"
            ;;
        pacman)
            sudo pacman -Sy --noconfirm "$paquete"
            ;;
        dnf)
            sudo dnf install -y "$paquete"
            ;;
        *)
            return 1
            ;;
    esac
}

##############################################################################
# COMPROBACIÓN
##############################################################################

comprobar_dependencias() {
    local gestor
    gestor=$(detectar_gestor_paquetes)

    if [ -z "$gestor" ]; then
        echo "No se pudo detectar un gestor de paquetes compatible."
        echo "Instala manualmente las dependencias."
        return 1
    fi

    for dep in "${DEPENDENCIAS[@]}"; do
        IFS=":" read -sr bin pkg_linux pkg_termux <<< "$dep"

        if command -v "$bin" >/dev/null; then
            continue
        fi

        echo "Dependencia faltante: $bin"

        if es_termux; then
            paquete="$pkg_termux"
        else
            paquete="$pkg_linux"
        fi

        if [ -z "$paquete" ]; then
            echo "No hay paquete conocido para instalar $bin en este entorno."
            return 1
        fi

        echo "Instalando paquete: $paquete"

        if ! instalar_paquete "$gestor" "$paquete"; then
            echo "No se pudo instalar $paquete"
            return 1
        fi
    done
}

##############################################################################
# EJECUCIÓN DIRECTA
##############################################################################

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    comprobar_dependencias
fi
