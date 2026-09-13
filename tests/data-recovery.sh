#!/usr/bin/env bash
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
favorites_init || fail inicio
favorites_add Original https://original.invalid || fail favoritos
labels_set https://original.invalid Original || fail comentarios
STATE_VOLUME=37 STATE_LAST_NAME=Original STATE_LAST_URL=https://original.invalid
state_save || fail estado
preferences_save || fail preferencias
history_record Original https://original.invalid || fail recientes
EQUALIZER_GAINS=(1 2 3 4 5)
equalizer_save || fail ecualizador
config_load "$task_tmp/recordings" || fail configuración
# Segundo guardado deja la primera versión como respaldo.
favorites_add Nuevo https://nuevo.invalid || fail favoritos
labels_set https://original.invalid Nuevo || fail comentarios
STATE_VOLUME=88
state_save || fail estado
PREF_COLOR=0
preferences_save || fail preferencias
history_record Nuevo https://nuevo.invalid || fail recientes
EQUALIZER_GAINS=(5 4 3 2 1)
equalizer_save || fail ecualizador
files=("$KEILA_FAVORITES_FILE" "$KEILA_CONFIG_DIR/labels" "$KEILA_STATE_FILE" "$KEILA_CONFIG_DIR/preferences" "$KEILA_STATE_DIR/history" "$KEILA_EQUALIZER_FILE" "$KEILA_CONFIG_FILE")
kinds=(favorites labels state preferences history equalizer config)
shopt -s nullglob
for i in "${!files[@]}"; do
    file=${files[i]} kind=${kinds[i]}
    cp "$file.bak" "$task_tmp/expected.$i" || fail copia
    printf 'archivo dañado sin estructura\n' > "$file"
    cp "$file" "$task_tmp/corrupt.$i"
    data_recover "$file" "$kind" 2>/dev/null || fail "recuperación $kind"
    cmp "$file" "$task_tmp/expected.$i" || fail restauración
    archives=("$file".corrupt.*)
    ((${#archives[@]} == 1)) || fail archivo
    cmp "${archives[0]}" "$task_tmp/corrupt.$i" || fail 'no conserva original dañado'
    [[ $(stat -c %a "$file.bak") == 600 && $(stat -c %a "${archives[0]}") == 600 ]] || fail permisos
    data_recover "$file" "$kind" || fail 'repetir recuperación'
    # Sin ninguna copia válida, no modificar ninguno de los dos archivos.
    printf 'dañado\n' > "$file"
    printf 'copia dañada\n' > "$file.bak"
    if data_recover "$file" "$kind" 2>/dev/null; then fail 'acepta copia dañada'; fi
    [[ $(<"$file") == dañado && $(<"$file.bak") == 'copia dañada' ]] || fail 'pérdida sin copia'
    # Tampoco publicar una normalización de un original dañado durante la sesión.
    cp "$task_tmp/expected.$i" "$task_tmp/candidate"
    if data_publish "$task_tmp/candidate" "$file" "$kind"; then fail 'sustituye corrupción en sesión'; fi
    cp "$task_tmp/expected.$i" "$file.bak"
    # Si falla la restauración, el original dañado permanece.
    mv() { return 1; }
    if data_recover "$file" "$kind" 2>/dev/null; then fail 'ignora fallo de restauración'; fi
    unset -f mv
    [[ $(<"$file") == dañado ]] || fail 'restauración fallida destruye original'
    lock_release "$file.lock" || fail bloqueo
    rm -- "$file"
    data_recover "$file" "$kind" 2>/dev/null || fail 'recuperación de archivo ausente'
    cmp "$file" "$task_tmp/expected.$i" || fail 'ausente incorrecto'
done
favorites_load; labels_load; state_load; preferences_load
history_load; equalizer_load; config_load "$task_tmp/recordings"
[[ ${#FAVORITE_URLS[@]} == 1 && ${FAVORITE_LABELS[https://original.invalid]} == Original && $STATE_VOLUME == 37 && $PREF_COLOR == 1 ]] || fail lectura
[[ ${#HISTORY_URLS[@]} == 1 && ${HISTORY_URLS[0]} == https://original.invalid && ${EQUALIZER_GAINS[*]} == '1 2 3 4 5' && $KEILA_VOLUME_STEP == 5 ]] || fail 'lectura de nuevos formatos'
[[ -n ${DATA_RECOVERY_NOTICE:-} ]] || fail aviso
printf 'ok   recuperación: respaldo, corrupción conservada, copia inválida, fallos y ausencia\n'
