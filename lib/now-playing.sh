#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Memoria acotada por sesión. Sin catálogo/DNS/HTTP en cada tick de teclado.
NOW_PLAYING_WORKER="$(dirname "${BASH_SOURCE[0]}")/now-playing-worker.sh"
NP_ENABLED=${KEILA_NOW_PLAYING:-1}
NP_JOB_PID='' NP_JOB_DIR='' NP_URL='' NP_ENDPOINT='' NP_KIND='' NP_NEXT_AT=0 NP_FAILURES=0
NP_JOB_BASELINE=''
NP_TITLE='' NP_HOST='' NP_CHECKED_AT=0 NP_VALID_UNTIL=0 NP_BASELINE='' NP_CONFIRMED=0
NP_DISPLAY_TITLE='' NP_DISPLAY_CONFIRMED_AT=0
declare -A NP_CACHE_ENDPOINTS=() NP_CACHE_KINDS=() NP_CACHE_NEXT=() NP_CACHE_FAILURES=()
NP_CACHE_KEYS=()

now_playing_cleanup() {
    if [[ -n $NP_JOB_PID ]]; then
        player_terminate_group_bounded "$NP_JOB_PID" "$NP_JOB_PID" >/dev/null 2>&1 || true
        wait "$NP_JOB_PID" 2>/dev/null || true
    fi
    NP_JOB_PID=''
    if [[ -n $NP_JOB_DIR && $NP_JOB_DIR == "${TMPDIR:-/tmp}/keila-nowplaying."* && ! -L $NP_JOB_DIR ]]; then
        rm -rf -- "$NP_JOB_DIR"
    fi
    NP_JOB_DIR=''
    NP_JOB_BASELINE=''
}

now_playing_reset() {
    now_playing_cleanup
    NP_URL='' NP_ENDPOINT='' NP_KIND='' NP_NEXT_AT=0 NP_FAILURES=0
    NP_TITLE='' NP_HOST='' NP_CHECKED_AT=0 NP_VALID_UNTIL=0 NP_BASELINE='' NP_CONFIRMED=0
}

