#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Solo al abrir Opciones: catálogo primero, una lista HLS después. Sin audio.
quality_fetch_playlist() {
    local url=$1 directory=$2 ip line hop response code redirect
    QUALITY_FETCH_URL=''
    command -v getent >/dev/null 2>&1 || return 1
    for ((hop=0; hop<3; hop++)); do
        logo_url_parts "$url" || return 1
        ip=''
        while read -r line _; do
            if logo_public_ipv4 "$line"; then ip=$line; break; fi
        done < <(logo_resolve "$LOGO_HTTP_HOST")
        [[ -n $ip ]] || return 1
        response=$(curl --disable --silent --show-error --noproxy '*' --proto '=http,https' \
            --connect-timeout 3 --max-time 8 --max-filesize 65536 --max-redirs 0 \
            --resolve "$LOGO_HTTP_HOST:$LOGO_HTTP_PORT:$ip" --user-agent 'KeilaRadioPlayer-quality/1' \
            --output "$directory/playlist" --write-out $'%{http_code}\n%{redirect_url}' -- "$url" 2>/dev/null) || return 1
        code=${response%%$'\n'*} redirect=${response#*$'\n'}
        if [[ $code == 200 ]]; then QUALITY_FETCH_URL=$url; return 0; fi
        [[ $code == 30[12378] && -n $redirect && $redirect != "$response" ]] || return 1
        url=$redirect
    done
    return 1
}

quality_worker() {
    local origin=$1 input=$2 name=$3 catalog=$4 directory=$5 base result probe=0 rate codec size
    base=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    # shellcheck source=lib/data-safety.sh
    source "$base/data-safety.sh"
    # Reutiliza validación de URL/IP y DNS fijado, no el descargador de imágenes.
    # shellcheck source=lib/station-logo-worker.sh
    source "$base/station-logo-worker.sh"
    data_quality_url_valid "$origin" && data_quality_url_valid "$input" || return 1
    [[ -d $directory && ! -L $directory ]] || return 1
    result="$directory/catalog.tmp"
    if [[ -f $catalog && ! -L $catalog ]]; then
        timeout --kill-after=1s 8s jq --arg origin "$origin" --arg input "$input" -f "$base/quality-candidates.jq" "$catalog" > "$result" || rm -f -- "$result"
    fi
    if [[ ! -s $result ]]; then
        jq -n --arg origin "$origin" '{version:1,probe_hls:false,rows:[{url:$origin,rate:0,codec:"",bits:0,kind:"original"}],notice:"Sin catálogo disponible; se mantiene la emisión original."}' > "$result" || return 1
    fi
    mv -- "$result" "$directory/catalog.json" || return 1
    [[ ${input,,} != *.m3u8* ]] || probe=1
    jq -e '.probe_hls == true' "$directory/catalog.json" >/dev/null && probe=1
    if ((probe)); then
        if quality_fetch_playlist "$input" "$directory" && [[ -f $directory/playlist && ! -L $directory/playlist ]]; then
            size=$(stat -c %s -- "$directory/playlist") || return 1
            if ((size <= 65536)) && ! IFS= read -r -d '' _ < "$directory/playlist" &&
                LC_ALL=C awk -f "$base/quality-hls.awk" "$directory/playlist" > "$directory/variants"; then
                : > "$directory/hls.jsonl"
                while IFS=$'\t' read -r rate codec; do
                    jq -nc --arg url "$input" --arg codec "$codec" --argjson rate "$rate" \
                        '{url:$url,rate:$rate,codec:$codec,bits:$rate,kind:"hls"}' >> "$directory/hls.jsonl" || return 1
                done < "$directory/variants"
                jq --slurpfile variants "$directory/hls.jsonl" \
                    '.rows += (if ($variants|length)>1 then $variants else [] end) |
                     .notice += (if ($variants|length)>1 then " Variantes de audio publicadas por la lista HLS; bitrate de transporte aproximado."
                                 elif ($variants|length)==1 then " La lista HLS solo anuncia una variante de audio."
                                 else " Sin variantes de audio compatibles en esta lista HLS." end)' \
                    "$directory/catalog.json" > "$directory/result.tmp" || return 1
            fi
        fi
        if [[ ! -s $directory/result.tmp ]]; then
            jq '.notice += " No se pudo comprobar la lista HLS (red, acceso o formato). No se inventan calidades."' \
                "$directory/catalog.json" > "$directory/result.tmp" || return 1
        fi
    else cp -- "$directory/catalog.json" "$directory/result.tmp" || return 1; fi
    mv -- "$directory/result.tmp" "$directory/result.json"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -uo pipefail
    umask 077
    (($# == 5)) || exit 2
    ulimit -f 2048 2>/dev/null || true
    quality_worker "$@"
fi
