#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

export HOME="$task_tmp/home" XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
mkdir -p "$HOME"

BASE_DIR="$ROOT_DIR"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/i18n.sh"
source "$ROOT_DIR/lib/stations.sh"

config_load "$task_tmp/recordings" || fail config
i18n_load "$KEILA_LANGUAGE"
assert_eq es "$KEILA_LANGUAGE" 'idioma por defecto'
assert_eq 'AHORA SUENA' "$(tr_ui ui.now_playing)" 'traducción base española'
assert_eq 'fallback' "$(tr_ui missing.key fallback)" 'fallback explícito'

cat > "$KEILA_CONFIG_FILE" <<'EOF'
language=en
EOF
config_load "$task_tmp/recordings" || fail config_en
i18n_load "$KEILA_LANGUAGE"
assert_eq en "$KEILA_LANGUAGE" 'idioma desde config'
assert_eq 'NOW PLAYING' "$(tr_ui ui.now_playing)" 'traducción inglesa'
assert_eq 'COMMENTS' "$(tr_ui ui.comments)" 'traducción inglesa comentarios'
assert_eq 'yes' "$(tr_ui catalog.yes)" 'traducción inglesa sí/no'

KEILA_LANG=es config_load "$task_tmp/recordings" || fail config_env
i18n_load "$KEILA_LANGUAGE"
assert_eq es "$KEILA_LANGUAGE" 'KEILA_LANG tiene prioridad'
assert_eq 'AHORA SUENA' "$(tr_ui ui.now_playing)" 'override español'
assert_eq '4h 08m' "$(stations_human_duration 14880)" 'duración con minutos a dos dígitos'

printf 'ok   i18n: español base, inglés, fallback y override por entorno\n'
