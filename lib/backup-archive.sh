#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Solo datos pequeños. No extraer archivos sin validar tipos, rutas y tamaños.
BACKUP_MEMBERS=(config/config config/favorites config/labels config/preferences config/equalizer state/state state/history)
BACKUP_KINDS=(config favorites labels preferences equalizer state history)
BACKUP_LABELS=(Configuración Favoritas Comentarios Preferencias Ecualizador 'Volumen y última emisora' Recientes)
BACKUP_MAX_ARCHIVE=8388608
BACKUP_MAX_MEMBER=4194304
BACKUP_MAX_TOTAL=16777216
BACKUP_LOCKED=()

backup_data_paths() {
    BACKUP_PATHS=("$KEILA_CONFIG_FILE" "$KEILA_FAVORITES_FILE" "$KEILA_CONFIG_DIR/labels"
        "$KEILA_CONFIG_DIR/preferences" "$KEILA_EQUALIZER_FILE" "$KEILA_STATE_FILE" "$KEILA_STATE_DIR/history")
}

backup_unlock_all() {
    local file
    for file in "${BACKUP_LOCKED[@]}"; do lock_release "$file.lock" || true; done
    BACKUP_LOCKED=()
}

backup_lock_all() {
    local file
    BACKUP_LOCKED=()
    backup_data_paths
    for file in "${BACKUP_PATHS[@]}"; do
        if ! lock_acquire "$file.lock"; then backup_unlock_all; return 1; fi
        BACKUP_LOCKED+=("$file")
    done
}

# El llamante mantiene todos los locks. No inicializar la aplicación ni tocar
# estado de audio, cargar preferencias o crear carpetas de grabación al copiar.
backup_snapshot() {
    local root=$1 i source count=0 size total=0
    mkdir -p -- "$root/config" "$root/state" || return 1
    for i in "${!BACKUP_MEMBERS[@]}"; do
        source=${BACKUP_PATHS[i]}
        [[ -e "$source" || -L "$source" ]] || continue
        size=$(stat -c %s -- "$source") || return 1
        [[ "$size" =~ ^[0-9]+$ ]] && ((size <= BACKUP_MAX_MEMBER)) || return 1
        total=$((total+size))
        ((total <= BACKUP_MAX_TOTAL)) || return 1
        data_validate "$source" "${BACKUP_KINDS[i]}" || return 1
        cp -- "$source" "$root/${BACKUP_MEMBERS[i]}" || return 1
        chmod 600 "$root/${BACKUP_MEMBERS[i]}" || return 1
        ((count+=1))
    done
    ((count > 0)) || { printf 'Todavía no hay datos personales para copiar.\n' >&2; return 1; }
    printf 'format=keila-backup-v1\nversion=%s\ncreated_at=%s\n' "${KEILA_VERSION:-desconocida}" "$(date -Iseconds)" > "$root/manifest"
}

backup_publish_archive() {
    local root=$1 output=$2 tmp status=0
    [[ ! -e "$output" && ! -L "$output" ]] || { printf 'La copia ya existe; no se sobrescribe: %s\n' "$output" >&2; return 1; }
    mkdir -p -- "${output%/*}" || return 1
    tmp=$(mktemp "${output}.tmp.XXXXXX") || return 1
    timeout --kill-after=2s 30s tar -C "${root%/*}" -czf "$tmp" keila-backup || status=1
    if ((status == 0)); then
        local size
        size=$(stat -c %s -- "$tmp") || status=1
        [[ "$size" =~ ^[0-9]+$ ]] && ((size > 0 && size <= BACKUP_MAX_ARCHIVE)) || status=1
    fi
    if ((status == 0)); then
        # Link exclusivo: también protege una colisión aparecida durante tar.
        chmod 600 "$tmp" && ln -T -- "$tmp" "$output" || status=1
    fi
    rm -f -- "$tmp"
    return "$status"
}

backup_next_file() {
    local directory=$1 prefix=$2 suffix='' i
    mkdir -p -- "$directory" || return 1
    [[ ! -L "$directory" ]] || return 1
    for ((i=0; i<1000; i++)); do
        ((i == 0)) || suffix="-$i"
        if [[ ! -e "$directory/$prefix$suffix.tar.gz" && ! -L "$directory/$prefix$suffix.tar.gz" ]]; then
            printf '%s/%s%s.tar.gz' "$directory" "$prefix" "$suffix"; return 0
        fi
    done
    return 1
}

backup_signature() {
    [[ -f "$1" && ! -L "$1" ]] || return 1
    stat -c '%d:%i:%s:%y:%z' -- "$1"
}

backup_tar_list_safe() {
    local archive=$1 listing line mode owner size rest entry type total=0 count=0
    local -A seen=()
    # GNU tar (también en Termux). Escapar nombres evita interpretar saltos de
    # línea incrustados como miembros distintos. Nada se extrae en esta fase.
    listing=$(LC_ALL=C timeout --kill-after=2s 20s tar --quoting-style=escape -tvzf "$archive" --numeric-owner --full-time | head -c 32769) || return 1
    ((${#listing} <= 32768)) || return 1
    while IFS= read -r line; do
        read -r mode owner size rest <<< "$line"
        type=${mode:0:1}
        [[ "$type" == - || "$type" == d ]] || return 1
        [[ "$size" =~ ^[0-9]{1,9}$ ]] && ((size <= BACKUP_MAX_MEMBER)) || return 1
        total=$((total+size)); ((total <= BACKUP_MAX_TOTAL)) || return 1
    done <<< "$listing"
    listing=$(LC_ALL=C timeout --kill-after=2s 20s tar --quoting-style=escape -tzf "$archive" | head -c 32769) || return 1
    ((${#listing} <= 32768)) || return 1
    while IFS= read -r entry; do
        [[ -n "$entry" && -z "${seen[$entry]:-}" ]] || return 1
        seen[$entry]=1
        case "$entry" in
            keila-backup/|keila-backup/config/|keila-backup/state/|keila-backup/manifest) ;;
            keila-backup/config/config|keila-backup/config/favorites|keila-backup/config/labels|keila-backup/config/preferences|keila-backup/config/equalizer|keila-backup/state/state|keila-backup/state/history) ((count+=1)) ;;
            *) return 1 ;;
        esac
    done <<< "$listing"
    ((count > 0)) && [[ -n "${seen[keila-backup/manifest]:-}" ]]
}

backup_prepare() {
    local archive=$1 work=$2 before after size
    before=$(backup_signature "$archive") || return 1
    size=$(stat -c %s -- "$archive") || return 1
    ((size > 0 && size <= BACKUP_MAX_ARCHIVE)) || { printf 'Tamaño de copia no admitido (máximo 8 MiB).\n' >&2; return 1; }
    # Copia privada acotada: la confirmación se refiere a estos bytes, aunque el
    # original se mueva o cambie después. No ejecutar ni extraer fuera de work.
    head -c "$((BACKUP_MAX_ARCHIVE+1))" -- "$archive" > "$work/input.tar.gz" || return 1
    after=$(backup_signature "$archive") || return 1
    [[ "$before" == "$after" ]] && [[ $(stat -c %s -- "$work/input.tar.gz") == "$size" ]] || return 1
    backup_tar_list_safe "$work/input.tar.gz" || { printf 'Copia rechazada: formato, rutas, tipos o tamaños no válidos.\n' >&2; return 1; }
    mkdir -p -- "$work/tree" || return 1
    timeout --kill-after=2s 20s tar --no-same-owner --no-same-permissions -C "$work/tree" -xzf "$work/input.tar.gz" || return 1
    backup_validate_staging "$work/tree/keila-backup" || return 1
}
