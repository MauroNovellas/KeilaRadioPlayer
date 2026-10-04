#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
directory=$5
jq -n --arg url "$1" '{version:1,rows:[{url:$url,rate:0,codec:"MP3",bits:0,kind:"original"}],notice:"Catálogo disponible"}' > "$directory/catalog.tmp"
mv -- "$directory/catalog.tmp" "$directory/catalog.json"
sleep 30 &
child=$!
printf '%s\n' "$child" > "$directory/child"
trap 'wait "$child" 2>/dev/null; exit 0' TERM INT
wait "$child"
