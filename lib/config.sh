#!/usr/bin/env bash

# Rutas XDG y valores por defecto de Keila Radio Player v2.

KEILA_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/keila-radio"
KEILA_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/keila-radio"

KEILA_FAVORITES_FILE="$KEILA_CONFIG_DIR/favorites"
KEILA_STATE_FILE="$KEILA_STATE_DIR/state"

KEILA_DEFAULT_VOLUME=50

keila_init_paths() {
    mkdir -p "$KEILA_CONFIG_DIR" "$KEILA_STATE_DIR"
    chmod 700 "$KEILA_CONFIG_DIR" "$KEILA_STATE_DIR" 2>/dev/null || true
}
