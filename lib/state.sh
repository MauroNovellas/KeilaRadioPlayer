#!/usr/bin/env bash

# Persistencia segura: este archivo se lee como datos, nunca con `source`.

STATE_VOLUME="${KEILA_DEFAULT_VOLUME:-50}"
STATE_LAST_NAME=""
STATE_LAST_URL=""

state_load() {
    STATE_VOLUME="${KEILA_DEFAULT_VOLUME:-50}"
    STATE_LAST_NAME=""
    STATE_LAST_URL=""

    [[ -f "$KEILA_STATE_FILE" ]] || return 0

    local key value
    while IFS=$'\t' read -r key value; do
        case "$key" in
            volume)
                if [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 0 && value <= 100)); then
                    STATE_VOLUME="$value"
                fi
                ;;
            last_name)
                STATE_LAST_NAME="$value"
                ;;
            last_url)
                STATE_LAST_URL="$value"
                ;;
        esac
    done < "$KEILA_STATE_FILE"
}

state_save() {
    keila_init_paths || return 1

    local lock_dir="${KEILA_STATE_FILE}.lock"
    lock_acquire "$lock_dir" || return 1

    local tmp="${KEILA_STATE_FILE}.tmp.$$"
    local status=0
    umask 077

    {
        printf 'volume\t%s\n' "$STATE_VOLUME"
        printf 'last_name\t%s\n' "$STATE_LAST_NAME"
        printf 'last_url\t%s\n' "$STATE_LAST_URL"
    } > "$tmp" || status=1

    if ((status == 0)); then
        mv -f "$tmp" "$KEILA_STATE_FILE" || status=1
    fi

    if ((status == 0)); then
        chmod 600 "$KEILA_STATE_FILE" 2>/dev/null || true
    else
        rm -f "$tmp" 2>/dev/null || true
    fi

    lock_release "$lock_dir" || status=1
    return "$status"
}
