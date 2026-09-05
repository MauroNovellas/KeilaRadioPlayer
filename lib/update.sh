#!/usr/bin/env bash

KEILA_UPDATE_TAGS_URL="${KEILA_UPDATE_TAGS_URL:-https://api.github.com/repos/MauroNovellas/KeilaRadioPlayer/tags?per_page=100}"
KEILA_UPDATE_ARCHIVE_BASE_URL="${KEILA_UPDATE_ARCHIVE_BASE_URL:-https://github.com/MauroNovellas/KeilaRadioPlayer/archive/refs/tags}"
KEILA_UPDATE_GIT_URL="${KEILA_UPDATE_GIT_URL:-https://github.com/MauroNovellas/KeilaRadioPlayer.git}"

update_parse_version() {
    local version="${1#v}"

    UPDATE_MAJOR=''
    UPDATE_MINOR=''
    UPDATE_PATCH=''
    UPDATE_STAGE='stable'
    UPDATE_STAGE_NUM=0

    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-([[:alpha:]]+)([0-9]+)?)?$ ]]; then
        UPDATE_MAJOR=$((10#${BASH_REMATCH[1]}))
        UPDATE_MINOR=$((10#${BASH_REMATCH[2]}))
        UPDATE_PATCH=$((10#${BASH_REMATCH[3]}))
        if [[ -n "${BASH_REMATCH[5]:-}" ]]; then
            UPDATE_STAGE="${BASH_REMATCH[5],,}"
            if [[ -n "${BASH_REMATCH[6]:-}" ]]; then
                UPDATE_STAGE_NUM=$((10#${BASH_REMATCH[6]}))
            fi
        fi
        return 0
    fi

    return 1
}

update_stage_rank() {
    case "$1" in
        alpha) printf '1\n' ;;
        beta) printf '2\n' ;;
        rc) printf '3\n' ;;
        stable) printf '4\n' ;;
        *) printf '0\n' ;;
    esac
}

# Imprime -1 si A < B, 0 si A == B y 1 si A > B.
update_compare_versions() {
    local a="${1#v}" b="${2#v}"
    local a_major a_minor a_patch a_stage a_stage_num
    local b_major b_minor b_patch b_stage b_stage_num
    local a_rank b_rank

    update_parse_version "$a" || return 2
    a_major=$UPDATE_MAJOR; a_minor=$UPDATE_MINOR; a_patch=$UPDATE_PATCH
    a_stage=$UPDATE_STAGE; a_stage_num=$UPDATE_STAGE_NUM

    update_parse_version "$b" || return 2
    b_major=$UPDATE_MAJOR; b_minor=$UPDATE_MINOR; b_patch=$UPDATE_PATCH
    b_stage=$UPDATE_STAGE; b_stage_num=$UPDATE_STAGE_NUM

    if ((a_major != b_major)); then ((a_major > b_major)) && printf '1\n' || printf '%s\n' '-1'; return 0; fi
    if ((a_minor != b_minor)); then ((a_minor > b_minor)) && printf '1\n' || printf '%s\n' '-1'; return 0; fi
    if ((a_patch != b_patch)); then ((a_patch > b_patch)) && printf '1\n' || printf '%s\n' '-1'; return 0; fi

    a_rank=$(update_stage_rank "$a_stage")
    b_rank=$(update_stage_rank "$b_stage")
    if ((a_rank != b_rank)); then ((a_rank > b_rank)) && printf '1\n' || printf '%s\n' '-1'; return 0; fi

    if ((a_rank == 0)) && [[ "$a_stage" != "$b_stage" ]]; then
        if [[ "$a_stage" > "$b_stage" ]]; then printf '1\n'; else printf '%s\n' '-1'; fi
        return 0
    fi

    if ((a_stage_num != b_stage_num)); then
        ((a_stage_num > b_stage_num)) && printf '1\n' || printf '%s\n' '-1'
        return 0
    fi

    printf '0\n'
}

update_fetch_tags() {
    if [[ -n "${KEILA_UPDATE_TAGS:-}" ]]; then
        printf '%s\n' "$KEILA_UPDATE_TAGS"
        return 0
    fi

    command -v curl >/dev/null 2>&1 || {
        printf 'Falta curl para consultar actualizaciones.\n' >&2
        return 1
    }
    command -v jq >/dev/null 2>&1 || {
        printf 'Falta jq para consultar actualizaciones.\n' >&2
        return 1
    }

    curl -fsSL --connect-timeout 5 --max-time 12 \
        -H 'Accept: application/vnd.github+json' \
        "$KEILA_UPDATE_TAGS_URL" |
        jq -r '.[].name'
}

update_select_latest() {
    local current="${1#v}"
    local latest='' tag candidate cmp
    local allow_prerelease=0

    [[ "$current" == *-* ]] && allow_prerelease=1

    while IFS= read -r tag; do
        [[ -n "$tag" ]] || continue
        candidate="${tag#v}"
        update_parse_version "$candidate" || continue

        if ((!allow_prerelease)) && [[ "$candidate" == *-* ]]; then
            continue
        fi

        if [[ -z "$latest" ]]; then
            latest="$candidate"
            continue
        fi

        cmp=$(update_compare_versions "$candidate" "$latest") || continue
        if [[ "$cmp" == '1' ]]; then
            latest="$candidate"
        fi
    done

    [[ -n "$latest" ]] || return 1
    printf '%s\n' "$latest"
}

update_latest_version() {
    local current="${1#v}"
    local tags latest

    update_parse_version "$current" || {
        printf 'La versión local no tiene un formato comparable: %s\n' "$current" >&2
        return 1
    }

    if ! tags=$(update_fetch_tags); then
        printf 'No se pudo consultar GitHub para buscar actualizaciones.\n' >&2
        return 1
    fi

    if ! latest=$(printf '%s\n' "$tags" | update_select_latest "$current"); then
        printf 'No se encontraron versiones publicadas compatibles.\n' >&2
        return 1
    fi

    printf '%s\n' "$latest"
}

update_check() {
    local current="${KEILA_VERSION:-dev}"
    local latest cmp

    latest=$(update_latest_version "$current") || return 1
    cmp=$(update_compare_versions "$latest" "$current") || return 1

    printf 'Keila Radio Player %s\n' "$current"
    if [[ "$cmp" == '1' ]]; then
        printf 'Nueva versión disponible: %s\n' "$latest"
        printf 'Ejecuta ./keila-radio --update para instalarla.\n'
    elif [[ "$cmp" == '0' ]]; then
        printf 'Estás usando la versión más reciente disponible.\n'
    else
        printf 'Tu versión local es más reciente que la última publicada (%s).\n' "$latest"
    fi
}

update_archive_is_safe() {
    local archive="$1"
    local listing entry

    listing=$(tar -tzf "$archive") || return 1
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        if [[ "$entry" == /* || "$entry" == ../* || "$entry" == *'/../'* ]]; then
            return 1
        fi
    done <<< "$listing"
}

update_tree_version() {
    local tree="$1"
    sed -n 's/^KEILA_VERSION="\([^"]*\)"$/\1/p' "$tree/lib/version.sh" | head -n 1
}

update_validate_tree() {
    local tree="$1" expected_version="$2"
    local file version

    for file in \
        keila-radio \
        lib/version.sh \
        lib/update.sh \
        lib/player.sh \
        lib/ui.sh \
        defaults/favorites; do
        [[ -f "$tree/$file" ]] || {
            printf 'La actualización no contiene %s.\n' "$file" >&2
            return 1
        }
    done

    version=$(update_tree_version "$tree")
    [[ "$version" == "$expected_version" ]] || {
        printf 'La actualización declara la versión %s, esperaba %s.\n' "${version:-desconocida}" "$expected_version" >&2
        return 1
    }

    bash -n "$tree/keila-radio" || return 1
    while IFS= read -r -d '' file; do
        bash -n "$file" || return 1
    done < <(find "$tree/lib" -maxdepth 1 -type f -name '*.sh' -print0)
}

update_download_archive() {
    local version="$1" destination="$2"

    if [[ -n "${KEILA_UPDATE_ARCHIVE_FILE:-}" ]]; then
        cp -- "$KEILA_UPDATE_ARCHIVE_FILE" "$destination"
        return $?
    fi

    command -v curl >/dev/null 2>&1 || {
        printf 'Falta curl para descargar la actualización.\n' >&2
        return 1
    }

    curl -fL --connect-timeout 8 --max-time 60 \
        "$KEILA_UPDATE_ARCHIVE_BASE_URL/v${version}.tar.gz" \
        -o "$destination"
}

update_postcheck() {
    local install_dir="$1" expected_version="$2"
    local output

    bash -n "$install_dir/keila-radio" || return 1
    output=$(bash "$install_dir/keila-radio" --version 2>/dev/null) || return 1
    [[ "$output" == "Keila Radio Player $expected_version" ]]
}

update_rollback_files() {
    local install_dir="$1" backup_dir="$2"
    shift 2
    local component

    for component in "$@"; do
        rm -rf -- "${install_dir:?}/$component"
        if [[ -e "$backup_dir/$component" || -L "$backup_dir/$component" ]]; then
            mv -- "$backup_dir/$component" "$install_dir/$component" || return 1
        fi
    done
}

update_install_archive() {
    local install_dir="$1" version="$2"
    local workdir archive extract_dir release_root backup_dir component
    local -a managed_components=(keila-radio lib defaults README.md CHANGELOG.md)
    local -a replaced=()

    [[ -d "$install_dir" && -w "$install_dir" ]] || {
        printf 'No hay permisos de escritura sobre %s.\n' "$install_dir" >&2
        return 1
    }

    command -v tar >/dev/null 2>&1 || {
        printf 'Falta tar para instalar actualizaciones.\n' >&2
        return 1
    }

    workdir=$(mktemp -d "$install_dir/.keila-update.XXXXXX") || return 1
    archive="$workdir/release.tar.gz"
    extract_dir="$workdir/extract"
    backup_dir="$workdir/backup"
    mkdir -p "$extract_dir" "$backup_dir" || { rm -rf -- "$workdir"; return 1; }

    printf '→ Descargando Keila Radio Player %s...\n' "$version"
    if ! update_download_archive "$version" "$archive"; then
        rm -rf -- "$workdir"
        printf 'No se pudo descargar la actualización.\n' >&2
        return 1
    fi

    if ! update_archive_is_safe "$archive"; then
        rm -rf -- "$workdir"
        printf 'El archivo descargado no es un paquete válido o seguro.\n' >&2
        return 1
    fi

    if ! tar -xzf "$archive" -C "$extract_dir"; then
        rm -rf -- "$workdir"
        printf 'No se pudo extraer la actualización.\n' >&2
        return 1
    fi

    release_root=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)
    [[ -n "$release_root" ]] || {
        rm -rf -- "$workdir"
        printf 'No se encontró el contenido de la actualización.\n' >&2
        return 1
    }

    printf '→ Validando paquete...\n'
    if ! update_validate_tree "$release_root" "$version"; then
        rm -rf -- "$workdir"
        printf 'La actualización no superó la validación. No se modificó la instalación.\n' >&2
        return 1
    fi

    printf '→ Instalando con copia de seguridad temporal...\n'
    for component in "${managed_components[@]}"; do
        [[ -e "$release_root/$component" || -L "$release_root/$component" ]] || continue

        if [[ -e "$install_dir/$component" || -L "$install_dir/$component" ]]; then
            if ! mv -- "$install_dir/$component" "$backup_dir/$component"; then
                update_rollback_files "$install_dir" "$backup_dir" "${replaced[@]}" >/dev/null 2>&1 || true
                rm -rf -- "$workdir"
                printf 'No se pudo crear la copia de seguridad de %s.\n' "$component" >&2
                return 1
            fi
        fi

        replaced+=("$component")
        if ! mv -- "$release_root/$component" "$install_dir/$component"; then
            update_rollback_files "$install_dir" "$backup_dir" "${replaced[@]}" >/dev/null 2>&1 || true
            rm -rf -- "$workdir"
            printf 'Falló la instalación de %s; se restauró la versión anterior.\n' "$component" >&2
            return 1
        fi
    done

    if ! update_postcheck "$install_dir" "$version"; then
        printf 'La nueva versión no superó la comprobación final. Restaurando...\n' >&2
        if ! update_rollback_files "$install_dir" "$backup_dir" "${replaced[@]}"; then
            printf 'ERROR: el rollback automático no pudo completarse. Copia temporal: %s\n' "$backup_dir" >&2
            return 1
        fi
        rm -rf -- "$workdir"
        printf 'Se restauró correctamente la versión anterior.\n' >&2
        return 1
    fi

    rm -rf -- "$workdir"
    printf '✓ Keila Radio Player se actualizó correctamente a %s.\n' "$version"
}

update_install_git() {
    local install_dir="$1" version="$2"
    local branch old_branch old_sha target_tag="v$version"

    command -v git >/dev/null 2>&1 || {
        printf 'Esta instalación usa Git, pero git no está disponible.\n' >&2
        return 1
    }

    branch=$(git -C "$install_dir" branch --show-current 2>/dev/null) || return 1
    if [[ -n "$branch" && "$branch" != 'main' ]]; then
        printf 'Esta es una copia de desarrollo en la rama %s.\n' "$branch" >&2
        printf 'No la sustituiré por una release. Actualízala con sync-keila.sh.\n' >&2
        return 2
    fi

    if [[ -n "$(git -C "$install_dir" status --porcelain 2>/dev/null)" ]]; then
        printf 'Hay cambios locales en la copia Git; no se actualizará para evitar perderlos.\n' >&2
        return 1
    fi

    old_branch="$branch"
    old_sha=$(git -C "$install_dir" rev-parse HEAD) || return 1

    printf '→ Descargando tag oficial %s...\n' "$target_tag"
    if ! git -C "$install_dir" fetch --force "$KEILA_UPDATE_GIT_URL" \
        "refs/tags/$target_tag:refs/tags/$target_tag"; then
        printf 'No se pudo descargar el tag %s.\n' "$target_tag" >&2
        return 1
    fi

    printf '→ Activando release %s...\n' "$target_tag"
    if ! git -C "$install_dir" switch --detach "$target_tag"; then
        return 1
    fi

    if update_postcheck "$install_dir" "$version"; then
        printf '✓ Keila Radio Player se actualizó correctamente a %s.\n' "$version"
        return 0
    fi

    printf 'La nueva release no superó la comprobación final. Restaurando...\n' >&2
    if [[ -n "$old_branch" ]]; then
        git -C "$install_dir" switch "$old_branch" >/dev/null 2>&1 || true
    else
        git -C "$install_dir" switch --detach "$old_sha" >/dev/null 2>&1 || true
    fi
    printf 'Se intentó restaurar la revisión anterior %s.\n' "$old_sha" >&2
    return 1
}

update_install() {
    local install_dir="$1"
    local current="${KEILA_VERSION:-dev}"
    local latest cmp

    latest=$(update_latest_version "$current") || return 1
    cmp=$(update_compare_versions "$latest" "$current") || return 1

    printf 'Keila Radio Player %s\n' "$current"
    if [[ "$cmp" == '0' ]]; then
        printf 'Estás usando la versión más reciente disponible.\n'
        return 0
    fi
    if [[ "$cmp" == '-1' ]]; then
        printf 'Tu versión local es más reciente que la última publicada (%s).\n' "$latest"
        return 0
    fi

    printf 'Nueva versión disponible: %s\n' "$latest"

    if [[ -e "$install_dir/.git" ]]; then
        update_install_git "$install_dir" "$latest"
    else
        update_install_archive "$install_dir" "$latest"
    fi
}

# El launcher actual todavía contiene el antiguo caso --update. Como update.sh
# se carga antes de inicializar reproducción/TUI, interceptamos únicamente este
# comando aquí; así la actualización puede reemplazar archivos sin arrancar mpv.
if [[ "${BASH_SOURCE[0]}" != "$0" && "${0##*/}" == 'keila-radio' && "${1:-}" == '--update' && -n "${BASE_DIR:-}" ]]; then
    update_install "$BASE_DIR"
    exit $?
fi
