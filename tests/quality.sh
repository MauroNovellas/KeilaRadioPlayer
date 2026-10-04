#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s: %s\n' "$*" "$QUALITY_NOTICE" >&2; exit 1; }
keila_init_paths || fail rutas
origin=https://radio.invalid/original target=https://radio.invalid/alternativa other=https://otra.invalid/live
quality_load || fail 'archivo ausente'
quality_resolve_playback "$origin"
[[ $QUALITY_PLAY_URL == "$origin" && $QUALITY_PLAY_RATE == 0 ]] || fail defecto
quality_save_choice "$origin" "$target" 64000 || fail guardar
[[ $(stat -c %a "$KEILA_CONFIG_DIR/qualities") == 600 && -f $KEILA_CONFIG_DIR/qualities.bak ]] || fail privacidad
QUALITY_TARGETS=() QUALITY_RATES=(); quality_load || fail cargar
quality_resolve_playback "$origin"
[[ $QUALITY_PLAY_URL == "$target" && $QUALITY_PLAY_RATE == 64000 ]] || fail persistencia
# Fusionar la elección de otra sesión y restaurar solo esta emisora.
printf '%s|%s|0\n' "$other" "$other/low" >> "$KEILA_CONFIG_DIR/qualities"
quality_save_choice "$origin" "$origin" 0 || fail original
[[ -z ${QUALITY_TARGETS[$origin]:-} && ${QUALITY_TARGETS[$other]} == "$other/low" ]] || fail 'no fusiona o borra otras emisoras'
quality_save_choice "$origin" "$target" 96000 || fail guardar
for rate in 7999 2000001 064000 '-1' '1+1' '$(touch NO)' ''; do
    quality_save_choice "$origin" "$target" "$rate" && fail "acepta bitrate $rate"
done
for url in '' 'file:///tmp/a' 'https://' 'https://user:pass@radio.invalid/a' 'https://radio.invalid/a b' 'https://radio.invalid/a|b' $'https://radio.invalid/\n' 'https://radio.invalid/a\b'; do
    quality_save_choice "$origin" "$url" 0 && fail "acepta URL $url"
done
data_quality_url_valid 'https://[2001:db8::1]:443/audio?a=1&b=2' || fail IPv6
before=$(<"$KEILA_CONFIG_DIR/qualities")
data_publish() { return 1; }
quality_save_choice "$origin" "$other" 0 && fail 'acepta fallo de disco'
[[ ${QUALITY_TARGETS[$origin]} == "$target" && ${QUALITY_RATES[$origin]} == 96000 && $(<"$KEILA_CONFIG_DIR/qualities") == "$before" ]] || fail 'fallo altera datos'
unset -f data_publish; source "$ROOT_DIR/lib/data-safety.sh"
BACKUP_DATA_BUSY=1
quality_save_choice "$origin" "$other" 0 && fail 'guarda durante restauración'
BACKUP_DATA_BUSY=0
# Nunca cargar ni sobrescribir un documento dañado.
for contents in "$origin|$target|0|extra" "$origin|$target|064000" "$origin|$target|0"$'\n'"$origin|$other|0" '||0'; do
    printf '%s\n' "$contents" > "$KEILA_CONFIG_DIR/qualities"
    quality_load && fail 'carga documento dañado'
    quality_save_choice "$origin" "$other" 0 && fail 'sobrescribe documento dañado'
    [[ ${QUALITY_TARGETS[$origin]} == "$target" ]] || fail 'error de lectura altera memoria'
done
printf '%s\0\n' "$origin|$target|0" > "$KEILA_CONFIG_DIR/qualities"
quality_load && fail NUL
printf '%s\n' "$before" > "$KEILA_CONFIG_DIR/qualities"
mv -- "$KEILA_CONFIG_DIR/qualities" "$task_tmp/personal"
ln -s "$task_tmp/personal" "$KEILA_CONFIG_DIR/qualities"
quality_load && fail 'sigue enlace'
rm -- "$KEILA_CONFIG_DIR/qualities"; cp -- "$task_tmp/personal" "$KEILA_CONFIG_DIR/qualities"
quality_load || fail 'recarga válida'
# Recuperación conserva íntegro el dañado; las URL con metacaracteres son datos.
quality_save_choice "$origin" "$target" 128000 || fail 'crear respaldo anterior'
printf 'dañado\n' > "$KEILA_CONFIG_DIR/qualities"
data_recover "$KEILA_CONFIG_DIR/qualities" qualities >/dev/null 2>&1 || fail recuperación
quality_load
[[ ${QUALITY_RATES[$origin]} == 96000 ]] || fail 'no recupera copia anterior'
compgen -G "$KEILA_CONFIG_DIR/qualities.corrupt.*" >/dev/null || fail 'pierde documento dañado'
payload='https://radio.invalid/$(touch${IFS}'"$task_tmp/EXECUTED)"
quality_save_choice "$payload" "$target" 0 || fail 'metacaracteres como datos'
quality_load; quality_resolve_playback "$payload"
[[ $QUALITY_PLAY_URL == "$target" ]] || fail 'pierde URL con metacaracteres'
quality_save_choice "$payload" "$payload" 0 || fail 'eliminar elección con metacaracteres'
[[ ! -e $task_tmp/EXECUTED ]] || fail 'ejecuta URL personal'
# Audio/disco no son una transacción: fallo de conexión restaura ambas elecciones.
PLAYER_URL=$origin PLAYER_INPUT_URL=$target PLAYER_HLS_RATE=96000 PLAYER_PID=123 PLAYER_NAME=Radio
PLAYER_MUTED=1 PLAYER_PAUSED=1 PLAYER_VOLUME=37 RECORDING_ACTIVE=0 starts=0
player_is_running() { return 0; }
record_plan_busy() { return 1; }
player_start() {
    starts=$((starts+1))
    [[ ${PLAYER_PRESERVE_MUTE:-0} == 1 && ${PLAYER_START_PAUSED:-0} == 1 ]] || fail 'no conserva silencio/pausa'
    quality_resolve_playback "$2"
    PLAYER_INPUT_URL=$QUALITY_PLAY_URL PLAYER_HLS_RATE=$QUALITY_PLAY_RATE
    ((starts > 1))
}
quality_apply_choice "$origin" 123 "$other" 64000 && fail 'acepta conexión fallida'
[[ $starts == 2 && $PLAYER_INPUT_URL == "$target" && $PLAYER_HLS_RATE == 96000 && ${QUALITY_TARGETS[$origin]} == "$target" && $PLAYER_MUTED == 1 && $PLAYER_PAUSED == 1 && $PLAYER_VOLUME == 37 ]] || fail reversión
starts=0 RECORDING_ACTIVE=1
quality_apply_choice "$origin" 123 "$other" 0 && fail 'interrumpe grabación'
[[ $starts == 0 ]] || fail 'graba y reconecta'
RECORDING_ACTIVE=0 PENDING_PREVIEW_PID=456
quality_apply_choice "$origin" 123 "$other" 0 && fail 'interrumpe escucha de archivo'
PENDING_PREVIEW_PID=''
quality_apply_choice "$origin" 124 "$other" 0 && fail 'usa proceso obsoleto'
record_plan_busy() { return 0; }
quality_apply_choice "$origin" 123 "$other" 0 && fail 'interrumpe programación'
printf 'ok   calidades: persistencia privada, fusión, validación, fallos, reversión y protección de audio\n'
