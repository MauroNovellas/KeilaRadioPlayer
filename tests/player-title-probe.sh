#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/ffprobe" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"format":{"tags":{"title":"Artista - Tema Dos"}},"streams":[]}'
SH
chmod +x "$TEST_TMP/bin/ffprobe"

cat > "$TEST_TMP/bin/timeout" <<'SH'
#!/usr/bin/env bash
shift
"$@"
SH
chmod +x "$TEST_TMP/bin/timeout"

PATH="$TEST_TMP/bin:$PATH"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

# shellcheck source=lib/player.sh
source "$ROOT_DIR/lib/player.sh"

player_is_running() { return 0; }
PLAYER_NAME='Rock FM'
PLAYER_URL='https://rockfm-cope.flumotion.com/playlist.m3u8'
PLAYER_INFO_INTERVAL=1
PLAYER_STREAM_TITLE_PROBE_INTERVAL=10
KEILA_PLAYER_NOW=1000
PLAYER_INFO_LAST_REFRESH=0

player_query_snapshot() {
    printf '%s\n' '{"1":{"icy-title":"Artista - Tema Uno"},"2":"aac","3":128000,"4":{"samplerate":48000,"channels":2},"5":false,"6":"","7":"","8":"","9":"","10":false,"11":1,"12":1}'
}

player_refresh_info || fail 'primer snapshot'
[[ "$PLAYER_STREAM_TITLE" == 'Artista - Tema Uno' ]] || fail 'título inicial'
[[ "${PLAYER_STREAM_TITLE_PROBE_PID:-}" =~ ^[0-9]+$ ]] || fail 'no arrancó probe'

wait "$PLAYER_STREAM_TITLE_PROBE_PID" 2>/dev/null || true
KEILA_PLAYER_NOW=1001
PLAYER_INFO_LAST_REFRESH=0
player_refresh_info || fail 'probe no provocó cambio'

[[ "$PLAYER_STREAM_TITLE" == 'Artista - Tema Dos' ]] || fail 'no se prefirió título externo'
[[ "$PLAYER_STREAM_TITLE_LAST_SEEN" == 'Artista - Tema Dos' ]] || fail 'no se actualizó frescura'

printf 'ok   títulos: probe HLS externo actualiza canción congelada\n'
