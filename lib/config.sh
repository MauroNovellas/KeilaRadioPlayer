#!/usr/bin/env bash

# Rutas XDG y configuración segura de Keila Radio Player v2.
# El fichero de usuario se interpreta como datos; nunca se ejecuta con `source`.

KEILA_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/keila-radio"
KEILA_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/keila-radio"
KEILA_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/keila-radio"

KEILA_CONFIG_FILE="$KEILA_CONFIG_DIR/config"
KEILA_FAVORITES_FILE="$KEILA_CONFIG_DIR/favorites"
KEILA_STATE_FILE="$KEILA_STATE_DIR/state"
KEILA_STATIONS_JSON="$KEILA_CACHE_DIR/radio.json"
KEILA_STATIONS_TSV="$KEILA_CACHE_DIR/radio.tsv"

KEILA_RADIO_BROWSER_SERVER_DISCOVERY_URL="${KEILA_RADIO_BROWSER_SERVER_DISCOVERY_URL:-https://all.api.radio-browser.info/json/servers}"
KEILA_RADIO_BROWSER_FALLBACK_URL="${KEILA_RADIO_BROWSER_FALLBACK_URL:-https://de1.api.radio-browser.info}"
KEILA_RADIO_BROWSER_USER_AGENT="${KEILA_RADIO_BROWSER_USER_AGENT:-KeilaRadioPlayer/${KEILA_VERSION:-dev} https://github.com/MauroNovellas/KeilaRadioPlayer}"
KEILA_DEFAULT_VOLUME=50
KEILA_VOLUME_STEP=5
KEILA_PLAYER_INFO_INTERVAL=1
KEILA_CATALOG_MAX_AGE=86400
KEILA_CATALOG_LIMIT=50000
KEILA_CATALOG_COUNTRY_FILTER=ES
KEILA_SEARCH_MATCH_LIMIT=300
KEILA_RECORDINGS_DIR=""
KEILA_LANGUAGE="${KEILA_LANG:-${KEILA_LANGUAGE:-es}}"

keila_init_paths() {
    mkdir -p "$KEILA_CONFIG_DIR" "$KEILA_STATE_DIR" "$KEILA_CACHE_DIR"
    chmod 700 "$KEILA_CONFIG_DIR" "$KEILA_STATE_DIR" "$KEILA_CACHE_DIR" 2>/dev/null || true
}

config_trim() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

config_reset_defaults() {
    local default_recordings_dir="$1"

    KEILA_VOLUME_STEP=5
    KEILA_PLAYER_INFO_INTERVAL=1
    KEILA_CATALOG_MAX_AGE=86400
    KEILA_CATALOG_LIMIT=50000
    KEILA_CATALOG_COUNTRY_FILTER=ES
    KEILA_SEARCH_MATCH_LIMIT=300
    KEILA_RECORDINGS_DIR="$default_recordings_dir"
    KEILA_LANGUAGE="${KEILA_LANG:-es}"
}

config_write_default() {
    [[ -e "$KEILA_CONFIG_FILE" ]] && return 0

    local tmp status=0
    tmp=$(mktemp "${KEILA_CONFIG_FILE}.tmp.XXXXXX") || return 1
    umask 077

    cat > "$tmp" <<'EOF' || status=1
# Keila Radio Player v2
# Este archivo es opcional. Los valores inválidos se ignoran y usan el defecto.

# Incremento de volumen para A/D y flechas izquierda/derecha (1-50).
volume_step=5

# Cada cuántos segundos consultar metadatos de mpv (1-60).
metadata_interval=1

# Tiempo máximo de la caché de Radio Browser en segundos. 0 = actualizar siempre.
catalog_max_age=86400

# Máximo de emisoras a guardar desde Radio Browser.
catalog_limit=50000

# País preferido para el filtro rápido de búsqueda (ISO 3166-1 alpha-2).
catalog_country_filter=ES

# Máximo de resultados visibles por búsqueda. El catálogo completo sigue indexado.
search_match_limit=300

# Idioma de la interfaz: es o en. KEILA_LANG tiene prioridad si se define.
language=es

# Vacío = carpeta "grabaciones" junto a keila-radio.
# También admite rutas absolutas, ~/... o rutas relativas a $HOME.
recordings_dir=
EOF

    if ((status == 0)); then
        # Publicación exclusiva: otra sesión puede haber creado el fichero.
        ln -- "$tmp" "$KEILA_CONFIG_FILE" 2>/dev/null || {
            [[ -f "$KEILA_CONFIG_FILE" ]] || status=1
        }
    fi
    rm -f -- "$tmp"
    return "$status"
}

