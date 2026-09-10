#!/usr/bin/env bash
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
player_is_running() { return 0; }
PLAYER_SOCKET=/tmp/keila-test-title.sock PLAYER_STREAM_TITLE_MAX_AGE=300
PLAYER_INFO_LAST_REFRESH=0
KEILA_PLAYER_NOW=1000
player_query_snapshot() {
    printf '%s\n' '{"1":{"icy-title":"Artista - Tema Uno"},"2":"aac","3":128000,"4":{"samplerate":48000,"channels":2},"5":false,"6":"","7":"","8":"","9":"","10":false,"11":1,"12":1}'
}
player_refresh_info || fail 'primer título'
[[ "$PLAYER_STREAM_TITLE" == 'Artista - Tema Uno' && $PLAYER_STREAM_TITLE_UPDATED_AT == 1000 ]] || fail 'título inicial'
KEILA_PLAYER_NOW=1299; PLAYER_INFO_LAST_REFRESH=0
player_refresh_info || true
[[ "$PLAYER_STREAM_TITLE" == 'Artista - Tema Uno' ]] || fail 'caducidad anticipada'
KEILA_PLAYER_NOW=1300; PLAYER_INFO_LAST_REFRESH=0
player_refresh_info || fail 'caducidad'
[[ -z "$PLAYER_STREAM_TITLE" && "$PLAYER_STREAM_TITLE_LAST_SEEN" == 'Artista - Tema Uno' ]] || fail 'título antiguo visible'
KEILA_PLAYER_NOW=1301; PLAYER_INFO_LAST_REFRESH=0
player_refresh_info || true
[[ -z "$PLAYER_STREAM_TITLE" ]] || fail 'título reaparece'
player_query_snapshot() {
    printf '%s\n' '{"1":{"icy-title":"Artista - Tema Dos"},"2":"aac","3":128000,"4":{"samplerate":48000,"channels":2},"5":false,"6":"","7":"","8":"","9":"","10":false,"11":2,"12":2}'
}
KEILA_PLAYER_NOW=1302; PLAYER_INFO_LAST_REFRESH=0
player_refresh_info || fail 'título nuevo'
[[ "$PLAYER_STREAM_TITLE" == 'Artista - Tema Dos' && $PLAYER_STREAM_TITLE_UPDATED_AT == 1302 ]] || fail 'título nuevo no reaparece'
printf 'ok   títulos: actualización, caducidad y reemplazo\n'
