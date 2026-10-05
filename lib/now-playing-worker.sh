#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Solo JSON público de la autoridad del stream; no escanear webs ni descargar audio.
# shellcheck source=lib/station-logo-worker.sh
source "$(dirname "${BASH_SOURCE[0]}")/station-logo-worker.sh"

now_playing_fetch() {
    local url=$1 directory=$2 ip line hop response code redirect age size
    for ((hop=0; hop<3; hop++)); do
        logo_url_parts "$url" || return 1
        ip=''
        while read -r line _; do
            if logo_public_ipv4 "$line"; then ip=$line; break; fi
        done < <(logo_resolve "$LOGO_HTTP_HOST")
        [[ -n $ip ]] || return 1
        response=$(curl --disable --silent --show-error --noproxy '*' --proto '=http,https' \
            --connect-timeout 2 --max-time 4 --max-filesize 524288 --max-redirs 0 \
            --resolve "$LOGO_HTTP_HOST:$LOGO_HTTP_PORT:$ip" --user-agent 'KeilaRadioPlayer-nowplaying/1' \
            --header 'Accept: application/json' --header 'Cache-Control: no-cache' \
            --dump-header "$directory/headers" --output "$directory/response" \
            --write-out $'%{http_code}\n%{redirect_url}' -- "$url" 2>/dev/null) || return 1
        code=${response%%$'\n'*} redirect=${response#*$'\n'}
        if [[ $code == 200 ]]; then
            size=$(stat -c %s -- "$directory/response") || return 1
            ((size > 0 && size <= 524288)) || return 1
            while IFS= read -r line; do
                if [[ ${line,,} == age:* ]]; then
                    age=${line#*:}; age=${age//[[:space:]]/}
                    [[ $age =~ ^[0-9]{1,8}$ ]] && ((10#$age < 120)) || return 1
                fi
            done < "$directory/headers"
            return 0
        fi
        [[ $code == 30[12378] && -n $redirect && $redirect != "$response" ]] || return 1
        url=$redirect
    done
    return 1
}

now_playing_worker() {
    local stream=$1 directory=$2 endpoint=${3:-} kind=${4:-} base origin path shortcode candidate type
    base=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    logo_url_parts "$stream" || return 1
    [[ -d $directory && ! -L $directory ]] || return 1
    if [[ $stream =~ ^(https?://[^/]+)(/.*)?$ ]]; then origin=${BASH_REMATCH[1]} path=${BASH_REMATCH[2]:-/}; else return 1; fi
    local -a candidates=() types=()
    if [[ -n $endpoint ]]; then
        [[ $endpoint == "$origin/"* && $kind =~ ^(icecast|azuracast)$ ]] || return 1
        candidates=("$endpoint") types=("$kind")
    else
        if [[ $path =~ ^/(listen|hls)/([A-Za-z0-9_-]+)/ ]]; then
            shortcode=${BASH_REMATCH[2]}
            candidates+=("$origin/api/nowplaying_static/$shortcode.json") types+=(azuracast)
        fi
        candidates+=("$origin/status-json.xsl" "$origin/api/nowplaying") types+=(icecast azuracast)
    fi
    local index now
    for index in "${!candidates[@]}"; do
        candidate=${candidates[index]} type=${types[index]}
        now_playing_fetch "$candidate" "$directory" || continue
        now=${NOW_PLAYING_WORKER_NOW:-$EPOCHSECONDS}
        if jq -e -L "$base" --arg stream "$stream" --arg endpoint "$candidate" --arg kind "$type" \
            --argjson now "$now" -f "$base/now-playing-response.jq" "$directory/response" > "$directory/result.tmp" 2>/dev/null; then
            mv -- "$directory/result.tmp" "$directory/result.json"
            return $?
        fi
    done
    return 1
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -uo pipefail
    umask 077
    (($# == 4)) || exit 2
    ulimit -f 2048 2>/dev/null || true
    now_playing_worker "$@"
fi
