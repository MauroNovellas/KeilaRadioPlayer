#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
source "$1/lib/deps.sh"
test_mode=$2 test_marker=$3
deps_detect_manager() { [[ $test_mode == termux-* ]] && printf pkg || printf apt; }
deps_collect_missing() {
    KEILA_MISSING_COMMANDS=(mpv jq tput)
    KEILA_MISSING_PACKAGES=(mpv jq ncurses-bin)
    if [[ $test_mode == termux-* ]]; then KEILA_MISSING_PACKAGES=(mpv jq ncurses-utils); fi
    if [[ $test_mode == termux-repair ]]; then KEILA_MISSING_COMMANDS=(); KEILA_MISSING_PACKAGES=(); fi
}
deps_termux_needs_repair() { [[ $test_mode == termux-repair ]]; }
deps_authorize_root() { printf 'AUTH\n'; }
deps_termux_repair() { printf 'repair\n' >> "$test_marker"; printf 'NOISY REPAIR\n'; }
deps_install_packages() {
    ((${#KEILA_MISSING_PACKAGES[@]})) || return 0
    printf 'install %s\n' "$*" >> "$test_marker"
    printf 'NOISY INSTALL\n'
    [[ $test_mode != failure ]]
}
deps_verify() { return 0; }
deps_ensure
