#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
# Reloj, audio y procesos simulados; persistencia privada y hooks reales.
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache" XDG_RUNTIME_DIR="$task_tmp/runtime"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s: %s\n' "$*" "$QUALITY_NOTICE" >&2; exit 1; }
keila_init_paths || fail rutas
origin=https://radio.invalid/original old=https://radio.invalid/low target=https://radio.invalid/new other=https://otra.invalid/live
quality_save_choice "$origin" "$old" 64000 || fail 'preferencia anterior'
quality_save_choice "$other" "$other/low" 0 || fail 'otra emisora'
# Cancelar una parada intencional usa el player_stop real, sin proceso que matar.
QUALITY_CHECK_ACTIVE=1 PLAYER_PID=''
player_stop
[[ $QUALITY_CHECK_ACTIVE == 0 ]] || fail 'parar no cancela la prueba'

TEST_NOW=100 RUNNING=1 starts=0 FAIL_TARGET='' FAIL_ALL=0
quality_check_now() { QUALITY_CHECK_NOW_VALUE=$TEST_NOW; }
app_message() { UI_MESSAGE=$1; }
player_is_running() { ((RUNNING)); }
record_plan_busy() { return 1; }
player_start() {
    local name=$1 url=$2 paused=${PLAYER_START_PAUSED:-0}
    [[ ${PLAYER_PRESERVE_MUTE:-0} == 1 ]] || fail 'quita silencio al reiniciar'
    quality_check_cancel
    starts=$((starts+1))
    quality_resolve_playback "$url"
    PLAYER_NAME=$name PLAYER_URL=$url PLAYER_INPUT_URL=$QUALITY_PLAY_URL PLAYER_HLS_RATE=$QUALITY_PLAY_RATE
    PLAYER_PID=$((1000+starts)) PLAYER_PAUSED=$paused RUNNING=1
    player_reset_info
    APP_RECONNECT_WAITING=1 APP_RECONNECT_INITIAL_START=1 APP_RECONNECT_ATTEMPTS=0
    APP_RECONNECT_NEXT_AT=0 APP_RECONNECT_ELIGIBLE=0
    if ((FAIL_ALL)) || [[ $PLAYER_INPUT_URL == "$FAIL_TARGET" ]]; then PLAYER_PID='' PLAYER_PAUSED=0 RUNNING=0; return 1; fi
    return 0
}
app_reconnect_start_attempt() { fail 'reintenta la candidata antes de verificarla'; }
player_collect_exit_status() { PLAYER_PID='' PLAYER_PAUSED=0; player_reset_info; PLAYER_LAST_EXIT_STATUS=4; }
ui_draw_player_info_only() { return 0; }
spectrum_tick() { return 1; }

reset_case() {
    quality_check_cancel
    BACKUP_DATA_BUSY=0 FAIL_TARGET='' FAIL_ALL=0 TEST_NOW=100 starts=0 RUNNING=1
    quality_save_choice "$origin" "$old" 64000 || fail 'reiniciar preferencia'
    PLAYER_NAME=Radio PLAYER_URL=$origin PLAYER_INPUT_URL=$old PLAYER_HLS_RATE=64000 PLAYER_PID=123
    PLAYER_VOLUME=37 PLAYER_MUTED=1 PLAYER_PAUSED=0 RECORDING_ACTIVE=0 PENDING_PREVIEW_PID=''
    player_reset_info
    UI_MESSAGE='' APP_RECONNECT_WAITING=0 APP_RECONNECT_ELIGIBLE=1
    before=$(<"$KEILA_CONFIG_DIR/qualities")
}
begin_trial() {
    quality_apply_choice "$origin" "$PLAYER_PID" "$target" 128000 || fail iniciar
    [[ $QUALITY_CHECK_ACTIVE == 1 && $starts == 1 && $PLAYER_INPUT_URL == "$target" && $PLAYER_HLS_RATE == 128000 ]] || fail 'prueba no instalada'
    [[ $(<"$KEILA_CONFIG_DIR/qualities") == "$before" && ${QUALITY_TARGETS[$origin]} == "$old" ]] || fail 'guarda antes del audio'
}
tick() { TEST_NOW=$1; app_reconnect_tick || true; }
audio_position() {
    PLAYER_STREAM_READY=1 PLAYER_INFO_READY=1 PLAYER_STREAM_CORE_IDLE=0 PLAYER_BUFFERING=0
    PLAYER_STREAM_LAST_POSITION=$1 PLAYER_STREAM_LAST_PROGRESS_AT=$TEST_NOW
}
assert_previous() {
    [[ $QUALITY_CHECK_ACTIVE == 0 && $starts == 2 && $PLAYER_INPUT_URL == "$old" && $PLAYER_HLS_RATE == 64000 ]] || fail recuperación
    [[ $(<"$KEILA_CONFIG_DIR/qualities") == "$before" ]] || fail 'fallo altera preferencias'
}

