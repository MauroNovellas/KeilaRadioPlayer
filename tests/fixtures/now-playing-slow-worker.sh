#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
directory=$2
sleep 60 &
child=$!
trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit' TERM INT
printf '%s\n' "$child" > "$directory/child"
wait "$child"
