#!/bin/bash

DEPENDENCIAS=(
    "mpv:mpv"
    "fzf:fzf"
    "ip:iproute2"
    "tput:ncurses-bin"
)

detectar_gestor_paquetes() {
    if command -v apt >/dev/null; then
        echo "apt"
    elif command -v pacman >/dev/null; then
        echo "pacman"
    elif command -v dnf >/dev/null; then
        echo "dnf"
    else
        echo ""
    fi
}

instalar_paquete() {
    local gestor="$1"
    local paquete="$2"

    case "$gestor" in
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

comprobar_dependencias() {
    local gestor
    gestor=$(detectar_gestor_paquetes)

    if [ -z "$gestor" ]; then
        echo "No se pudo detectar un gestor de paquetes compatible."
        echo "Instala manualmente las dependencias."
        exit 1
    fi

    for dep in "${DEPENDENCIAS[@]}"; do
        IFS=":" read -r bin pkg <<< "$dep"

        if ! command -v "$bin" >/dev/null; then
            echo "⚠️ Dependencia faltante: $bin"
            echo "→ Instalando paquete: $pkg"

            if ! instalar_paquete "$gestor" "$pkg"; then
                echo "No se pudo instalar $pkg"
                exit 1
            fi
        fi
    done
}
