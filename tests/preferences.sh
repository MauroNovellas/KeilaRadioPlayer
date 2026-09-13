#!/usr/bin/env bash
# Los stubs se invocan desde el selector cargado por source.
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf -- "$task_tmp"' EXIT
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
declare -A PREF_KEYS
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
PREF_AUTOPLAY=0 PREF_COLOR=0 PREF_UNICODE=0 PREF_SPECTRUM=0
PREF_KEYS[b]=n
preferences_save || fail guardar
PREF_AUTOPLAY=1 PREF_COLOR=1 PREF_UNICODE=1 PREF_SPECTRUM=1
PREF_KEYS[b]=b
preferences_load
[[ "$PREF_AUTOPLAY:$PREF_COLOR:$PREF_UNICODE:$PREF_SPECTRUM" == 0:0:0:0 ]] || fail persistencia
preferences_translate_key N
[[ "$PREF_TRANSLATED" == b ]] || fail reasignación
preferences_translate_key b
[[ -z "$PREF_TRANSLATED" ]] || fail 'atajo antiguo activo'
preferences_translate_key 0
[[ "$PREF_TRANSLATED" == 0 ]] || fail preset
calls=0
app_search_catalog() { ((calls+=1)); }
app_handle_key N
[[ "$calls" == 1 ]] || fail 'el atajo no llega a la acción'
app_handle_key B || true
[[ "$calls" == 1 ]] || fail 'la tecla antigua sigue disparando la acción'
[[ $(stat -c %a "$KEILA_CONFIG_DIR/preferences") == 600 ]] || fail permisos
PREF_KEYS[f]=n
preferences_save; preferences_load
[[ "${PREF_KEYS[b]}:${PREF_KEYS[f]}" == b:f ]] || fail duplicados
STATE_LAST_URL=good STATE_LAST_NAME=Good PLAYER_URL=bad PLAYER_NAME=Bad PLAYER_STREAM_READY=0 PLAYER_VOLUME=37
save_player_state; state_load
[[ "$STATE_LAST_URL:$STATE_VOLUME" == good:37 ]] || fail 'fallo reemplaza última escucha'
PLAYER_STREAM_READY=1 PLAYER_URL=new PLAYER_NAME=New
save_player_state; state_load
[[ "$STATE_LAST_URL" == new ]] || fail 'no guarda escucha confirmada'
# Una sesión nueva restaura preferencias, nunca una alarma pendiente.
ALARM_AT=123 ALARM_LABEL=test
preferences_save
fresh=$(bash -c 'launcher=$1; set -- --version; source "$launcher" >/dev/null; preferences_load; printf "%s:%s" "$ALARM_AT" "$PREF_AUTOPLAY"' bash "$ROOT_DIR/keila-radio")
[[ "$fresh" == 0:0 ]] || fail 'la alarma o las preferencias no se restauran correctamente'
# Recorrido del selector: cambiar autoplay y salir, sin reproducir audio.
ui_draw() { :; }; ui_refresh_size() { UI_COLS=80 UI_LINES=24; }; tput() { :; }
events=0
input_read() { ((events+=1)); INPUT_KEY=''; if ((events == 1)); then INPUT_EVENT=ENTER; else INPUT_EVENT=ESC; fi; }
PREF_AUTOPLAY=0
app_preferences_menu settings >/dev/null
PREF_AUTOPLAY=0
preferences_load
[[ "$PREF_AUTOPLAY" == 1 && "$PREFERENCES_ACTIVE" == 0 ]] || fail selector
# Moverse hasta Buscar y asignarle F intercambia Buscar/Favoritas.
events=0
input_read() {
    ((events+=1)); INPUT_KEY=''
    case "$events" in
        [1-4]) INPUT_EVENT=DOWN ;;
        5) INPUT_EVENT=ENTER ;;
        6) INPUT_EVENT=KEY; INPUT_KEY=F ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_preferences_menu settings >/dev/null
preferences_load
[[ "${PREF_KEYS[b]}:${PREF_KEYS[f]}" == f:b ]] || fail 'intercambio desde el selector'
events=0
input_read() {
    ((events+=1)); INPUT_KEY=''
    case "$events" in
        1) INPUT_EVENT=END ;;
        2|3) INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_preferences_menu settings >/dev/null
preferences_load
[[ "${PREF_KEYS[b]}:${PREF_KEYS[f]}:$PREF_COLOR:$PREF_AUTOPLAY" == b:f:1:1 ]] || fail 'restaurar valores predeterminados'
[[ "$STATE_LAST_URL:$STATE_VOLUME" == new:37 ]] || fail 'restaurar borra última escucha'
printf 'ok   preferencias: persistencia, atajos, última escucha y selector\n'
