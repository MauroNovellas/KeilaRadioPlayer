#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/recording.sh"

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    fi

    printf 'FAIL %s\n  esperado: %q\n  obtenido: %q\n' "$message" "$expected" "$actual" >&2
    return 1
}

assert_eq 'ts' "$(recording_extension_for_stream 'hls' 'aac' 'https://example.invalid/live.m3u8')" 'HLS usa MPEG-TS' || exit 1
assert_eq 'mp3' "$(recording_extension_for_stream 'mp3' 'mp3' 'https://example.invalid/radio')" 'MP3 conserva MP3' || exit 1
assert_eq 'aac' "$(recording_extension_for_stream 'aac' 'aac' 'https://example.invalid/radio')" 'AAC conserva AAC' || exit 1
assert_eq 'ts' "$(recording_extension_for_stream '' 'aac' 'https://example.invalid/live.m3u8?token=abc')" 'URL m3u8 detecta HLS' || exit 1
assert_eq 'ogg' "$(recording_extension_for_stream '' 'opus' 'https://example.invalid/stream')" 'Opus usa Ogg' || exit 1

printf 'ok   formatos de grabación\n'
