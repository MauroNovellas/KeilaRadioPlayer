#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/lib/recording-preview-clock.sh"
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
for entry in '0 00:00' '222 03:42' '3723 01:02:03' '- --:--' '-1 --:--' '08 --:--' '36000000 --:--'; do
    read -r value expected <<< "$entry"
    pending_clock_format "$value"
    [[ $PENDING_CLOCK_FORMATTED == "$expected" ]] || fail "formato $value"
done
[[ $(pending_clock_parse <<< '{"request_id":1,"error":"success","data":222.9}
{"request_id":2,"error":"success","data":1695.8}') == '222 1695' ]] || fail lectura
for data in null true '"123"' -1 36000000; do
    [[ $(pending_clock_parse <<< "{\"request_id\":1,\"error\":\"success\",\"data\":$data}") == '- -' ]] || fail "dato $data"
done
[[ $(pending_clock_parse <<< '{"request_id":2,"error":"success","data":0}') == '- -' ]] || fail 'duración cero'
for position in -0.157996 -0.999 0 0.999; do
    [[ $(pending_clock_parse <<< "{\"request_id\":1,\"error\":\"success\",\"data\":$position}
{\"request_id\":2,\"error\":\"success\",\"data\":25}") == '0 25' ]] || fail 'inicio de mpv antiguo'
done
[[ $(pending_clock_parse <<< '{"request_id":2,"error":"success","data":-0.1}') == '- -' ]] || fail 'duración negativa'
[[ $(pending_clock_parse <<< '{"request_id":1,"error":"failure","data":42}') == '- -' ]] || fail error
[[ $(pending_clock_parse <<< '{"request_id":3,"error":"success","data":42}') == '- -' ]] || fail identificador
PENDING_CLOCK_POSITION=222 PENDING_CLOCK_DURATION=1695
pending_clock_update_text
[[ $PENDING_CLOCK_TIME == '03:42 / 28:15' ]] || fail texto
PENDING_PREVIEW_READY=1 PENDING_PREVIEW_PAUSED=1 PENDING_CLOCK_FORCE=0
calls=0
pending_clock_start() { calls=$((calls+1)); PENDING_CLOCK_AT=$EPOCHSECONDS; }
pending_clock_poll || true
[[ $calls == 0 ]] || fail 'consulta en pausa'
PENDING_PREVIEW_PAUSED=0
pending_clock_poll || true
pending_clock_poll || true
[[ $calls == 1 ]] || fail 'más de una consulta por segundo'
pending_clock_invalidate
[[ $PENDING_CLOCK_TIME == '--:-- / 28:15' && $PENDING_CLOCK_FORCE == 1 ]] || fail invalidación
printf 'ok   contador: formato, datos ausentes, pausa, cadencia e invalidación\n'
