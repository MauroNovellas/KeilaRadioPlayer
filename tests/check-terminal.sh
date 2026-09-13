#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Reproduce una batería lanzada desde terminal, no solo desde stdin cerrado/CI.
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; [[ ! -f "$task_tmp/output" ]] || cat "$task_tmp/output" >&2; exit 1; }
mkdir "$task_tmp/suite" || fail temporal
printf '%s\n' \
    '[[ ! -t 0 ]] || { printf "La prueba heredó el terminal\n"; exit 8; }' \
    'if IFS= read -r -t 1 unexpected; then exit 9; fi' \
    'exit 0' > "$task_tmp/suite/stdin.sh"
# Sin -nostdin intencionadamente: el runner debe aislar incluso herramientas
# que intentan leer el terminal por defecto. Audio sintético, nunca altavoces.
printf '%s\n' 'ffmpeg -v error -f lavfi -i sine=frequency=440:duration=1 -f null -' > "$task_tmp/suite/audio.sh"
printf '%s\n' 'bash "$KEILA_TTY_TEST_ROOT/tests/ui-terminal-guard.sh"' > "$task_tmp/suite/guard.sh"
printf '%s\n' 'fast|stdin.sh|' 'fast|audio.sh|' 'fast|guard.sh|' > "$task_tmp/suite/suites.txt"
printf '%s\n' \
    '[[ -t 0 ]] || { printf "El runner no recibió un terminal real\n"; exit 10; }' \
    'source "$KEILA_TTY_TEST_ROOT/tests/check.sh"' \
    'CHECK_DIR="$KEILA_TTY_TEST_SUITE"' \
    'KEILA_TEST_TIMEOUT=4' \
    'check_main fast' > "$task_tmp/runner.sh"
KEILA_TTY_TEST_ROOT="$ROOT_DIR" KEILA_TTY_TEST_SUITE="$task_tmp/suite" \
KEILA_TTY_TEST_RUNNER="$task_tmp/runner.sh" \
    timeout --kill-after=1s 15s script -qec 'bash "$KEILA_TTY_TEST_RUNNER"' /dev/null \
    </dev/null > "$task_tmp/output" 2>&1 || fail 'la batería se bloquea o falla desde un TTY'
grep -q '3 correctas; 0 fallidas' "$task_tmp/output" || fail 'faltan comprobaciones'
printf 'ok   runner desde TTY: stdin aislado, ffmpeg sin bloqueo y guard con terminal propio\n'
