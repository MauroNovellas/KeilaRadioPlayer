#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Dobles de gestores: nunca instalar, reparar ni pedir sudo reales.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/lib/deps.sh"
task_tmp=$(mktemp -d)
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

for manager in apt pkg pacman dnf; do
    for spec in "${KEILA_DEPENDENCIES[@]}"; do
        IFS='|' read -r name _ <<< "$spec"
        [[ -n $(deps_package_for_manager "$spec" "$manager") ]] || fail 'paquete sin mapear'
        [[ -n $(deps_describe_command "$name") ]] || fail 'descripción ausente'
    done
done
[[ $(deps_package_for_manager 'tput|ncurses-bin|ncurses-utils|ncurses|ncurses' pkg) == ncurses-utils ]] || fail 'paquete Termux'
(
    command() {
        if [[ ${1:-} == -v && ( ${2:-} == mpv || ${2:-} == tput ) ]]; then return 1; fi
        if [[ ${1:-} == -v && ( ${2:-} == socat || ${2:-} == curl || ${2:-} == jq || ${2:-} == fzf ) ]]; then return 0; fi
        builtin command "$@"
    }
    deps_collect_missing pkg
    [[ ${KEILA_MISSING_COMMANDS[*]} == 'mpv tput' && ${KEILA_MISSING_PACKAGES[*]} == 'mpv ncurses-utils' ]] || fail 'lista de paquetes'
    KEILA_DEPENDENCIES=('mpv|shared|shared|shared|shared' 'tput|shared|shared|shared|shared')
    deps_collect_missing apt
    [[ ${KEILA_MISSING_PACKAGES[*]} == shared ]] || fail 'paquete duplicado'
)
(
    deps_detect_manager() { printf pkg; }
    deps_collect_missing() { KEILA_MISSING_COMMANDS=(mpv jq); KEILA_MISSING_PACKAGES=(mpv jq); }
    deps_termux_needs_repair() { return 0; }
    deps_apply_changes() { fail 'cambios sin consentimiento'; }
    deps_authorize_root() { fail 'autenticación sin consentimiento'; }
    deps_termux_repair() { fail 'reparación sin consentimiento'; }
    if printf 'S\n' | deps_ensure > "$task_tmp/no-tty" 2>&1; then fail 'tubería aceptada'; fi
    text=$(< "$task_tmp/no-tty")
    [[ $text == *'Sin terminal interactiva'* && $text == *'mpv: Reproduce'* && $text == *'jq: Lee'* && $text == *'entorno completo'* && $text == *'pkg install mpv jq'* ]] || fail 'aviso no interactivo'
)
(
    deps_detect_manager() { printf apt; }
    deps_collect_missing() { KEILA_MISSING_COMMANDS=(); KEILA_MISSING_PACKAGES=(); }
    deps_confirm_changes() { fail 'pregunta sin necesidad'; }
    deps_apply_changes() { fail 'instala sin necesidad'; }
    deps_verify() { return 0; }
    deps_ensure > "$task_tmp/ready" 2>&1
    [[ ! -s $task_tmp/ready ]] || fail 'ruido si todo está instalado'
)
(
    TMPDIR=$task_tmp
    KEILA_MISSING_PACKAGES=(mpv jq)
    deps_authorize_root() { printf 'auth\n' >> "$task_tmp/trace"; }
    deps_termux_repair() { printf 'repair\n' >> "$task_tmp/trace"; printf 'NOISY REPAIR\n'; }
    deps_install_packages() { printf 'install %s\n' "$*" >> "$task_tmp/trace"; printf 'NOISY INSTALL\n'; }
    deps_verify() { printf 'verify\n' >> "$task_tmp/trace"; }
    deps_apply_changes pkg 1 > "$task_tmp/success" 2>&1
    [[ $(< "$task_tmp/trace") == $'auth\nrepair\ninstall pkg mpv jq\nverify' ]] || fail 'orden de instalación'
    text=$(< "$task_tmp/success")
    [[ $text == *'Dependencias listas'* && $text != *NOISY* ]] || fail 'salida no silenciosa'
    shopt -s nullglob
    logs=("$task_tmp"/keila-deps.*)
    ((${#logs[@]} == 0)) || fail 'registro exitoso no eliminado'
)
(
    TMPDIR=$task_tmp
    KEILA_MISSING_PACKAGES=(mpv)
    deps_authorize_root() { return 0; }
    deps_install_packages() { printf '\033[2JERROR test\n'; return 1; }
    deps_verify() { fail 'verifica tras fallo'; }
    if deps_apply_changes apt 0 > "$task_tmp/failure" 2>&1; then fail 'oculta fallo'; fi
    text=$(< "$task_tmp/failure")
    [[ $text == *'ERROR test'* && $text == *'Registro completo:'* && $text != *$'\033'* ]] || fail 'diagnóstico de fallo'
    shopt -s nullglob
    logs=("$task_tmp"/keila-deps.*)
    ((${#logs[@]} == 1)) || fail 'registro perdido'
    [[ $(stat -c %a "${logs[0]}") == 600 ]] || fail 'registro no privado'
)
(
    KEILA_MISSING_PACKAGES=(mpv)
    deps_authorize_root() { return 1; }
    deps_install_packages() { fail 'instala sin privilegios'; }
    if deps_apply_changes apt 0 >/dev/null 2>&1; then fail 'oculta rechazo sudo'; fi
)
(
    deps_run_root() { printf '%s\n' "$*" >> "$task_tmp/managers"; }
    deps_install_packages apt mpv jq
    deps_install_packages pacman mpv
    deps_install_packages dnf jq
    text=$(< "$task_tmp/managers")
    [[ $text == *'apt-get -q update'* && $text == *'DEBIAN_FRONTEND=noninteractive'* && $text == *'--force-confold'* && $text == *'--noprogressbar'* && $text == *'dnf -q install -y jq'* ]] || fail 'flags de gestores'
)
(
    deps_termux_apt_get() { printf '%s\n' "$*" >> "$task_tmp/termux"; }
    deps_termux_repair() { fail 'actualiza Termux sano'; }
    deps_install_packages pkg mpv
    [[ $(< "$task_tmp/termux") == $'update\ninstall mpv' ]] || fail 'instalación mínima Termux'
)
(
    attempts=0
    deps_termux_apt_get() {
        [[ ${1:-} != update ]] || return 0
        ((attempts+=1))
        printf 'attempt %s\n' "$attempts" >> "$task_tmp/retry"
        ((attempts > 1))
    }
    deps_termux_repair() { printf 'repair\n' >> "$task_tmp/retry"; }
    deps_install_packages pkg mpv > "$task_tmp/retry-output" 2>&1
    [[ $(< "$task_tmp/retry") == $'attempt 1\nrepair\nattempt 2' ]] || fail 'reintento Termux'
)
printf 'ok   dependencias: consentimiento, descripciones, silencio, registros y reparación acotada\n'