reset_case; begin_trial
PLAYER_CODEC=aac PLAYER_BITRATE_KBPS=128
tick 101
[[ $QUALITY_CHECK_ACTIVE == 1 ]] || fail 'confirma solo códec/IPC'
audio_position 0.000; tick 102; tick 103
[[ $QUALITY_CHECK_ACTIVE == 1 && $(<"$KEILA_CONFIG_DIR/qualities") == "$before" ]] || fail 'confirma reloj congelado'
audio_position 0.125; tick 104
[[ $QUALITY_CHECK_ACTIVE == 0 && ${QUALITY_TARGETS[$origin]} == "$target" && ${QUALITY_RATES[$origin]} == 128000 ]] || fail confirmación
[[ $APP_RECONNECT_WAITING == 0 && $APP_RECONNECT_ELIGIBLE == 1 && $UI_MESSAGE == *'comprobada y guardada'* ]] || fail 'confirmación no limpia arranque'
[[ $PLAYER_VOLUME == 37 && $PLAYER_MUTED == 1 && $PLAYER_PAUSED == 0 && ${QUALITY_TARGETS[$other]} == "$other/low" ]] || fail 'confirmación cambia datos/audio'

reset_case; FAIL_TARGET=$target
quality_apply_choice "$origin" 123 "$target" 128000 && fail 'acepta fallo de IPC'
assert_previous
[[ $UI_MESSAGE == *'Recuperando la versión anterior'* ]] || fail 'no explica recuperación de IPC'

reset_case; PLAYER_PAUSED=1; begin_trial
RUNNING=0
app_poll_player || true
[[ $QUALITY_CHECK_PAUSED == 1 && $UI_MESSAGE != *'se detuvo inesperadamente'* ]] || fail 'caída pierde pausa o destella error'
tick 101; assert_previous
[[ $PLAYER_PAUSED == 1 && $PLAYER_MUTED == 1 ]] || fail 'recuperación tras caída quita pausa/silencio'

reset_case; begin_trial
audio_position 4.0; tick 101
tick 112; assert_previous
[[ $UI_MESSAGE == *'no entregó audio con progreso en 12s'* ]] || fail 'no explica reloj sin progreso'

reset_case; PLAYER_PAUSED=1; begin_trial
tick 900
[[ $QUALITY_CHECK_ACTIVE == 1 && $starts == 1 && $QUALITY_CHECK_ELAPSED == 0 ]] || fail 'vence o reanuda durante pausa'
ui_quality_info state
[[ $UI_QUALITY_INFO == *'pendiente'* && $UI_QUALITY_INFO == *'reanuda'* ]] || fail 'no explica pausa en fila existente'
recording_start Radio && fail 'graba candidata sin comprobar'
app_toggle_recording && fail 'G graba candidata'
[[ $UI_MESSAGE == *'antes de grabar'* ]] || fail 'G no explica bloqueo'
PLAYER_PAUSED=0 PLAYER_VOLUME=71 PLAYER_MUTED=0
tick 901
[[ $QUALITY_CHECK_ELAPSED == 0 ]] || fail 'no concede plazo nuevo al reanudar'
audio_position 2.0; tick 902
audio_position 2.2; tick 903
[[ $QUALITY_CHECK_ACTIVE == 0 && $PLAYER_VOLUME == 71 && $PLAYER_MUTED == 0 && $PLAYER_PAUSED == 0 ]] || fail 'no conserva ajustes hechos durante prueba'

reset_case; begin_trial
audio_position 0.25; tick 101
PLAYER_PAUSED=1; tick 102; tick 500
PLAYER_PAUSED=0; tick 501
[[ $QUALITY_CHECK_ACTIVE == 1 ]] || fail 'reanudar usa muestra anterior a la pausa'
audio_position 0.30; tick 502
[[ $QUALITY_CHECK_ACTIVE == 0 ]] || fail 'reanudar no confirma con avance fresco'

reset_case; begin_trial
audio_position 0.1; tick 101
tick 500
[[ $QUALITY_CHECK_ACTIVE == 1 && $QUALITY_CHECK_ELAPSED == 0 ]] || fail 'suspensión confirma o vence con datos viejos'
audio_position 0.2; tick 501
[[ $QUALITY_CHECK_ACTIVE == 0 ]] || fail 'no confirma tras suspensión'

reset_case; begin_trial
audio_position 0.1; tick 101
PLAYER_BUFFERING=1 PLAYER_STREAM_LAST_POSITION=0.2; tick 102
PLAYER_BUFFERING=0; tick 103
[[ $QUALITY_CHECK_ACTIVE == 1 ]] || fail 'usa progreso de buffering'
audio_position 0.3; tick 104
[[ $QUALITY_CHECK_ACTIVE == 0 ]] || fail 'audio después de buffering no confirma'