now_playing_cache() {
    local old
    [[ -n $NP_URL ]] || return 0
    if [[ -z ${NP_CACHE_NEXT[$NP_URL]+exists} ]]; then
        NP_CACHE_KEYS+=("$NP_URL")
        if ((${#NP_CACHE_KEYS[@]} > 64)); then
            old=${NP_CACHE_KEYS[0]}; NP_CACHE_KEYS=("${NP_CACHE_KEYS[@]:1}")
            unset 'NP_CACHE_ENDPOINTS[$old]' 'NP_CACHE_KINDS[$old]' 'NP_CACHE_NEXT[$old]' 'NP_CACHE_FAILURES[$old]'
        fi
    fi
    NP_CACHE_ENDPOINTS[$NP_URL]=$NP_ENDPOINT NP_CACHE_KINDS[$NP_URL]=$NP_KIND
    NP_CACHE_NEXT[$NP_URL]=$NP_NEXT_AT NP_CACHE_FAILURES[$NP_URL]=$NP_FAILURES
}

now_playing_poll() {
    local now=$1 file=$NP_JOB_DIR/result.json origin job_baseline=$NP_JOB_BASELINE size
    [[ -n $NP_JOB_PID ]] || return 1
    kill -0 "$NP_JOB_PID" 2>/dev/null && return 1
    wait "$NP_JOB_PID" 2>/dev/null || true
    origin=${NP_URL#*://}; origin=${origin%%/*}; origin=${NP_URL%%://*}://$origin
    local -a result=()
    if [[ -f $file && ! -L $file ]] && size=$(stat -c %s -- "$file") && ((size > 0 && size <= 8192)); then
        mapfile -t result < <(jq -ser --arg stream "$NP_URL" --arg origin "$origin/" --argjson now "$now" '
            def text($n): type == "string" and length <= $n and (test("[\u0000-\u001f\u007f-\u009f]") | not);
            def integer: type == "number" and floor == .;
            select(length == 1) | .[0] |
            select(.version == 1 and .stream == $stream and
                   (.kind == "icecast" or .kind == "azuracast") and
                   (.endpoint | text(2048)) and (.endpoint | startswith($origin)) and
                   (.title | text(240)) and (.host | text(60)) and
                   (.checked_at | integer) and .checked_at >= $now-30 and .checked_at <= $now and
                   (.valid_until | integer) and .valid_until >= .checked_at and .valid_until <= .checked_at+120) |
            .title,.host,.checked_at,.valid_until,.endpoint,.kind
        ' "$file" 2>/dev/null)
    fi
    now_playing_cleanup
    if ((${#result[@]} == 6)); then
        NP_TITLE=${result[0]} NP_HOST=${result[1]} NP_CHECKED_AT=${result[2]} NP_VALID_UNTIL=${result[3]}
        NP_ENDPOINT=${result[4]} NP_KIND=${result[5]} NP_BASELINE=$job_baseline
        NP_CONFIRMED=1 NP_FAILURES=0 NP_NEXT_AT=$((now+30))
    else
        ((NP_FAILURES+=1))
        local shift=$NP_FAILURES delay
        ((shift <= 5)) || shift=5
        delay=$((30 * (1 << shift)))
        NP_NEXT_AT=$((now+delay))
        if ((NP_FAILURES == 3)); then NP_ENDPOINT='' NP_KIND=''; fi
    fi
    now_playing_cache
    return 0
}

now_playing_tick() {
    local now=$1 baseline=$2 ready=${3:-${PLAYER_STREAM_READY:-0}} buffering=${4:-${PLAYER_BUFFERING:-0}}
    local url=${PLAYER_INPUT_URL:-${PLAYER_URL:-}}
    if [[ $NP_ENABLED != 1 || ( $url != http://* && $url != https://* ) ]]; then
        [[ -z $NP_URL && -z $NP_JOB_PID ]] || now_playing_reset
        return 0
    fi
    if [[ $url != "$NP_URL" ]]; then
        now_playing_reset
        NP_URL=$url
        NP_ENDPOINT=${NP_CACHE_ENDPOINTS[$url]:-} NP_KIND=${NP_CACHE_KINDS[$url]:-}
        NP_NEXT_AT=${NP_CACHE_NEXT[$url]:-$((now+3))} NP_FAILURES=${NP_CACHE_FAILURES[$url]:-0}
    fi
    if ((${PLAYER_PAUSED:-0} || buffering)); then
        [[ -z $NP_JOB_PID ]] || now_playing_cleanup
        return 0
    fi
    now_playing_poll "$now" || true
    ((ready)) || return 0
    ((now >= NP_NEXT_AT)) && [[ -z $NP_JOB_PID ]] || return 0
    if ! command -v getent >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        NP_NEXT_AT=$((now+960)); now_playing_cache; return 0
    fi
    NP_JOB_DIR=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/keila-nowplaying.XXXXXX") || { NP_NEXT_AT=$((now+60)); return 0; }
    NP_JOB_BASELINE=$baseline
    setsid -- timeout --kill-after=1s 20s bash "$NOW_PLAYING_WORKER" "$url" "$NP_JOB_DIR" "$NP_ENDPOINT" "$NP_KIND" </dev/null >/dev/null 2>&1 &
    NP_JOB_PID=$!
}

now_playing_choose() {
    local now=$1 embedded=$2
    NP_DISPLAY_TITLE=$embedded NP_DISPLAY_CONFIRMED_AT=0
    ((NP_CONFIRMED)) || return 0
    if [[ -n $embedded && $embedded != "$NP_BASELINE" ]]; then
        # Un cambio recibido dentro del audio es más próximo a lo que se oye.
        NP_TITLE='' NP_HOST='' NP_CONFIRMED=0
        return 0
    fi
    NP_DISPLAY_TITLE=''
    if ((now < NP_VALID_UNTIL)) && [[ -n $NP_TITLE || -n $NP_HOST ]]; then
        NP_DISPLAY_TITLE=$NP_TITLE
        if [[ -n $NP_HOST ]]; then
            [[ -z $NP_DISPLAY_TITLE ]] || NP_DISPLAY_TITLE+=' · '
            NP_DISPLAY_TITLE+="En directo: $NP_HOST"
        fi
        NP_DISPLAY_CONFIRMED_AT=$NP_CHECKED_AT
    fi
}
