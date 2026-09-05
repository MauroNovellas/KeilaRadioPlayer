#!/usr/bin/env bash

# Rutas XDG y valores por defecto de Keila Radio Player v2.

KEILA_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/keila-radio"
KEILA_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/keila-radio"
KEILA_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/keila-radio"

KEILA_FAVORITES_FILE="$KEILA_CONFIG_DIR/favorites"
KEILA_STATE_FILE="$KEILA_STATE_DIR/state"
KEILA_STATIONS_JSON="$KEILA_CACHE_DIR/radio.json"

KEILA_TDTCHANNELS_RADIO_URL="${KEILA_TDTCHANNELS_RADIO_URL:-https://www.tdtchannels.com/lists/radio.json}"
KEILA_CATALOG_MAX_AGE="${KEILA_CATALOG_MAX_AGE:-86400}"
KEILA_DEFAULT_VOLUME=50

keila_init_paths() {
    mkdir -p "$KEILA_CONFIG_DIR" "$KEILA_STATE_DIR" "$KEILA_CACHE_DIR"
    chmod 700 "$KEILA_CONFIG_DIR" "$KEILA_STATE_DIR" "$KEILA_CACHE_DIR" 2>/dev/null || true
}
