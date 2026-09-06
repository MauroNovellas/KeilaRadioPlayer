#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

# shellcheck source=lib/player.sh
source "$ROOT_DIR/lib/player.sh"

player_is_running() { return 0; }
PLAYER_NAME='Radio Test'
PLAYER_URL='https://example.invalid/radio'
PLAYER_INFO_INTERVAL=1

refresh_with_snapshot() {
    local snapshot="$1"
    player_query_snapshot() { printf '%s\n' "$snapshot"; }
    PLAYER_INFO_LAST_REFRESH=0
    player_refresh_info || true
}

# mpv puede conocer ya códec, bitrate y parámetros de audio antes de empezar a
# entregar sonido. Eso no debe bastar para declarar la emisora reproduciendo.
player_reset_info
refresh_with_snapshot '{
  "1": {"title":"Radio Test"},
  "2": "aac",
  "3": 128000,
  "4": {"samplerate":44100,"hr-channels":"stereo"},
  "5": false,
  "10": true,
  "11": null,
  "12": null
}'
assert_eq 'aac' "$PLAYER_CODEC" 'metadata técnica disponible antes del audio'
assert_eq '0' "$PLAYER_STREAM_READY" 'metadata sola no declara stream listo'
assert_eq '0' "$PLAYER_INFO_READY" 'alias de compatibilidad sigue estado real'

# Incluso core-idle=false no basta si todavía no existe un reloj de audio/playback.
player_reset_info
refresh_with_snapshot '{
  "2": "aac",
  "4": {"samplerate":44100,"hr-channels":"stereo"},
  "5": false,
  "10": false,
  "11": null,
  "12": null
}'
assert_eq '0' "$PLAYER_STREAM_READY" 'core activo sin reloj no declara stream listo'

# Cuando el núcleo ya reproduce y aparece una posición real, el stream pasa a ready.
player_reset_info
refresh_with_snapshot '{
  "2": "aac",
  "3": 128000,
  "4": {"samplerate":44100,"hr-channels":"stereo"},
  "5": false,
  "10": false,
  "11": 0.125,
  "12": 0.100
}'
assert_eq '1' "$PLAYER_STREAM_READY" 'audio real declara stream listo'
assert_eq '1' "$PLAYER_INFO_READY" 'TUI recibe readiness real'
assert_eq '0' "$PLAYER_STREAM_CORE_IDLE" 'core-idle real almacenado'
assert_eq '0.125' "$PLAYER_STREAM_LAST_POSITION" 'posición real almacenada'
((PLAYER_STREAM_STARTED_AT > 0)) || fail 'no se registró inicio real del stream'
((PLAYER_STREAM_LAST_PROGRESS_AT > 0)) || fail 'no se registró progreso real del stream'

# Una emisora que ya reprodujo no vuelve a "Conectando" durante buffering: ready
# representa que alcanzó reproducción real y BUFFERING describe el estado transitorio.
refresh_with_snapshot '{
  "2": "aac",
  "4": {"samplerate":44100,"hr-channels":"stereo"},
  "5": true,
  "10": true,
  "11": 0.125,
  "12": 0.100
}'
assert_eq '1' "$PLAYER_STREAM_READY" 'buffering conserva readiness alcanzado'
assert_eq '1' "$PLAYER_BUFFERING" 'buffering se informa por separado'
assert_eq '0.125' "$PLAYER_STREAM_LAST_POSITION" 'posición quieta se conserva durante buffering'

# Al reanudarse, el reloj vuelve a avanzar y queda preparado para una futura
# detección de stream estancado sin activar aún ninguna reconexión automática.
refresh_with_snapshot '{
  "2": "aac",
  "4": {"samplerate":44100,"hr-channels":"stereo"},
  "5": false,
  "10": false,
  "11": 0.875,
  "12": 0.850
}'
assert_eq '1' "$PLAYER_STREAM_READY" 'reanudación conserva ready'
assert_eq '0' "$PLAYER_BUFFERING" 'buffering termina al reanudar'
assert_eq '0.875' "$PLAYER_STREAM_LAST_POSITION" 'posición avanza al reanudar'

player_reset_info
assert_eq '0' "$PLAYER_STREAM_READY" 'reset limpia readiness'
assert_eq '' "$PLAYER_STREAM_LAST_POSITION" 'reset limpia posición'
assert_eq '0' "$PLAYER_STREAM_STARTED_AT" 'reset limpia instante de inicio'

printf 'ok   player: distingue metadata, reproducción real, buffering y progreso\n'
