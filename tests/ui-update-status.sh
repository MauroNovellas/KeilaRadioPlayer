#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/update.sh"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/ui-responsive.sh"
source "$ROOT_DIR/lib/ui-safe-width.sh"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    ui_update_background_cleanup
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

wait_for_update_check() {
    local i
    for ((i = 0; i < 200; i++)); do
        if ui_update_background_poll; then
            return 0
        fi
        sleep 0.01
    done
    return 1
}

# Una versión superior debe detectarse sin bloquear el proceso principal.
KEILA_VERSION='2.0.0'
KEILA_UPDATE_TAGS=$'v2.0.0\nv2.0.1'
UI_UPDATE_CHECK_STATE='idle'
UI_UPDATE_AVAILABLE_VERSION=''
ui_update_background_start || fail 'no se pudo iniciar el check en background'
assert_eq 'checking' "$UI_UPDATE_CHECK_STATE" 'estado mientras consulta'
wait_for_update_check || fail 'el check en background no terminó'
assert_eq 'available' "$UI_UPDATE_CHECK_STATE" 'detecta actualización disponible'
assert_eq '2.0.1' "$UI_UPDATE_AVAILABLE_VERSION" 'versión disponible'
[[ -z "$UI_UPDATE_CHECK_PID" ]] || fail 'quedó PID después de terminar'
[[ -z "$UI_UPDATE_CHECK_DIR" ]] || fail 'quedó temporal después de terminar'

# El aviso se inserta en la última fila útil del panel izquierdo desktop.
UI_UNICODE=0
ui_configure_glyphs
UI_COLOR=0
UI_DESKTOP_LEFT_WIDTH=47
UI_DESKTOP_RIGHT_WIDTH=65
ui_desktop_header_rule 119 'AHORA SUENA' 'FAVORITOS (8)' >/dev/null
for ((i = 0; i < 12; i++)); do
    ui_desktop_row '' '' '' '' '' '' '' '' 0 >/dev/null
done
update_line=$(ui_desktop_row '' '' '' '' 'Radio Test' '' '' '' 1)
[[ "$update_line" == *'ACTUALIZACIÓN'* ]] || fail 'el desktop no muestra etiqueta de actualización'
[[ "$update_line" == *'2.0.1 disponible'* ]] || fail 'el desktop no muestra la versión nueva'
[[ "$update_line" == *'Radio Test'* ]] || fail 'el aviso sustituyó el contenido de favoritos'

# Si estamos al día, el estado final es silencioso y no anuncia una versión.
ui_update_background_cleanup
UI_UPDATE_CHECK_STATE='idle'
UI_UPDATE_AVAILABLE_VERSION=''
KEILA_UPDATE_TAGS=$'v2.0.0'
ui_update_background_start || fail 'no se pudo iniciar el check de versión actual'
wait_for_update_check || fail 'el check de versión actual no terminó'
assert_eq 'current' "$UI_UPDATE_CHECK_STATE" 'detecta versión actual'
assert_eq '' "$UI_UPDATE_AVAILABLE_VERSION" 'no anuncia actualización inexistente'

# Opt-out explícito: no inicia ningún proceso ni consulta.
ui_update_background_cleanup
UI_UPDATE_CHECK_STATE='idle'
KEILA_NO_UPDATE_CHECK=1
if ui_update_background_start; then
    fail 'KEILA_NO_UPDATE_CHECK no desactivó el check'
fi
assert_eq 'disabled' "$UI_UPDATE_CHECK_STATE" 'estado de check desactivado'
assert_eq '' "$UI_UPDATE_CHECK_PID" 'opt-out no deja proceso'
unset KEILA_NO_UPDATE_CHECK

ui_update_background_cleanup
printf 'ok   estado de actualización integrado en TUI\n'