config_expand_path() {
    local value="$1"
    local fallback="$2"

    case "$value" in
        '')
            printf '%s' "$fallback"
            ;;
        '~')
            printf '%s' "$HOME"
            ;;
        \~/*)
            printf '%s/%s' "$HOME" "${value:2}"
            ;;
        /*)
            printf '%s' "$value"
            ;;
        *)
            printf '%s/%s' "$HOME" "$value"
            ;;
    esac
}

config_load() {
    local default_recordings_dir="$1"

    config_reset_defaults "$default_recordings_dir"
    keila_init_paths || return 1
    config_write_default || return 1

    [[ -f "$KEILA_CONFIG_FILE" ]] || return 0

    local raw key value number
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        raw="${raw%$'\r'}"
        raw=$(config_trim "$raw")

        [[ -z "$raw" || "${raw:0:1}" == '#' ]] && continue
        [[ "$raw" == *=* ]] || continue

        key=$(config_trim "${raw%%=*}")
        value=$(config_trim "${raw#*=}")

        case "$key" in
            volume_step)
                if [[ "$value" =~ ^[0-9]+$ && ${#value} -le 9 ]]; then
                    number=$((10#$value))
                    if ((number >= 1 && number <= 50)); then
                        KEILA_VOLUME_STEP="$number"
                    fi
                fi
                ;;
            metadata_interval)
                if [[ "$value" =~ ^[0-9]+$ && ${#value} -le 9 ]]; then
                    number=$((10#$value))
                    if ((number >= 1 && number <= 60)); then
                        KEILA_PLAYER_INFO_INTERVAL="$number"
                    fi
                fi
                ;;
            catalog_max_age)
                if [[ "$value" =~ ^[0-9]+$ && ${#value} -le 9 ]]; then
                    number=$((10#$value))
                    if ((number >= 0 && number <= 31536000)); then
                        KEILA_CATALOG_MAX_AGE="$number"
                    fi
                fi
                ;;
            catalog_limit)
                if [[ "$value" =~ ^[0-9]+$ && ${#value} -le 9 ]]; then
                    number=$((10#$value))
                    if ((number >= 100 && number <= 100000)); then
                        KEILA_CATALOG_LIMIT="$number"
                    fi
                fi
                ;;
            catalog_country_filter)
                value="${value^^}"
                if [[ "$value" =~ ^[A-Z][A-Z]$ ]]; then
                    KEILA_CATALOG_COUNTRY_FILTER="$value"
                fi
                ;;
            search_match_limit)
                if [[ "$value" =~ ^[0-9]+$ && ${#value} -le 9 ]]; then
                    number=$((10#$value))
                    if ((number >= 100 && number <= 20000)); then
                        KEILA_SEARCH_MATCH_LIMIT="$number"
                    fi
                fi
                ;;
            recordings_dir)
                KEILA_RECORDINGS_DIR=$(config_expand_path "$value" "$default_recordings_dir")
                ;;
            language)
                if [[ -z "${KEILA_LANG:-}" ]]; then
                    value="${value%%.*}"
                    value="${value%%@*}"
                    value="${value//_/-}"
                    value="${value,,}"
                    case "$value" in
                        en-*|en) KEILA_LANGUAGE=en ;;
                        es-*|es) KEILA_LANGUAGE=es ;;
                    esac
                fi
                ;;
        esac
    done < "$KEILA_CONFIG_FILE"

    if [[ -n "${KEILA_LANG:-}" ]]; then
        value="${KEILA_LANG%%.*}"
        value="${value%%@*}"
        value="${value//_/-}"
        value="${value,,}"
        case "$value" in
            en-*|en) KEILA_LANGUAGE=en ;;
            es-*|es) KEILA_LANGUAGE=es ;;
        esac
    fi
}
