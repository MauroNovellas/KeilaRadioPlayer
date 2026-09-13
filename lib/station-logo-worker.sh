#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Datos de imagen normalizados; nunca guardar ni ejecutar escapes del servidor.

logo_read_render() {
    local file=$1 blob='' header rest LC_ALL=C
    [[ -f "$file" && ! -L "$file" ]] || return 1
    IFS= read -r -N 40000 blob < "$file" || true
    ((${#blob} < 40000)) || return 1
    header=${blob%%$'\n'*} rest=${blob#*$'\n'}
    [[ "$header" == keila-logo-v1 ]] || return 1
    LOGO_PIXELS_BASE64=${rest%%$'\n'*} rest=${rest#*$'\n'}
    LOGO_PIXELS_HEX=${rest%$'\n'}
    [[ ${#LOGO_PIXELS_BASE64} == 36864 && "$LOGO_PIXELS_BASE64" != *[!a-zA-Z0-9+/]* &&
        ${#LOGO_PIXELS_HEX} == 864 && "$LOGO_PIXELS_HEX" != *[!0-9a-f]* ]]
}

logo_public_ipv4() {
    local ip=$1 a b c d
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r a b c d <<< "$ip"
    a=$((10#$a)) b=$((10#$b)) c=$((10#$c)) d=$((10#$d))
    ((a > 0 && a < 224 && b < 256 && c < 256 && d < 256)) || return 1
    ((a != 10 && a != 127)) || return 1
    ((a != 169 || b != 254)) || return 1
    ((a != 172 || b < 16 || b > 31)) || return 1
    ((a != 192 || (b != 168 && b != 0))) || return 1
    ((a != 100 || b < 64 || b > 127)) || return 1
    ((a != 198 || (b != 18 && b != 19 && (b != 51 || c != 100)))) || return 1
    ((a != 203 || b != 0 || c != 113))
}

logo_url_parts() {
    local url=$1
    ((${#url} <= 2048)) || return 1
    [[ "$url" != *[[:space:][:cntrl:]\\]* && "$url" =~ ^(https?)://([a-zA-Z0-9.-]+)(:([0-9]{1,5}))?(/.*)?$ ]] || return 1
    LOGO_HTTP_HOST=${BASH_REMATCH[2]} LOGO_HTTP_PORT=${BASH_REMATCH[4]}
    if [[ -z "$LOGO_HTTP_PORT" ]]; then
        LOGO_HTTP_PORT=80; [[ ${BASH_REMATCH[1]} != https ]] || LOGO_HTTP_PORT=443
    fi
    ((10#$LOGO_HTTP_PORT > 0 && 10#$LOGO_HTTP_PORT <= 65535)) || return 1
    LOGO_HTTP_PORT=$((10#$LOGO_HTTP_PORT))
    [[ "$LOGO_HTTP_HOST" != .* && "$LOGO_HTTP_HOST" != *..* ]]
}

logo_resolve() {
    timeout --kill-after=1s 3s getent ahostsv4 "$1" 2>/dev/null
}

logo_fetch() {
    local url=$1 job=$2 ip='' line hop response code redirect
    for ((hop=0; hop<3; hop++)); do
        logo_url_parts "$url" || return 1
        ip=''
        # Fijar la IP verificada evita DNS rebinding y destinos de red privada.
        while read -r line _; do
            if logo_public_ipv4 "$line"; then ip=$line; break; fi
        done < <(logo_resolve "$LOGO_HTTP_HOST")
        [[ -n "$ip" ]] || return 1
        response=$(curl --disable --silent --show-error --noproxy '*' --proto '=http,https' \
            --connect-timeout 3 --max-time 8 --max-filesize 1048576 --max-redirs 0 \
            --resolve "$LOGO_HTTP_HOST:$LOGO_HTTP_PORT:$ip" --user-agent 'KeilaRadioPlayer-logo/1' \
            --output "$job/image" --write-out $'%{http_code}\n%{redirect_url}' -- "$url" 2>/dev/null) || return 1
        code=${response%%$'\n'*} redirect=${response#*$'\n'}
        if [[ "$code" == 200 ]]; then return 0; fi
        [[ "$code" == 30[12378] && -n "$redirect" && "$redirect" != "$response" ]] || return 1
        url=$redirect
    done
    return 1
}

logo_convert() {
    local job=$1 magic codec size
    size=$(stat -c %s "$job/image") || return 1
    ((size > 0 && size <= 1048576)) || return 1
    magic=$(od -An -tx1 -N8 "$job/image" | tr -d ' \n') || return 1
    case "$magic" in 89504e470d0a1a0a) codec=png ;; ffd8ff*) codec=mjpeg ;; *) return 1 ;; esac
    # Forzar decodificador y protocolos: un favicon no puede abrir playlists,
    # SVG, archivos locales externos ni URLs secundarias. Solo el primer cuadro.
    timeout --kill-after=1s 6s ffmpeg -nostdin -v error -threads 1 -filter_threads 1 -protocol_whitelist file,pipe \
        -f image2 -pattern_type none -c:v "$codec" -max_pixels 4194304 -i "$job/image" \
        -vf 'scale=96:96:force_original_aspect_ratio=decrease,pad=96:96:(ow-iw)/2:(oh-ih)/2:color=black,format=rgb24' \
        -frames:v 1 -threads 1 -f rawvideo "$job/rgb" || return 1
    [[ $(stat -c %s "$job/rgb") == 27648 ]] || return 1
    timeout --kill-after=1s 6s ffmpeg -nostdin -v error -threads 1 -filter_threads 1 -f rawvideo -pixel_format rgb24 \
        -video_size 96x96 -i "$job/rgb" -vf scale=12:12 -frames:v 1 -threads 1 -f rawvideo "$job/small" || return 1
    [[ $(stat -c %s "$job/small") == 432 ]] || return 1
    {
        printf 'keila-logo-v1\n'
        base64 -w0 "$job/rgb"; printf '\n'
        od -An -v -tx1 "$job/small" | tr -d ' \n'; printf '\n'
    } > "$job/result"
    logo_read_render "$job/result"
}

logo_cache_store() {
    local cache=$1 key=$2 result=$3 path name modified oldest='' oldest_time=9223372036854775807 count=0
    # Si hay otra instancia publicando, basta el resultado privado de esta tarea.
    # lock_acquire lee esta variable mediante el alcance dinámico de Bash.
    # shellcheck disable=SC2034
    local KEILA_LOCK_ATTEMPTS=1
    lock_acquire "$cache/cache.lock" || return 0
    for path in "$cache"/*.logo; do
        name=${path##*/}
        [[ "$name" =~ ^[0-9a-f]{64}\.logo$ && -f "$path" && ! -L "$path" ]] || continue
        count=$((count+1))
        modified=$(stat -c %Y "$path") || continue
        if ((modified < oldest_time)); then oldest=$path oldest_time=$modified; fi
    done
    if ((count >= 64)) && [[ -n "$oldest" ]]; then rm -f -- "$oldest"; fi
    # Solo nuestro temporal hermano se publica; no seguir enlaces preexistentes.
    local tmp
    tmp=$(mktemp "$cache/.logo.XXXXXX") || { lock_release "$cache/cache.lock"; return 0; }
    if cp -- "$result" "$tmp"; then mv -fT -- "$tmp" "$cache/$key.logo"; else rm -f -- "$tmp"; fi
    lock_release "$cache/cache.lock"
}

logo_worker() {
    local url=$1 catalog=$2 cache=$3 job=$4 key modified favicon
    umask 077
    ulimit -f 4096 2>/dev/null || true
    key=$(printf '%s' "$url" | sha256sum); key=${key%% *}
    [[ "$key" =~ ^[0-9a-f]{64}$ ]] || return 1
    if [[ ! -L "$cache/$key.logo" ]] && logo_read_render "$cache/$key.logo"; then
        modified=$(stat -c %Y "$cache/$key.logo") || modified=0
        if ((EPOCHSECONDS >= modified && EPOCHSECONDS-modified < 604800)); then
            cp -- "$cache/$key.logo" "$job/result"; return $?
        fi
    fi
    [[ -f "$catalog" && ! -L "$catalog" ]] || return 1
    # La expresión jq debe permanecer entre comillas simples: $url es un
    # argumento de jq, no una expansión de Bash.
    # shellcheck disable=SC2016
    favicon=$(timeout --kill-after=1s 6s jq -r --arg url "$url" '
        first(.[] | select(.url_resolved == $url or .url == $url) |
            .favicon | select(type == "string" and length > 0 and length <= 2048)) // empty
    ' "$catalog") || return 1
    [[ -n "$favicon" ]] || return 1
    logo_fetch "$favicon" "$job" && logo_convert "$job" || return 1
    logo_cache_store "$cache" "$key" "$job/result"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -uo pipefail
    # shellcheck source=lib/lock.sh
    source "$(dirname "${BASH_SOURCE[0]}")/lock.sh"
    (($# == 4)) || exit 2
    logo_worker "$@"
fi
