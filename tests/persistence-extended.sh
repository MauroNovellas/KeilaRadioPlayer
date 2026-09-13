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
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
keila_init_paths || fail rutas

# Migrar sin normalizar ni truncar el archivo antiguo (ni siquiera su último LF).
printf 'Radio vieja|https://vieja.invalid' > "$KEILA_STATE_DIR/history"
printf '1,2,3,4,5' > "$KEILA_EQUALIZER_FILE"
for kind in history equalizer; do
    if [[ "$kind" == history ]]; then file="$KEILA_STATE_DIR/history"; else file=$KEILA_EQUALIZER_FILE; fi
    cp "$file" "$task_tmp/$kind.original"
    data_recover "$file" "$kind" || fail "migrar $kind"
    cmp "$file" "$task_tmp/$kind.original" || fail 'migración reescribe original'
    cmp "$file" "$file.bak" || fail 'migración sin respaldo'
    [[ $(stat -c %a "$file.bak") == 600 ]] || fail 'permisos de migración'
done
history_load || fail 'recientes sin LF'
equalizer_load || fail 'ecualizador sin LF'
[[ ${#HISTORY_URLS[@]} == 1 && ${EQUALIZER_GAINS[*]} == '1 2 3 4 5' ]] || fail migración

# Configuración manual: contenido literal, CRLF, tabs, espacios y claves futuras.
{
    printf '# Comentario personal\r\n\tvolume_step = 7\r\nmetadata_interval=no\r\n'
    printf 'catalog_country_filter=es\nfuture_option=conservar\n'
    printf 'recordings_dir=%s/recordings\n' "$task_tmp"
    printf 'literal=$(touch %s/EXECUTED)\n' "$task_tmp"
} > "$KEILA_CONFIG_FILE"
cp "$KEILA_CONFIG_FILE" "$task_tmp/config.expected"
config_load "$task_tmp/fallback" || fail 'carga manual'
[[ $KEILA_VOLUME_STEP == 7 && $KEILA_PLAYER_INFO_INTERVAL == 1 && ! -e "$task_tmp/EXECUTED" ]] || fail 'compatibilidad del parser'
cmp "$KEILA_CONFIG_FILE" "$task_tmp/config.expected" || fail 'reescribe comentarios'
cmp "$KEILA_CONFIG_FILE.bak" "$task_tmp/config.expected" || fail 'falta última configuración cargada'
printf 'roto\n' > "$KEILA_CONFIG_FILE"
config_load "$task_tmp/fallback" 2>/dev/null || fail 'config no recupera'
cmp "$KEILA_CONFIG_FILE" "$task_tmp/config.expected" || fail 'config recuperada incorrecta'

# Error al respaldar una edición manual: no reemplazar original ni la copia.
printf '\nvolume_step=9\n' >> "$KEILA_CONFIG_FILE"
cp "$KEILA_CONFIG_FILE" "$task_tmp/config.edited"
blocked_target="$KEILA_CONFIG_FILE.bak"
mv() { [[ "${*: -1}" != "$blocked_target" ]] || return 1; command mv "$@"; }
if config_load "$task_tmp/fallback"; then fail 'config oculta fallo de copia'; fi
[[ $KEILA_VOLUME_STEP == 7 ]] || fail 'config fallida aplica valores nuevos'
cmp "$KEILA_CONFIG_FILE" "$task_tmp/config.edited" || fail 'pierde edición manual'
cmp "$KEILA_CONFIG_FILE.bak" "$task_tmp/config.expected" || fail 'pierde copia manual'
unset -f mv
config_load "$task_tmp/fallback" || fail 'reintento de config'

# Un cierre forzado durante el respaldo de una edición manual conserva ambos
# archivos; el siguiente arranque recupera el lock y acepta la edición intacta.
printf '\nvolume_step=11\n' >> "$KEILA_CONFIG_FILE"
cp "$KEILA_CONFIG_FILE" "$task_tmp/config.before-kill"
cp "$KEILA_CONFIG_FILE.bak" "$task_tmp/config.bak-before-kill"
(
    trap - EXIT
    mv() {
        if [[ "${*: -1}" == "$KEILA_CONFIG_FILE.bak" ]]; then kill -KILL "$BASHPID"; fi
        command mv "$@"
    }
    config_load "$task_tmp/fallback"
) >/dev/null 2>&1 &
writer=$!
status=0
wait "$writer" 2>/dev/null || status=$?
((status == 137)) || fail 'no interrumpe respaldo de configuración'
cmp "$KEILA_CONFIG_FILE" "$task_tmp/config.before-kill" || fail 'cierre pierde edición manual'
cmp "$KEILA_CONFIG_FILE.bak" "$task_tmp/config.bak-before-kill" || fail 'cierre pierde copia manual'
config_load "$task_tmp/fallback" || fail 'config no recupera lock tras cierre'

# El ecualizador restaura también el audio si falla el rename FINAL, no solo la
# preparación del respaldo. Cubrir bandas, centrado, reset y presets.
equalizer_apply() { applied_gains="${EQUALIZER_GAINS[*]}"; return "${apply_status:-0}"; }
blocked_target=$KEILA_EQUALIZER_FILE
for operation in gain center reset preset; do
    EQUALIZER_GAINS=(1 2 3 4 5)
    equalizer_save || fail 'preparar ecualizador'
    cp "$KEILA_EQUALIZER_FILE" "$task_tmp/eq.expected"
    EQUALIZER_SELECTED=0 applied_gains='1 2 3 4 5'
    mv() { [[ "${*: -1}" != "$blocked_target" ]] || return 1; command mv "$@"; }
    status=0
    case "$operation" in
        gain) equalizer_set_gain 0 8 || status=$? ;;
        center) equalizer_center_selected || status=$? ;;
        reset) equalizer_reset || status=$? ;;
        preset) equalizer_apply_preset 2 || status=$? ;;
    esac
    unset -f mv
    ((status != 0)) || fail "acepta guardado fallido: $operation"
    [[ ${EQUALIZER_GAINS[*]} == '1 2 3 4 5' && $applied_gains == '1 2 3 4 5' ]] || fail "no revierte: $operation"
    [[ $EQUALIZER_LAST_ERROR == *'No se pudo guardar'* ]] || fail 'falta aviso de guardado'
    cmp "$KEILA_EQUALIZER_FILE" "$task_tmp/eq.expected" || fail 'daña ecualizador guardado'
