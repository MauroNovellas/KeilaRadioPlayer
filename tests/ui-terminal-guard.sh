#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

if ! command -v script >/dev/null 2>&1; then
    printf 'skip protección de eco: falta script(1)\n'
    exit 0
fi

probe_dir=$(mktemp -d) || fail 'no se pudo crear temporal'
trap 'rm -rf "$probe_dir"' EXIT
probe="$probe_dir/probe.sh"

cat > "$probe" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

# Stubs mínimos: el módulo solo necesita funciones existentes que envolver.
ui_enter() { :; }
ui_suspend() { :; }
ui_resume() { :; }
ui_leave() { :; }

source "$ROOT_DIR/lib/ui-terminal-guard.sh"

before=$(stty -g) || exit 10

ui_enter || exit 11
flags=$(stty -a | tr '\n' ' ') || exit 12
if ! grep -Eq '(^|[;[:space:]])-echo([;[:space:]]|$)' <<< "$flags"; then
    exit 13
fi

ui_suspend || exit 14
after_suspend=$(stty -g) || exit 15
[[ "$after_suspend" == "$before" ]] || exit 16

ui_resume || exit 17
flags=$(stty -a | tr '\n' ' ') || exit 18
if ! grep -Eq '(^|[;[:space:]])-echo([;[:space:]]|$)' <<< "$flags"; then
    exit 19
fi

ui_leave || exit 20
after_leave=$(stty -g) || exit 21
[[ "$after_leave" == "$before" ]] || exit 22

printf '__KEILA_TERMINAL_GUARD_OK__\n'
EOF
chmod +x "$probe"

output=$(ROOT_DIR="$ROOT_DIR" script -qec "bash '$probe'" /dev/null 2>&1) || {
    printf '%s\n' "$output" >&2
    fail 'el guard no conservó/restauró correctamente el estado del pseudo-terminal'
}

[[ "$output" == *'__KEILA_TERMINAL_GUARD_OK__'* ]] || fail 'la prueba de pseudo-terminal no terminó correctamente'

printf 'ok   TUI mantiene echo desactivado entre lecturas y lo restaura al suspender/salir\n'
