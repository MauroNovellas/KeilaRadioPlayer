#!/bin/bash

es_termux() {
    [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ]
}

DEPENDENCIAS_LINUX=(
    "cvlc:vlc"
    "fzf:fzf"
    "ip:iproute2"
    "tput:ncurses-bin"
)

DEPENDENCIAS_TERMUX=(
    "vlc:vlc"
    "fzf:fzf"
    "tput:ncurses"
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
        termux)
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

comprobar_dependencias() {
    local gestor deps bin pkg

    gestor=$(detectar_gestor_paquetes)

    if [ -z "$gestor" ]; then
        echo "❌ No se pudo detectar un gestor de paquetes compatible."
        exit 1
    fi

    if [ "$gestor" = "termux" ]; then
        deps=("${DEPENDENCIAS_TERMUX[@]}")
        echo "📱 Entorno Termux detectado"
    else
        deps=("${DEPENDENCIAS_LINUX[@]}")
    fi

    for dep in "${deps[@]}"; do
        IFS=":" read -r bin pkg <<< "$dep"

        if ! command -v "$bin" >/dev/null; then
            echo "⚠️ Falta dependencia: $bin"
            echo "→ Instalando: $pkg"

            if ! instalar_paquete "$gestor" "$pkg"; then
                echo "❌ No se pudo instalar $pkg"
                exit 1
            fi
        fi
    done

    if [ "$gestor" = "termux" ]; then
        echo
        echo "ℹ️ Nota Termux:"
        echo "  - Asegúrate de tener audio configurado (pulseaudio)"
        echo "  - Algunas emisoras pueden no sonar"
        echo
    fi
}

detectar_gestor_paquetes() {
    if es_termux; then
        echo "termux"
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