done
apply_status=1
if equalizer_set_gain 0 8; then fail 'acepta rechazo del audio'; fi
[[ $EQUALIZER_LAST_ERROR == *'No se pudo confirmar'* ]] || fail 'oculta fallo de restauración de audio'
apply_status=0

# La preferencia visual no se modifica ni inicia captura si no puede guardarse.
PREF_SPECTRUM=0 SPECTRUM_ENABLED=0
preferences_save() { return 1; }
spectrum_toggle() { fail 'aplicó espectrograma antes de guardar'; }
if app_toggle_spectrum; then fail 'espectrograma oculta fallo de guardado'; fi
[[ $PREF_SPECTRUM == 0 && $SPECTRUM_ENABLED == 0 && $UI_MESSAGE == *'valor anterior'* ]] || fail 'rollback visual'
unset -f preferences_save spectrum_toggle
source "$ROOT_DIR/lib/preferences.sh"
source "$ROOT_DIR/lib/spectrum.sh"
# El estado persistido en memoria no se confunde con el volumen actual del audio.
STATE_VOLUME=37 STATE_LAST_NAME=Antes STATE_LAST_URL=https://antes.invalid
PLAYER_VOLUME=80 PLAYER_NAME=Ahora PLAYER_URL=https://ahora.invalid PLAYER_STREAM_READY=1
state_save() { return 1; }
if save_player_state; then fail 'estado oculta fallo'; fi
[[ $STATE_VOLUME == 37 && $STATE_LAST_NAME == Antes && $PLAYER_VOLUME == 80 ]] || fail 'confunde estado guardado y audio'
unset -f state_save
source "$ROOT_DIR/lib/state.sh"

# Validación completa: ninguna fila extra, NUL o expresión aritmética se acepta.
for malformed in '0,0,0,0,0,' '08,0,0,0,0' '99,0,0,0,0' '1+1,0,0,0,0' $'0,0,0,0,0\nextra'; do
    printf '%s\n' "$malformed" > "$task_tmp/malformed"
    if data_validate "$task_tmp/malformed" equalizer; then fail 'acepta ecualizador malformado'; fi
    if backup_validate_equalizer "$task_tmp/malformed"; then fail 'restore usa otra validación'; fi
done
printf '0,0,0,0,0\0\n' > "$task_tmp/malformed"
if data_validate "$task_tmp/malformed" equalizer; then fail 'acepta NUL'; fi

