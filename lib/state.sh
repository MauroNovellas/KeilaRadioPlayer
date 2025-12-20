#!/bin/bash

mkdir -p "$(dirname "$STATE")"

VOL_ACTUAL=40
LAST_NAME=""
LAST_URL=""

load_state() {
    [ -f "$STATE" ] || return
    source "$STATE"
}

save_state() {
    cat > "$STATE" <<EOF
VOL_ACTUAL=$VOL_ACTUAL
LAST_NAME="$ACTUAL_NOMBRE"
LAST_URL="$ACTUAL_URL"
EOF
}