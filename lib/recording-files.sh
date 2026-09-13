#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Cambios de nombre y papelera en el mismo filesystem; nunca copiar audio grande.
RECORDING_FILES_RESULT='' RECORDING_FILES_NOTICE='' RECORDING_FILES_SELECT=''
declare -A PENDING_DOUBTFUL

recording_name_valid() {
    local name=$1 LC_ALL=C
    [[ -n "$name" && "$name" != .* && "$name" != *[/\\]* && "$name" != *[[:cntrl:]]* && "$name" == *[![:space:]]* && ${#name} -le 246 ]]
}

recording_trash_file_valid() {
    local file=$1 bucket=${1%/*} root="$RECORDINGS_DIR/.trash"
    [[ -d "$RECORDINGS_DIR" && ! -L "$RECORDINGS_DIR" && -d "$root" && ! -L "$root" && -d "$bucket" && ! -L "$bucket" ]] || return 1
    [[ "${bucket%/*}" == "$root" && "${bucket##*/}" == recording.* && "${file##*/}" != .* ]] || return 1
    pending_signature "$file" >/dev/null
}

recording_files_available() {
    local file=$1
    pending_signature "$file" >/dev/null && ! pending_busy "$file" || return 1
    [[ "$file" != "${PENDING_TARGET:-}" || -z "${PENDING_PROBE_PID:-}" ]] || return 1
    [[ "$file" != "${PENDING_PREVIEW_FILE:-}" || -z "${PENDING_PREVIEW_PID:-}" ]]
}

recording_files_lock() {
    [[ -d "$RECORDINGS_DIR" && ! -L "$RECORDINGS_DIR" ]] || return 1
    local file="$RECORDINGS_DIR/.keila-files.lock" KEILA_LOCK_ATTEMPTS=2 KEILA_LOCK_SLEEP=0.01
    [[ ! -L "$file" && ( ! -e "$file/pid" || ( -f "$file/pid" && ! -L "$file/pid" ) ) ]] || return 1
    lock_acquire "$file"
}

recording_files_unlock() { lock_release "$RECORDINGS_DIR/.keila-files.lock"; }

recording_marker_signature() {
    [[ -f "$1" && ! -L "$1" ]] || return 1
    stat -c '%d:%i:%s:%y:%z' -- "$1"
}

recording_marker_remove_owned() {
    local actual
    actual=$(recording_marker_signature "$1") || return 1
    [[ "$actual" == "$2" ]] || return 1
    rm -- "$1"
}

# El llamante valida rutas y mantiene el lock. Reservar un marcador de destino
# antes de mover evita presentar como finalizado un audio de cierre pendiente.
# El marcador original no se elimina hasta que el audio esté en su destino.
recording_files_move() {
    local source=$1 target=$2 expected=$3 original_marker='' reserved='' identity actual size doubtful=0 move_status=0
    RECORDING_FILES_RESULT=''
    RECORDING_FILES_NOTICE='No se ha movido: archivo ocupado, cambiado o destino existente.'
    [[ ! -e "$target" && ! -L "$target" && ! -e "$target.pending" && ! -L "$target.pending" ]] || return 1
    recording_files_available "$source" || return 1
    [[ $(pending_signature "$source") == "$expected" ]] || return 1
    [[ "${PENDING_DOUBTFUL[$source]:-}" != "$expected" ]] || doubtful=1
    # Rechazar montajes distintos: no bloquear la TUI copiando gigabytes.
    [[ $(stat -c %d -- "$source") == "$(stat -c %d -- "${target%/*}")" ]] || {
        RECORDING_FILES_NOTICE='Origen y destino deben estar en el mismo sistema de archivos.'; return 1;
    }
    identity=$(stat -c '%d:%i' -- "$source") || return 1
    if [[ -e "$source.pending" ]]; then
        original_marker=$(recording_marker_signature "$source.pending") || return 1
        size=$(stat -c %s -- "$source.pending") || return 1
        ((size <= 128)) || { RECORDING_FILES_NOTICE='Marcador inesperado; se conserva todo para revisión manual.'; return 1; }
    fi
    if ! (
        umask 077
        set -o noclobber
        if [[ -n "$original_marker" ]]; then head -c 128 -- "$source.pending" > "$target.pending"
        else printf 'closed\n' > "$target.pending"; fi
    ) 2>/dev/null; then
        RECORDING_FILES_NOTICE='No se pudo reservar el destino; se conserva el original.'; return 1
    fi
    reserved=$(recording_marker_signature "$target.pending") || return 1
    if [[ $(pending_signature "$source") != "$expected" ]] || ! recording_files_available "$source"; then
        recording_marker_remove_owned "$target.pending" "$reserved" || true
        return 1
    fi
    # -nT no sustituye un archivo/directorio/enlace que aparezca entre tanto.
    # GNU mv puede devolver éxito al omitirlo: comprobar también el resultado.
    mv -nT -- "$source" "$target" || move_status=$?
    actual=$(stat -c '%d:%i' -- "$target" 2>/dev/null) || actual=''
    if [[ -e "$source" || -L "$source" || "$actual" != "$identity" ]]; then
        if [[ -f "$source" ]]; then recording_marker_remove_owned "$target.pending" "$reserved" || true; fi
        RECORDING_FILES_NOTICE='No se confirmó el traslado; revisa origen y destino. No se sobrescribe ninguno.'
        return 1
    fi
    RECORDING_FILES_RESULT=$target RECORDING_FILES_SELECT=$target
    if [[ -n "$original_marker" ]]; then
        if ! recording_marker_remove_owned "$source.pending" "$original_marker"; then
            RECORDING_FILES_NOTICE="Audio trasladado a $target; queda un marcador original para revisar: $source.pending"
            return 1
        fi
    elif ! recording_marker_remove_owned "$target.pending" "$reserved"; then
        RECORDING_FILES_NOTICE="Audio trasladado a $target; conserva cierre pendiente para comprobar con C."
        return 1
    fi
    RECORDING_FILES_NOTICE="Guardado: $target"
    if ((doubtful)); then
        PENDING_DOUBTFUL[$target]=$(pending_signature "$target")
        unset 'PENDING_DOUBTFUL[$source]'
    fi
    if ((move_status)); then RECORDING_FILES_NOTICE="Audio trasladado a $target, pero mv informó de un error. Revisa el destino."; return 1; fi
    return 0
}

recording_rename() {
    local file=$1 stem=$2 expected=$3 name=${1##*/} target status=0
    RECORDING_FILES_RESULT=''
    RECORDING_FILES_NOTICE='Nombre no válido. Escribe un nombre sin rutas, no vacío ni oculto.'
    [[ "${file%/*}" == "$RECORDINGS_DIR" && "$name" == *.* && -n "$stem" && "$stem" == *[![:space:]]* ]] || return 1
    recording_name_valid "$stem.${name##*.}" || return 1
    target="$RECORDINGS_DIR/$stem.${name##*.}"
    [[ "$target" != "$file" ]] || { RECORDING_FILES_NOTICE='El nombre no ha cambiado.'; return 1; }
    recording_files_lock || { RECORDING_FILES_NOTICE='Otra operación usa la carpeta; espera y reintenta.'; return 1; }
    recording_files_move "$file" "$target" "$expected" || status=1
    recording_files_unlock || status=1
    return "$status"
}

pending_trash() {
    local file=$1 expected=$2 bucket status=0 root="$RECORDINGS_DIR/.trash"
    RECORDING_FILES_RESULT=''
    RECORDING_FILES_NOTICE='No se pudo mover a la papelera; se conserva el original.'
    [[ "${file%/*}" == "$RECORDINGS_DIR" ]] || return 1
    recording_files_available "$file" && [[ $(pending_signature "$file") == "$expected" ]] || return 1
    recording_files_lock || { PENDING_NOTICE='Otra operación usa la carpeta; reintenta.'; return 1; }
    if [[ -L "$root" ]] || ! mkdir -p -- "$root" || ! chmod 700 "$root"; then status=1
    elif ! bucket=$(mktemp -d "$root/recording.XXXXXX"); then status=1
    else
        recording_files_move "$file" "$bucket/${file##*/}" "$expected" || status=1
        if [[ -z "$RECORDING_FILES_RESULT" ]]; then rmdir -- "$bucket" 2>/dev/null || true; fi
    fi
    recording_files_unlock || status=1
    PENDING_NOTICE=${RECORDING_FILES_NOTICE:-No se pudo mover a la papelera.}
    if ((status == 0)); then PENDING_NOTICE='Movida a la papelera. T abre la recuperación.'; fi
    [[ -z "$RECORDING_FILES_RESULT" ]] || pending_scan_start || true
    return "$status"
}

recording_restore_destination() {
    local file=$1 name=${1##*/} stem extension candidate i
    recording_trash_file_valid "$file" || return 1
    stem=${name%.*} extension=${name##*.}
    for ((i=0; i<1000; i++)); do
        candidate=$name
        if ((i)); then
            candidate="$stem (recuperada $i).$extension"
            while ! recording_name_valid "$candidate" && [[ -n "$stem" ]]; do
                stem=${stem%?}; candidate="$stem (recuperada $i).$extension"
            done
        fi
        recording_name_valid "$candidate" || return 1
        if [[ ! -e "$RECORDINGS_DIR/$candidate" && ! -L "$RECORDINGS_DIR/$candidate" && ! -e "$RECORDINGS_DIR/$candidate.pending" && ! -L "$RECORDINGS_DIR/$candidate.pending" ]]; then
            RECORDING_RESTORE_TARGET="$RECORDINGS_DIR/$candidate"; return 0
        fi
    done
    return 1
}

recording_restore() {
    local file=$1 target=$2 expected=$3 status=0
    RECORDING_FILES_RESULT=''
    RECORDING_FILES_NOTICE='No se pudo recuperar. Actualiza y revisa el archivo y el destino.'
    recording_trash_file_valid "$file" || return 1
    [[ "${target%/*}" == "$RECORDINGS_DIR" && "${target##*.}" == "${file##*.}" ]] || return 1
    recording_name_valid "${target##*/}" || return 1
    recording_files_lock || { RECORDING_FILES_NOTICE='Otra operación usa la carpeta; espera y reintenta.'; return 1; }
    recording_files_move "$file" "$target" "$expected" || status=1
    # Solo retirar un contenedor vacío: nunca borrar recursivamente una papelera.
    if [[ -n "$RECORDING_FILES_RESULT" ]]; then rmdir -- "${file%/*}" 2>/dev/null || true; fi
    recording_files_unlock || status=1
    return "$status"
}
