#!/usr/bin/env bash
# Exportación/restauración conservadora de datos personales.

BACKUP_RESTORE_NOTICE=''

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
    [[ -f "$source" && ! -L "$source" ]] || return 0
    mkdir -p "$(dirname "$target")" || return 1
    cp -- "$source" "$target" || return 1
    chmod 600 "$target" 2>/dev/null || true
}

backup_create() {
    local output
    output=$(backup_resolve_output "${1:-}") || return 1
    [[ "$output" == *.tar.gz ]] || output="${output}.tar.gz"

    app_init_data || return 1

    local output_dir staging root archive_name status=0
    output_dir=$(dirname "$output")
    mkdir -p "$output_dir" || return 1
    staging=$(mktemp -d "${TMPDIR:-/tmp}/keila-backup.XXXXXX") || return 1
    root="$staging/keila-backup"
    archive_name=$(basename "$output")
    mkdir -p "$root/config" "$root/state" || { rm -rf "$staging"; return 1; }

    {
        printf 'format=keila-backup-v1\n'
        printf 'version=%s\n' "${KEILA_VERSION:-desconocida}"
        printf 'created_at=%s\n' "$(date -Iseconds)"
    } > "$root/manifest" || status=1

    backup_copy_if_regular "$KEILA_CONFIG_FILE" "$root/config/config" || status=1
    backup_copy_if_regular "$KEILA_FAVORITES_FILE" "$root/config/favorites" || status=1
    backup_copy_if_regular "$KEILA_CONFIG_DIR/labels" "$root/config/labels" || status=1
    backup_copy_if_regular "$KEILA_CONFIG_DIR/preferences" "$root/config/preferences" || status=1
    backup_copy_if_regular "$KEILA_CONFIG_DIR/equalizer" "$root/config/equalizer" || status=1
    backup_copy_if_regular "$KEILA_STATE_FILE" "$root/state/state" || status=1
    backup_copy_if_regular "$KEILA_STATE_DIR/history" "$root/state/history" || status=1

    if ((status == 0)); then
        tar -C "$staging" -czf "$output" keila-backup || status=1
    fi
    if ((status == 0)); then
        chmod 600 "$output" 2>/dev/null || true
        printf 'Copia de seguridad creada: %s\n' "$output"
    else
        rm -f -- "$output"
    fi
    rm -rf "$staging"
    return "$status"
}

backup_tar_list_safe() {
    local archive="$1" entry
    tar -tzf "$archive" | while IFS= read -r entry; do
        case "$entry" in
            keila-backup|keila-backup/|keila-backup/config|keila-backup/config/|keila-backup/state|keila-backup/state/) ;;
            keila-backup/manifest|\
            keila-backup/config/config|\
            keila-backup/config/favorites|\
            keila-backup/config/labels|\
            keila-backup/config/preferences|\
            keila-backup/config/equalizer|\
            keila-backup/state/state|\
            keila-backup/state/history) ;;
            */../*|../*|/*|*'//'*) return 1 ;;
            *) return 1 ;;
        esac
    done
}

backup_validate_equalizer() {
    local file="$1" raw gains i
    [[ -f "$file" && ! -L "$file" ]] || return 1
    IFS= read -r raw < "$file" || raw=''
    IFS=',' read -r -a gains <<< "$raw"
    ((${#gains[@]} == 5)) || return 1
    for ((i=0; i<5; i++)); do equalizer_gain_valid "${gains[i]}" || return 1; done
}

backup_validate_config() {
    local file="$1" raw
    [[ -f "$file" && ! -L "$file" ]] || return 1
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        [[ "$raw" != *[[:cntrl:]]* ]] || return 1
    done < "$file"
}

backup_validate_history() {
    data_validate "$1" favorites
}

backup_validate_staging() {
    local root="$1"
    [[ -f "$root/manifest" ]] || return 1
    grep -qx 'format=keila-backup-v1' "$root/manifest" || return 1

    [[ ! -e "$root/config/config" ]] || backup_validate_config "$root/config/config" || return 1
    [[ ! -e "$root/config/favorites" ]] || data_validate "$root/config/favorites" favorites || return 1
    [[ ! -e "$root/config/labels" ]] || data_validate "$root/config/labels" labels || return 1
    [[ ! -e "$root/config/preferences" ]] || data_validate "$root/config/preferences" preferences || return 1
    [[ ! -e "$root/config/equalizer" ]] || backup_validate_equalizer "$root/config/equalizer" || return 1
    [[ ! -e "$root/state/state" ]] || data_validate "$root/state/state" state || return 1
    [[ ! -e "$root/state/history" ]] || backup_validate_history "$root/state/history" || return 1
}

backup_install_file() {
    local source="$1" destination="$2"
    [[ -f "$source" && ! -L "$source" ]] || return 0
    mkdir -p "$(dirname "$destination")" || return 1
    cp -- "$source" "$destination" || return 1
    chmod 600 "$destination" 2>/dev/null || true
}

backup_restore() {
    local archive="$1"
    [[ -n "$archive" && -f "$archive" && ! -L "$archive" ]] || {
        printf 'Archivo de copia no válido: %s\n' "${archive:-vacío}" >&2
        return 1
    }

    app_init_data || return 1
    backup_tar_list_safe "$archive" || {
        printf 'La copia contiene rutas no válidas o inesperadas.\n' >&2
        return 1
    }

    local staging root pre_restore status=0
    staging=$(mktemp -d "${TMPDIR:-/tmp}/keila-restore.XXXXXX") || return 1
    tar -C "$staging" -xzf "$archive" || { rm -rf "$staging"; return 1; }
    root="$staging/keila-backup"
    backup_validate_staging "$root" || {
        rm -rf "$staging"
        printf 'La copia no supera la validación; no se restaura nada.\n' >&2
        return 1
    }

    pre_restore="$KEILA_CONFIG_DIR/pre-restore-$(backup_timestamp).tar.gz"
    backup_create "$pre_restore" >/dev/null || {
        rm -rf "$staging"
        printf 'No se pudo crear la copia previa; no se restaura nada.\n' >&2
        return 1
    }

    backup_install_file "$root/config/config" "$KEILA_CONFIG_FILE" || status=1
    backup_install_file "$root/config/favorites" "$KEILA_FAVORITES_FILE" || status=1
    backup_install_file "$root/config/labels" "$KEILA_CONFIG_DIR/labels" || status=1
    backup_install_file "$root/config/preferences" "$KEILA_CONFIG_DIR/preferences" || status=1
    backup_install_file "$root/config/equalizer" "$KEILA_CONFIG_DIR/equalizer" || status=1
    backup_install_file "$root/state/state" "$KEILA_STATE_FILE" || status=1
    backup_install_file "$root/state/history" "$KEILA_STATE_DIR/history" || status=1

    if ((status == 0)); then
        favorites_load || true
        labels_load || true
        history_load || true
        history_recent_refresh || true
        state_load || true
        preferences_load || true
        equalizer_load || true
        printf 'Copia restaurada: %s\n' "$archive"
        printf 'Respaldo previo: %s\n' "$pre_restore"
    fi
    rm -rf "$staging"
    return "$status"
}
