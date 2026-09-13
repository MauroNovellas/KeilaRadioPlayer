#!/usr/bin/env bash

set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/player.sh"

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

command -v setsid >/dev/null 2>&1 || fail 'falta setsid para aislar el grupo de mpv'

setsid -- sleep 30 &
test_pid=$!
PLAYER_PID="$test_pid"
PLAYER_PGID="$test_pid"
PLAYER_SOCKET="${TMPDIR:-/tmp}/keila-process-group-test-$test_pid.sock"

player_stop || fail 'player_stop no terminó el grupo privado'
if kill -0 "$test_pid" 2>/dev/null; then
    kill -KILL "$test_pid" 2>/dev/null || true
    wait "$test_pid" 2>/dev/null || true
    fail 'el proceso del grupo privado sigue vivo'
fi

printf 'ok   player: mpv queda aislado y su grupo se limpia al detenerlo\n'
