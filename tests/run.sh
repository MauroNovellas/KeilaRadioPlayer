#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok() { printf 'ok   %s\n' "$1"; ((PASS += 1)); }
not_ok() { printf 'FAIL %s\n' "$1" >&2; ((FAIL += 1)); }

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    if [[ "$expected" == "$actual" ]]; then return 0; fi
    printf '  esperado: %q\n  obtenido: %q\n' "$expected" "$actual" >&2
    printf '  %s\n' "$message" >&2
    return 1
}

run_test() {
    local name="$1" fn="$2"
    if "$fn"; then ok "$name"; else not_ok "$name"; fi
}

test_bash_syntax() {
    local file
    while IFS= read -r file; do bash -n "$file" || return 1; done < <(
        {
            printf '%s\n' "$ROOT_DIR/keila-radio"
            find "$ROOT_DIR/lib" -maxdepth 1 -type f -name '*.sh' -print
            find "$ROOT_DIR/tests" -maxdepth 1 -type f -name '*.sh' -print
        } | sort -u
    )
}

test_shellcheck() {
    command -v shellcheck >/dev/null 2>&1 || { printf 'skip shellcheck no está instalado\n'; return 0; }
    shellcheck -x -e SC1090,SC1091,SC2030,SC2031,SC2034,SC2016 \
        "$ROOT_DIR/keila-radio" \
        "$ROOT_DIR/lib/config.sh" \
        "$ROOT_DIR/lib/lock.sh" \
        "$ROOT_DIR/lib/state.sh" \
        "$ROOT_DIR/lib/favorites.sh" \
        "$ROOT_DIR/lib/recording.sh" \
        "$ROOT_DIR/lib/ui.sh" \
        "$ROOT_DIR/tests/run.sh" \
        "$ROOT_DIR/tests/recording-formats.sh" \
        "$ROOT_DIR/tests/pre-rc.sh"
}

test_config_parser() (
    local tmp
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT
    export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"
    mkdir -p "$HOME"
    source "$ROOT_DIR/lib/config.sh"
    local default_recordings="$tmp/default recordings"
    config_load "$default_recordings" || return 1
    assert_eq '5' "$KEILA_VOLUME_STEP" 'volume_step por defecto' || return 1
    assert_eq '1' "$KEILA_PLAYER_INFO_INTERVAL" 'metadata_interval por defecto' || return 1
    assert_eq '86400' "$KEILA_CATALOG_MAX_AGE" 'catalog_max_age por defecto' || return 1
    assert_eq "$default_recordings" "$KEILA_RECORDINGS_DIR" 'grabaciones por defecto' || return 1
    [[ -f "$KEILA_CONFIG_FILE" ]] || return 1

    cat > "$KEILA_CONFIG_FILE" <<'EOF'
volume_step=7
metadata_interval=2
catalog_max_age=3600
recordings_dir=~/Radio Captures
unknown_key=ignored
EOF
    config_load "$default_recordings" || return 1
    assert_eq '7' "$KEILA_VOLUME_STEP" 'volume_step personalizado' || return 1
    assert_eq '2' "$KEILA_PLAYER_INFO_INTERVAL" 'metadata_interval personalizado' || return 1
    assert_eq '3600' "$KEILA_CATALOG_MAX_AGE" 'catalog_max_age personalizado' || return 1
    assert_eq "$HOME/Radio Captures" "$KEILA_RECORDINGS_DIR" 'expansión de ~/' || return 1

    cat > "$KEILA_CONFIG_FILE" <<'EOF'
volume_step=0
metadata_interval=no
catalog_max_age=-1
recordings_dir=
EOF
    config_load "$default_recordings" || return 1
    assert_eq '5' "$KEILA_VOLUME_STEP" 'valor inválido vuelve al defecto' || return 1
    assert_eq '1' "$KEILA_PLAYER_INFO_INTERVAL" 'intervalo inválido vuelve al defecto' || return 1
    assert_eq '86400' "$KEILA_CATALOG_MAX_AGE" 'caché inválida vuelve al defecto' || return 1
    assert_eq "$default_recordings" "$KEILA_RECORDINGS_DIR" 'ruta vacía conserva el defecto' || return 1
)

test_state_is_data() (
    local tmp
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT
    export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"
    mkdir -p "$HOME"
    source "$ROOT_DIR/lib/config.sh"
    source "$ROOT_DIR/lib/lock.sh"
    config_load "$tmp/recordings" || return 1
    source "$ROOT_DIR/lib/state.sh"
    local marker="$tmp/EXECUTED"
    {
        printf 'volume\t77\n'
        printf 'last_name\t%s\n' "\$(touch $marker)"
        printf 'last_url\thttps://example.invalid/radio\n'
    } > "$KEILA_STATE_FILE"
    state_load
    [[ ! -e "$marker" ]] || return 1
    assert_eq '77' "$STATE_VOLUME" 'volumen leído como dato' || return 1
    assert_eq "\$(touch $marker)" "$STATE_LAST_NAME" 'el estado no ejecuta comandos' || return 1
    assert_eq 'https://example.invalid/radio' "$STATE_LAST_URL" 'URL persistida' || return 1
    STATE_VOLUME=42 STATE_LAST_NAME='Radio Test' STATE_LAST_URL='https://example.invalid/test'
    state_save || return 1
    state_load
    assert_eq '42' "$STATE_VOLUME" 'round-trip de estado' || return 1
)