# Corrupción durante la sesión: recientes no se normaliza con una escritura.
history_recent_refresh
printf 'roto\n' > "$KEILA_STATE_DIR/history"
if history_record Nueva https://nueva.invalid; then fail 'reescribe historial corrupto'; fi
[[ ${HISTORY_URLS[0]} == https://vieja.invalid && ${RECENT_URLS[0]} == https://vieja.invalid ]] || fail 'pierde lista en memoria'
[[ $(<"$KEILA_STATE_DIR/history") == roto ]] || fail 'pierde original corrupto'
data_recover "$KEILA_STATE_DIR/history" history 2>/dev/null || fail 'recuperar recientes'

# Interrupción DESPUÉS de publicar .bak, justo antes de publicar los datos.
for kind in history equalizer; do
    if [[ "$kind" == history ]]; then file="$KEILA_STATE_DIR/history"; else file=$KEILA_EQUALIZER_FILE; fi
    cp "$file" "$task_tmp/before-kill"
    (
        trap - EXIT
        mv() {
            if [[ "${*: -1}" == "$file" ]]; then kill -KILL "$BASHPID"; fi
            command mv "$@"
        }
        if [[ "$kind" == history ]]; then history_record Nueva https://nueva.invalid
        else EQUALIZER_GAINS=(6 6 6 6 6); equalizer_save; fi
    ) >/dev/null 2>&1 &
    writer=$!
    status=0
    wait "$writer" 2>/dev/null || status=$?
    ((status == 137)) || fail "no interrumpe publicación de $kind"
    cmp "$file" "$task_tmp/before-kill" || fail 'cierre pierde datos'
    cmp "$file.bak" "$task_tmp/before-kill" || fail 'cierre pierde respaldo'
    data_recover "$file" "$kind" || fail "lock huérfano de $kind"
done

# Restauración de un archivo con el mismo protocolo: un fallo de publicación
# deja la versión anterior disponible, sin truncarla ni anunciar éxito.
cp "$KEILA_EQUALIZER_FILE" "$task_tmp/restore.previous"
blocked_target=$KEILA_EQUALIZER_FILE
printf '6,6,6,6,6\n' > "$task_tmp/restore.candidate"
mv() { [[ "${*: -1}" != "$blocked_target" ]] || return 1; command mv "$@"; }
if backup_install_file "$task_tmp/restore.candidate" "$KEILA_EQUALIZER_FILE" equalizer; then fail 'restore oculta fallo'; fi
unset -f mv
cmp "$KEILA_EQUALIZER_FILE" "$task_tmp/restore.previous" || fail 'restore trunca original'

# No seguir enlaces ni publicar temporales dentro de un directorio como destino.
printf '0,0,0,0,0\n' > "$task_tmp/candidate"
mkdir "$task_tmp/destination"
if data_copy_atomic "$task_tmp/candidate" "$task_tmp/destination"; then fail 'acepta directorio destino'; fi
ln -s "$task_tmp/absent" "$task_tmp/linked.bak"
if data_recover "$task_tmp/linked" history 2>/dev/null; then fail 'ignora respaldo enlazado roto'; fi

# Escritores cooperantes: ninguna fila de recientes se pierde y el ecualizador
# publica siempre un perfil entero (último escritor), también en su respaldo.
(
    KEILA_STATE_DIR="$task_tmp/concurrent-state"
    KEILA_EQUALIZER_FILE="$task_tmp/concurrent-equalizer"
    mkdir -p "$KEILA_STATE_DIR"
    pids=()
    for ((i=1; i<=12; i++)); do
        (history_record "Radio $i" "https://radio.invalid/$i") &
        pids+=("$!")
    done
    for writer in "${pids[@]}"; do wait "$writer" || fail 'escritor de recientes'; done
    history_load || fail 'recientes concurrentes inválidos'
    [[ ${#HISTORY_URLS[@]} == 12 ]] || fail 'pérdida de recientes concurrentes'
    pids=()
    for ((i=1; i<=8; i++)); do
        (EQUALIZER_GAINS=("$i" "$i" "$i" "$i" "$i"); equalizer_save) &
        pids+=("$!")
    done
    for writer in "${pids[@]}"; do wait "$writer" || fail 'escritor de ecualizador'; done
    data_validate "$KEILA_EQUALIZER_FILE" equalizer || fail 'perfil concurrente inválido'
    data_validate "$KEILA_EQUALIZER_FILE.bak" equalizer || fail 'respaldo concurrente inválido'
    equalizer_load || fail 'carga de perfil concurrente'
    for gain in "${EQUALIZER_GAINS[@]}"; do [[ "$gain" == "${EQUALIZER_GAINS[0]}" ]] || fail 'mezcla perfiles'; done
) || fail concurrencia

# Inicialización completa recupera los tres formatos antes de leerlos.
for file in "$KEILA_CONFIG_FILE" "$KEILA_EQUALIZER_FILE" "$KEILA_STATE_DIR/history"; do
    printf 'roto\n' > "$file"
done
app_init_data 2>/dev/null || fail 'arranque completo con recuperación'
[[ ${HISTORY_URLS[0]} == https://vieja.invalid && ${EQUALIZER_GAINS[*]} == '1 2 3 4 5' && $KEILA_VOLUME_STEP == 11 ]] || fail 'arranque no carga datos recuperados'
[[ -n ${DATA_RECOVERY_NOTICE:-} ]] || fail 'arranque sin aviso'
printf 'ok   persistencia extendida: migración, configuración literal, rollback, formatos y arranque\n'
