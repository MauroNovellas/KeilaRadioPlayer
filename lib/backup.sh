#!/usr/bin/env bash
# Exportación/restauración conservadora de datos personales.

BACKUP_RESTORE_NOTICE=''
# shellcheck source=lib/backup-archive.sh
source "$(dirname "${BASH_SOURCE[0]}")/backup-archive.sh"

backup_timestamp() {
    date '+%Y%m%d-%H%M%S'
}

backup_default_file() {
    printf '%s/keila-backup-%s.tar.gz' "$PWD" "$(backup_timestamp)"
}

backup_resolve_output() {
    local output="${1:-}"
    if [[ -z "$output" ]]; then
        backup_default_file
    elif [[ "$output" == /* ]]; then
        printf '%s' "$output"
    else
        printf '%s/%s' "$PWD" "$output"
    fi
}

backup_copy_if_regular() {
    local source="$1" target="$2"
    [[ -e "$source" || -L "$source" ]] || return 0
    [[ -f "$source" && ! -L "$source" ]] || return 1
    mkdir -p "$(dirname "$target")" || return 1
    cp -- "$source" "$target" || return 1
    chmod 600 "$target" 2>/dev/null || true
}

backup_create() {
    local output
    output=$(backup_resolve_output "${1:-}") || return 1
    [[ "$output" == *.tar.gz ]] || output="${output}.tar.gz"

    [[ ! -e "$output" && ! -L "$output" ]] || { printf 'La copia ya existe; no se sobrescribe: %s\n' "$output" >&2; return 1; }
    local staging status=0
    staging=$(mktemp -d "${TMPDIR:-/tmp}/keila-backup.XXXXXX") || return 1
    if backup_lock_all; then
        backup_snapshot "$staging/keila-backup" || status=1
        backup_unlock_all
    else status=1; fi
    if ((status == 0)); then backup_publish_archive "$staging/keila-backup" "$output" || status=1; fi
    if ((status == 0)); then
        printf 'Copia de seguridad creada: %s\n' "$output"
    fi
    rm -rf -- "$staging"
    return "$status"
}

backup_validate_equalizer() {
    data_validate "$1" equalizer
}

backup_validate_config() {
    data_validate "$1" config
}

backup_validate_history() {
    data_validate "$1" history
}

backup_validate_staging() {
    local root="$1"
    [[ -d "$root" && ! -L "$root" && -f "$root/manifest" && ! -L "$root/manifest" ]] || return 1
    grep -qx 'format=keila-backup-v1' "$root/manifest" || return 1
    local i count=0
    for i in config state; do [[ ! -L "$root/$i" ]] || return 1; done
    for i in "${!BACKUP_MEMBERS[@]}"; do
        [[ -e "$root/${BACKUP_MEMBERS[i]}" || -L "$root/${BACKUP_MEMBERS[i]}" ]] || continue
        data_validate "$root/${BACKUP_MEMBERS[i]}" "${BACKUP_KINDS[i]}" || return 1
        ((count+=1))
    done
    ((count > 0))
}

backup_install_locked() {
    local source="$1" destination="$2" kind="$3" tmp status=0
    [[ -e "$source" || -L "$source" ]] || return 0
    [[ -f "$source" && ! -L "$source" ]] || return 1
    mkdir -p "$(dirname "$destination")" || return 1
    tmp=$(mktemp "$destination.tmp.XXXXXX") || return 1
    cp -- "$source" "$tmp" && chmod 600 "$tmp" || status=1
    if ((status == 0)); then data_publish "$tmp" "$destination" "$kind" || status=1; fi
    rm -f -- "$tmp"
    return "$status"
}

backup_install_file() {
    local status=0
    lock_acquire "$2.lock" || return 1
    backup_install_locked "$@" || status=1
    lock_release "$2.lock" || status=1
    return "$status"
}

backup_restore_prepared() {
    local root=$1 work=$2 status=0 i pre_restore
    backup_validate_staging "$root" || return 1
    backup_lock_all || return 1
    pre_restore=$(backup_next_file "$KEILA_CONFIG_DIR" "pre-restore-$(backup_timestamp)") || status=1
    if ((status == 0)); then backup_snapshot "$work/keila-backup" || status=1; fi
    if ((status == 0)); then backup_publish_archive "$work/keila-backup" "$pre_restore" || status=1; fi
    if ((status)); then
        backup_unlock_all
        printf 'No se pudo crear la copia previa; no se restaura nada.\n' >&2
        return 1
    fi
    if ! printf '%s\n' "$pre_restore" > "$work/pre-restore"; then backup_unlock_all; return 1; fi
    for i in "${!BACKUP_MEMBERS[@]}"; do
        backup_install_locked "$root/${BACKUP_MEMBERS[i]}" "${BACKUP_PATHS[i]}" "${BACKUP_KINDS[i]}" || { status=1; break; }
    done
    backup_unlock_all
    if ((status == 0)); then printf 'Copia restaurada.\n'
    else printf 'Restauración incompleta; conserva la copia previa para recuperarte.\n' >&2; fi
    printf 'Respaldo previo: %s\n' "$pre_restore"
    return "$status"
}

backup_restore() {
    local archive=$1 work status=0
    work=$(mktemp -d "${TMPDIR:-/tmp}/keila-restore.XXXXXX") || return 1
    if backup_prepare "$archive" "$work"; then
        backup_restore_prepared "$work/tree/keila-backup" "$work" || status=1
    else
        printf 'La copia no supera la validación; no se restaura nada.\n' >&2
        status=1
    fi
    rm -rf -- "$work"
    return "$status"
}