test_favorites() (
    local tmp
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT
    export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"
    mkdir -p "$HOME"
    source "$ROOT_DIR/lib/config.sh"
    source "$ROOT_DIR/lib/lock.sh"
    config_load "$tmp/recordings" || return 1
    source "$ROOT_DIR/lib/favorites.sh"
    favorites_init '' || return 1
    favorites_load
    favorites_add 'Radio|Uno' 'https://example.invalid/1' || return 1
    favorites_add 'Radio Dos' 'https://example.invalid/2' || return 1
    assert_eq 'Radio-Uno' "${FAVORITE_NAMES[0]}" 'sanitización del separador' || return 1
    assert_eq '2' "${#FAVORITE_NAMES[@]}" 'dos favoritos añadidos' || return 1
    local duplicate_status=0
    favorites_add 'Duplicada' 'https://example.invalid/1' || duplicate_status=$?
    assert_eq '2' "$duplicate_status" 'URL duplicada rechazada' || return 1
    favorites_move 0 1 || return 1
    assert_eq 'Radio Dos' "${FAVORITE_NAMES[0]}" 'reordenado persistente' || return 1
    favorites_remove_index 0 || return 1
    favorites_load
    assert_eq '1' "${#FAVORITE_NAMES[@]}" 'eliminación persistente' || return 1

    # Si la escritura falla después de mutar las arrays, la vista en memoria no
    # debe mostrar un estado que nunca llegó al disco.
    local persisted_name="${FAVORITE_NAMES[0]}"
    local persisted_url="${FAVORITE_URLS[0]}"
    favorites_save_unlocked() { return 1; }

    local failed_add_status=0
    favorites_add 'No persistida' 'https://example.invalid/fail' || failed_add_status=$?
    assert_eq '1' "$failed_add_status" 'alta informa fallo de persistencia' || return 1
    assert_eq '1' "${#FAVORITE_NAMES[@]}" 'alta fallida restaura tamaño en memoria' || return 1
    assert_eq "$persisted_name" "${FAVORITE_NAMES[0]}" 'alta fallida restaura nombre en memoria' || return 1
    assert_eq "$persisted_url" "${FAVORITE_URLS[0]}" 'alta fallida restaura URL en memoria' || return 1

    FAVORITES_TOGGLE_ACTION='stale'
    local failed_toggle_status=0
    favorites_toggle 'No persistida' 'https://example.invalid/fail' || failed_toggle_status=$?
    assert_eq '1' "$failed_toggle_status" 'toggle informa fallo de persistencia' || return 1
    assert_eq '' "${FAVORITES_TOGGLE_ACTION:-}" 'toggle fallido no deja acción obsoleta' || return 1
    assert_eq '1' "${#FAVORITE_NAMES[@]}" 'toggle fallido conserva lista persistida' || return 1
)

test_recording_helpers() (
    local tmp
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT
    source "$ROOT_DIR/lib/recording.sh"
    recording_init "$tmp/recordings" || return 1
    local safe
    safe=$(recording_sanitize_name 'Radio / Test:*?')
    assert_eq 'Radio_Test' "$safe" 'nombre de grabación seguro' || return 1
    RECORDING_LAST_SIZE=1536
    assert_eq '1.5 KiB' "$(recording_size_human)" 'tamaño legible' || return 1
    local file
    file=$(recording_next_file 'Radio Test') || return 1
    [[ "$file" == "$tmp/recordings/Radio_Test_"*.mka ]] || return 1
)

test_ui_helpers() (
    source "$ROOT_DIR/lib/ui.sh"
    assert_eq '1' "$(ui_control_line_count)" 'ayuda compacta por defecto' || return 1
    ui_toggle_help
    assert_eq '4' "$(ui_control_line_count)" 'ayuda expandida ocupa cuatro filas' || return 1
    ui_toggle_help
    assert_eq '1' "$(ui_control_line_count)" 'la ayuda vuelve a compactarse' || return 1
    ui_set_message 'mensaje temporal' 5
    assert_eq 'mensaje temporal' "$UI_MESSAGE" 'mensaje visible' || return 1
    ((UI_MESSAGE_EXPIRES > 0)) || return 1
    UI_MESSAGE_EXPIRES=1
    ui_message_tick || return 1
    assert_eq '' "$UI_MESSAGE" 'mensaje temporal caduca' || return 1
    ui_set_message 'mensaje persistente' 0
    if ui_message_tick; then return 1; fi
    assert_eq 'mensaje persistente' "$UI_MESSAGE" 'ttl 0 conserva el mensaje' || return 1
)

printf 'Keila Radio Player - checks\n\n'
run_test 'sintaxis Bash' test_bash_syntax
run_test 'ShellCheck' test_shellcheck
run_test 'configuración segura' test_config_parser
run_test 'estado tratado como datos' test_state_is_data
run_test 'favoritos' test_favorites
run_test 'helpers de grabación' test_recording_helpers
run_test 'ayuda y mensajes TUI' test_ui_helpers
printf '\n%d ok, %d fallos\n' "$PASS" "$FAIL"
((FAIL == 0))
