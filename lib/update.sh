#!/usr/bin/env bash

KEILA_UPDATE_TAGS_URL="${KEILA_UPDATE_TAGS_URL:-https://api.github.com/repos/MauroNovellas/KeilaRadioPlayer/tags?per_page=100}"

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

update_check() {
    local current="${KEILA_VERSION:-dev}"
    local tags latest cmp

    if ! update_parse_version "$current"; then
        printf 'La versión local no tiene un formato comparable: %s\n' "$current" >&2
        return 1
    fi

    if ! tags=$(update_fetch_tags); then
        printf 'No se pudo consultar GitHub para buscar actualizaciones.\n' >&2
        return 1
    fi

    if ! latest=$(printf '%s\n' "$tags" | update_select_latest "$current"); then
        printf 'No se encontraron versiones publicadas compatibles.\n' >&2
        return 1
    fi

    cmp=$(update_compare_versions "$latest" "$current") || return 1

    printf 'Keila Radio Player %s\n' "$current"
    if [[ "$cmp" == '1' ]]; then
        printf 'Nueva versión disponible: %s\n' "$latest"
        printf 'La instalación automática se habilitará con --update en la siguiente etapa.\n'
    elif [[ "$cmp" == '0' ]]; then
        printf 'Estás usando la versión más reciente disponible.\n'
    else
        printf 'Tu versión local es más reciente que la última publicada (%s).\n' "$latest"
    fi
}
