#!/bin/bash

tput civis
trap 'tput cnorm; exit' INT TERM

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$BASE_DIR/lib"

source "$LIB/config.sh"
source "$LIB/state.sh"
source "$LIB/ui.sh"
source "$LIB/player.sh"
source "$LIB/search.sh"
source "$LIB/input.sh"

init_state
init_player

load_state
load_favorites

[ -n "$LAST_URL" ] && reproducir "$LAST_NAME" "$LAST_URL"

main_loop
