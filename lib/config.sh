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

KEILA_TDTCHANNELS_RADIO_URL="${KEILA_TDTCHANNELS_RADIO_URL:-https://www.tdtchannels.com/lists/radio.json}"
KEILA_DEFAULT_VOLUME=50
KEILA_VOLUME_STEP=5
KEILA_PLAYER_INFO_INTERVAL=1
KEILA_CATALOG_MAX_AGE=86400
KEILA_RECORDINGS_DIR=""

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
    KEILA_RECORDINGS_DIR="$default_recordings_dir"
}

config_write_default() {
    [[ -e "$KEILA_CONFIG_FILE" ]] && return 0

    local tmp="${KEILA_CONFIG_FILE}.tmp.$$"
    umask 077

    cat > "$tmp" <<'EOF'
# Keila Radio Player v2
# Este archivo es opcional. Los valores inválidos se ignoran y usan el defecto.

# Incremento de volumen para A/D y flechas izquierda/derecha (1-50).
volume_step=5

# Cada cuántos segundos consultar metadatos de mpv (1-60).
metadata_interval=1

# Tiempo máximo de la caché de TDTChannels en segundos. 0 = actualizar siempre.
catalog_max_age=86400

# Vacío = carpeta "grabaciones" junto a keila-radio.
# También admite rutas absolutas, ~/... o rutas relativas a $HOME.
recordings_dir=
EOF

    mv -f "$tmp" "$KEILA_CONFIG_FILE"
    chmod 600 "$KEILA_CONFIG_FILE" 2>/dev/null || true
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
        /*)
            printf '%s' "$value"
            ;;
        *)
            if [[ "${value:0:2}" == '~/' ]]; then
                printf '%s/%s' "$HOME" "${value:2}"
            else
                printf '%s/%s' "$HOME" "$value"
            fi
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
            recordings_dir)
                KEILA_RECORDINGS_DIR=$(config_expand_path "$value" "$default_recordings_dir")
                ;;
        esac
    done < "$KEILA_CONFIG_FILE"
}