reset_case; begin_trial
audio_position 0.1; tick 101
BACKUP_DATA_BUSY=1; audio_position 0.2; tick 113
[[ $QUALITY_CHECK_ACTIVE == 1 && $starts == 1 && $(<"$KEILA_CONFIG_DIR/qualities") == "$before" ]] || fail 'corta audio o escribe durante copia'
BACKUP_DATA_BUSY=0; audio_position 0.3; tick 114
[[ $QUALITY_CHECK_ACTIVE == 0 ]] || fail 'no guarda después de copia'

(
    reset_case; begin_trial
    FAVORITE_URLS=("$origin") RECENT_URLS=("$other") UI_SELECTED_INDEX=0
    favorites_load() { :; }; labels_load() { :; }; history_load() { :; }
    state_load() { :; }; preferences_load() { :; }; equalizer_load() { :; }
    config_load() { :; }; history_recent_refresh() { :; }; preferences_apply() { :; }
    equalizer_apply() { :; }; ui_sync_selection() { :; }
    backup_reload_runtime || fail 'recargar restauración'
    [[ $QUALITY_CHECK_ACTIVE == 0 && $starts == 1 && $PLAYER_INPUT_URL == "$target" && $PLAYER_MUTED == 1 && $PLAYER_VOLUME == 37 ]] || fail 'restaurar interrumpe radio o deja comprobación'
    [[ $(<"$KEILA_CONFIG_DIR/qualities") == "$before" ]] || fail 'restaurar publica candidata'
) || fail 'prioridad de restauración'

(
    reset_case; begin_trial
    # El horario vence mientras la candidata aún no está confirmada. Reabrir
    # la emisora desde su preferencia guardada, aunque coincida la URL lógica.
    app_play() { player_start "$@"; }
    record_plan_arm Radio "$origin" "$((EPOCHSECONDS+1))" "$((EPOCHSECONDS+61))" "$EPOCHSECONDS" || fail 'reserva durante comprobación'
    RECORD_PLAN_AT=$EPOCHSECONDS
    record_plan_tick || fail 'inicio de reserva'
    [[ $QUALITY_CHECK_ACTIVE == 0 && $starts == 2 && $PLAYER_INPUT_URL == "$old" && $PLAYER_HLS_RATE == 64000 && $RECORD_PLAN_STATE == connecting ]] || fail 'reserva usa candidata provisional'
) || fail 'prioridad de reserva'

(
    reset_case; begin_trial
    data_publish() { return 1; }
    audio_position 1.0; tick 101
    audio_position 1.1; tick 102
    assert_previous
    [[ $UI_MESSAGE == *'No se pudo guardar'* ]] || fail 'oculta fallo de disco'
) || fail 'fallo al publicar'

reset_case; begin_trial
quality_save_choice "$origin" "$other" 0 || fail 'otra sesión'
before=$(<"$KEILA_CONFIG_DIR/qualities")
tick 112; assert_previous
[[ ${QUALITY_TARGETS[$origin]} == "$other" ]] || fail 'recuperar sobrescribe otra sesión'

reset_case; begin_trial
PLAYER_PID=888 PLAYER_URL=$other PLAYER_INPUT_URL=$other PLAYER_HLS_RATE=0
tick 101
[[ $QUALITY_CHECK_ACTIVE == 0 && $starts == 1 && $PLAYER_PID == 888 && $(<"$KEILA_CONFIG_DIR/qualities") == "$before" ]] || fail 'tick obsoleto cambia nueva emisora'

reset_case; FAIL_ALL=1
quality_apply_choice "$origin" 123 "$target" 128000 && fail 'acepta ambas conexiones fallidas'
[[ $QUALITY_CHECK_ACTIVE == 0 && $starts == 2 && $RUNNING == 0 && $(<"$KEILA_CONFIG_DIR/qualities") == "$before" && $UI_MESSAGE == *'Tampoco se pudo abrir la anterior'* ]] || fail 'bucle o datos tras doble fallo'

reset_case; begin_trial
pid=$PLAYER_PID
quality_apply_choice "$origin" "$pid" "$other" 0 && fail 'solapa comprobaciones'
app_quality_menu >/dev/null && fail 'abre selector durante comprobación'
[[ $starts == 1 && $QUALITY_CHECK_PID == "$pid" ]] || fail 'segunda elección interrumpe candidata'
OPTIONS_RUNNING=1
options_action_reason quality; [[ -n $OPTIONS_REASON ]] || fail 'Opciones permite otra calidad pendiente'
options_action_reason record_toggle; [[ -n $OPTIONS_REASON ]] || fail 'Opciones permite grabar candidata'
ui_quality_info state
[[ $UI_QUALITY_INFO == *'comprobando audio'* ]] || fail 'comprobación no visible en fila existente'
for position in '' '-1' '1e3' '$(touch NO)' '1+1' '999999999999999999999'; do
    quality_check_position "$position" && fail 'acepta reloj no válido'
done
quality_check_position 0001.020 || fail 'reloj con ceros'
[[ $QUALITY_POSITION_MS == 1020 ]] || fail 'normalización decimal'
printf 'ok   calidad: audio con progreso, pausa/suspensión, IPC/caída/timeout, recuperación única, disco y cancelación\n'
