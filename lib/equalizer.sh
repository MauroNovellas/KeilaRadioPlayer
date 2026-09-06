#!/usr/bin/env bash

# Ecualizador gráfico de cinco bandas. Se guarda separado de config para no
# reescribir las preferencias que el usuario haya editado a mano.
EQUALIZER_FREQUENCIES=(60 250 1000 4000 12000)
EQUALIZER_LABELS=(60Hz 250Hz 1kHz 4kHz 12kHz)
EQUALIZER_GAINS=(0 0 0 0 0)
EQUALIZER_SELECTED=0
EQUALIZER_EDITOR_ACTIVE=0
KEILA_EQUALIZER_FILE="${KEILA_CONFIG_DIR}/equalizer"

equalizer_gain_valid() {
    [[ "$1" =~ ^-?[0-9]+$ ]] && (($1 >= -12 && $1 <= 12))
}

equalizer_is_flat() {
    local gain
    for gain in "${EQUALIZER_GAINS[@]}"; do ((gain == 0)) || return 1; done
}

equalizer_filter() {
    equalizer_is_flat && return 1

    local i filter='lavfi=['
    for ((i = 0; i < ${#EQUALIZER_FREQUENCIES[@]}; i++)); do
        ((i > 0)) && filter+=','
        filter+="equalizer=f=${EQUALIZER_FREQUENCIES[i]}:t=q:w=1:g=${EQUALIZER_GAINS[i]}"
    done
    printf '%s]' "$filter"
}

equalizer_load() {
    EQUALIZER_GAINS=(0 0 0 0 0)
    [[ -f "$KEILA_EQUALIZER_FILE" ]] || return 0

    local raw gains i
    IFS= read -r raw < "$KEILA_EQUALIZER_FILE" || return 0
    IFS=',' read -r -a gains <<< "$raw"
    ((${#gains[@]} == 5)) || return 0
    for ((i = 0; i < 5; i++)); do
        equalizer_gain_valid "${gains[i]}" || return 0
    done
    EQUALIZER_GAINS=("${gains[@]}")
}

equalizer_save() {
    local file="$KEILA_EQUALIZER_FILE" tmp
    lock_acquire "${file}.lock" || return 1
    tmp=$(mktemp "${file}.tmp.XXXXXX") || { lock_release "${file}.lock"; return 1; }
    (IFS=,; printf '%s\n' "${EQUALIZER_GAINS[*]}") > "$tmp" || {
        rm -f "$tmp"
        lock_release "${file}.lock"
        return 1
    }
    if ! mv -f "$tmp" "$file"; then
        rm -f "$tmp"
        lock_release "${file}.lock"
        return 1
    fi
    chmod 600 "$file" 2>/dev/null || true
    lock_release "${file}.lock"
}

equalizer_summary() {
    if equalizer_is_flat; then
        printf 'Plano'
    else
        printf '60:%+d 250:%+d 1k:%+d 4k:%+d 12k:%+d' "${EQUALIZER_GAINS[@]}"
    fi
}

equalizer_apply() {
    player_is_running || return 0

    local filter payload
    filter=$(equalizer_filter) || filter=''
    payload=$(jq -cn --arg filter "$filter" '{command:["af","set",$filter]}') || return 1
    player_ipc "$payload"
}

equalizer_set_gain() {
    local index="$1" gain="$2"
    [[ "$index" =~ ^[0-4]$ ]] || return 1
    equalizer_gain_valid "$gain" || return 1

    local previous="${EQUALIZER_GAINS[index]}"
    EQUALIZER_GAINS[index]="$gain"
    if ! equalizer_apply; then
        EQUALIZER_GAINS[index]="$previous"
        return 1
    fi
    equalizer_save || return 1
}

equalizer_change_selected() {
    local delta="$1"
    local next=$((EQUALIZER_GAINS[EQUALIZER_SELECTED] + delta))
    ((next < -12)) && next=-12
    ((next > 12)) && next=12
    equalizer_set_gain "$EQUALIZER_SELECTED" "$next"
}

equalizer_center_selected() {
    equalizer_set_gain "$EQUALIZER_SELECTED" 0
}

equalizer_reset() {
    local previous=("${EQUALIZER_GAINS[@]}")
    EQUALIZER_GAINS=(0 0 0 0 0)
    if ! equalizer_apply; then
        EQUALIZER_GAINS=("${previous[@]}")
        return 1
    fi
    equalizer_save
}
