#!/usr/bin/env bash

# Internacionalización ligera para Bash.
# Las traducciones viven en locale/<idioma>.conf como pares clave=valor.
# Español es el idioma base y también el fallback si una clave no existe.

KEILA_LANGUAGE="${KEILA_LANGUAGE:-es}"
KEILA_LOCALE_DIR="${KEILA_LOCALE_DIR:-${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/locale}"
I18N_LOADED_LANGUAGE=''
declare -gA I18N_BASE=()
declare -gA I18N_TEXT=()

i18n_valid_language() {
    [[ "${1:-}" =~ ^[A-Za-z][A-Za-z0-9_-]{0,15}$ ]]
}

i18n_normalize_language() {
    local language="${1:-es}"
    language="${language%%.*}"
    language="${language%%@*}"
    language="${language//_/-}"
    language="${language,,}"
    case "$language" in
        en-*|en) printf 'en' ;;
        es-*|es|'') printf 'es' ;;
        *) printf '%s' "$language" ;;
    esac
}

i18n_read_file() {
    local file="$1" target="$2" raw key value
    [[ -f "$file" ]] || return 1
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        raw="${raw%$'\r'}"
        [[ -z "$raw" || "${raw:0:1}" == '#' || "$raw" != *=* ]] && continue
        key="${raw%%=*}"
        value="${raw#*=}"
        [[ "$key" =~ ^[A-Za-z0-9_.-]+$ ]] || continue
        printf -v "$target[$key]" '%s' "$value"
    done < "$file"
}

i18n_load() {
    local requested="${1:-${KEILA_LANGUAGE:-es}}" language
    language=$(i18n_normalize_language "$requested")
    i18n_valid_language "$language" || language='es'

    I18N_BASE=()
    I18N_TEXT=()
    i18n_read_file "$KEILA_LOCALE_DIR/es.conf" I18N_BASE || true
    if [[ "$language" != es ]]; then
        i18n_read_file "$KEILA_LOCALE_DIR/$language.conf" I18N_TEXT || language='es'
    fi
    KEILA_LANGUAGE="$language"
    I18N_LOADED_LANGUAGE="$language"
}

i18n_ensure_loaded() {
    if [[ -z "$I18N_LOADED_LANGUAGE" || "$I18N_LOADED_LANGUAGE" != "${KEILA_LANGUAGE:-es}" ]]; then
        i18n_load "${KEILA_LANGUAGE:-es}"
    fi
}

tr_ui() {
    local key="$1" fallback="${2:-$1}" text
    i18n_ensure_loaded
    text="${I18N_TEXT[$key]:-${I18N_BASE[$key]:-$fallback}}"
    shift || true
    shift || true
    if (($# > 0)); then
        printf "$text" "$@"
    else
        printf '%s' "$text"
    fi
}
