#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Datos de imagen normalizados; nunca guardar ni ejecutar escapes del servidor.
# shellcheck source=lib/station-logo-cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/station-logo-cache.sh"

logo_read_render() {
    local file=$1 blob='' header rest pixels hex LC_ALL=C
    [[ -f "$file" && ! -L "$file" ]] || return 1
    IFS= read -r -N 40000 blob < "$file" || true
    ((${#blob} < 40000)) || return 1
    header=${blob%%$'\n'*} rest=${blob#*$'\n'}
    [[ "$header" == keila-logo-v1 ]] || return 1
    pixels=${rest%%$'\n'*} rest=${rest#*$'\n'} hex=${rest%$'\n'}
    [[ ${#pixels} == 36864 && "$pixels" != *[!a-zA-Z0-9+/]* &&
        ${#hex} == 864 && "$hex" != *[!0-9a-f]* ]] || return 1
    LOGO_PIXELS_BASE64=$pixels LOGO_PIXELS_HEX=$hex
}

logo_write_render() {
    printf 'keila-logo-v1\n%s\n%s\n' "$LOGO_PIXELS_BASE64" "$LOGO_PIXELS_HEX" > "$1"
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
    LOGO_FETCH_URL=''
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
        if [[ "$code" == 200 ]]; then LOGO_FETCH_URL=$url; return 0; fi
        [[ "$code" == 30[12378] && -n "$redirect" && "$redirect" != "$response" ]] || return 1
        url=$redirect
    done
    return 1
}

logo_convert() {
    local job=$1 magic size entries
    local -a decoder=()
    LOGO_FAILURE_REASON='Imagen no válida'
    [[ -f "$job/image" && ! -L "$job/image" ]] || return 1
    size=$(stat -c %s "$job/image") || return 1
    ((size > 0 && size <= 1048576)) || return 1
    magic=$(od -An -tx1 -N12 "$job/image" | tr -d ' \n') || return 1
    case "$magic" in
        89504e470d0a1a0a*) decoder=(-f image2 -pattern_type none -c:v png) ;;
        ffd8ff*) decoder=(-f image2 -pattern_type none -c:v mjpeg) ;;
        52494646????????57454250) decoder=(-f image2 -pattern_type none -c:v webp) ;;
        474946383761*|474946383961*) decoder=(-f image2 -pattern_type none -c:v gif) ;;
        00000100*)
            ((size >= 22)) || return 1
            entries=$((16#${magic:10:2}*256+16#${magic:8:2}))
            ((entries > 0 && entries <= 32)) || return 1
            decoder=(-f ico -codec_whitelist 'bmp,png') ;;
        *) LOGO_FAILURE_REASON='Formato no admitido (SVG/HTML u otro)'; return 1 ;;
    esac
    # Forzar decodificador y protocolos: un favicon no puede abrir playlists,
    # SVG, archivos locales externos ni URLs secundarias. Solo el primer cuadro.
    timeout --kill-after=1s 6s ffmpeg -nostdin -y -v error -threads 1 -filter_threads 1 -protocol_whitelist file,pipe \
        "${decoder[@]}" -max_pixels 4194304 -i "$job/image" \
        -vf 'scale=96:96:force_original_aspect_ratio=decrease,pad=96:96:(ow-iw)/2:(oh-ih)/2:color=black,format=rgb24' \
        -frames:v 1 -threads 1 -f rawvideo "$job/rgb" || return 1
    [[ $(stat -c %s "$job/rgb") == 27648 ]] || return 1
    timeout --kill-after=1s 6s ffmpeg -nostdin -y -v error -threads 1 -filter_threads 1 -f rawvideo -pixel_format rgb24 \
        -video_size 96x96 -i "$job/rgb" -vf scale=12:12 -frames:v 1 -threads 1 -f rawvideo "$job/small" || return 1
    [[ $(stat -c %s "$job/small") == 432 ]] || return 1
    {
        printf 'keila-logo-v1\n'
        base64 -w0 "$job/rgb"; printf '\n'
        od -An -v -tx1 "$job/small" | tr -d ' \n'; printf '\n'
    } > "$job/result"
    logo_read_render "$job/result"
}

logo_read_sixel() {
    local file=$1 blob='' LC_ALL=C
    [[ -f "$file" && ! -L "$file" ]] || return 1
    IFS= read -r -N 262144 blob < "$file" || true
    ((${#blob} < 262144)) || return 1
    logo_decode_sixel "$blob" "${2:-}"
}

logo_decode_sixel() {
    local blob=$1 expected=${2:-} rest side body tail allowed='^[0-9;!#$"?-~-]+$' LC_ALL=C
    ((${#blob} < 262144)) || return 1
    [[ ${blob%%$'\n'*} == keila-sixel-v1 ]] || return 1
    rest=${blob#*$'\n'} side=${rest%%$'\n'*} body=${rest#*$'\n'} body=${body%$'\n'}
    [[ $side =~ ^[1-9][0-9]?$ ]] || return 1
    ((side >= 6 && side <= 96 && side % 6 == 0)) || return 1
    [[ -z $expected || $side == "$expected" ]] || return 1
    [[ $body == "\"1;1;$side;$side"* && $body =~ $allowed && ! $body =~ ![0-9]{3} && ! $body =~ \#[0-9]{4} ]] || return 1
    tail=${body#"\"1;1;$side;$side"}
    [[ $tail != *'"'* ]] || return 1
    LOGO_SIXEL_BODY=$body
}

logo_prepare_sixel() {
    local job=$1 side=$2 encoder
    [[ $side =~ ^[1-9][0-9]?$ ]] || return 1
    ((side >= 6 && side <= 96 && side % 6 == 0)) || return 1
    encoder="$(dirname "${BASH_SOURCE[0]}")/station-logo-sixel.awk"
    # La caché contiene solo RGB normalizado. No conservar escapes de red.
    printf '%s' "$LOGO_PIXELS_BASE64" | base64 -d > "$job/rgb" || return 1
    {
        printf 'keila-sixel-v1\n%s\n' "$side"
        od -An -v -tu1 "$job/rgb" | LC_ALL=C timeout --kill-after=1s 3s awk -v side="$side" -f "$encoder"
    } > "$job/sixel" || return 1
    logo_read_sixel "$job/sixel" "$side"
}

logo_catalog_candidates() {
    local url=$1 catalog=$2 name=${3:-}
    timeout --kill-after=1s 6s jq -r --arg url "$url" --arg name "$name" '
        def key: ascii_downcase | gsub("[áàäâ]";"a") | gsub("[éèëê]";"e") | gsub("[íìïî]";"i") |
            gsub("[óòöô]";"o") | gsub("[úùüû]";"u") | gsub("ñ";"n") | gsub("[^a-z0-9]";"");
        def identity:
            key | if . == "radio5rne" or . == "rneradio5" or . == "radionacionaldeespanaradio5todonoticias" or . == "radio5todonoticias" then "rne-radio5"
            elif . == "radionacional" or . == "rneradionacional" or . == "rneradionacionaldeespana" then "rne-nacional" else . end;
        def streamkey: sub("^https?://"; "") | sub("#.*$"; "");
        def site: (.homepage // "") | ascii_downcase | sub("^https?://(www\\.)?"; "") | split("/")[0];
        def distinct: reduce .[] as $v ([]; if index($v) == null then . + [$v] else . end);
        . as $all | ($name | identity) as $id |
        ($name | ascii_downcase | split(" ") | map(select(length>2 and .!="radio" and .!="rne")) | last // "") as $word |
        (if $id=="rne-radio5" then "5" elif $id=="rne-nacional" then "nacional" else $word[0:3] end) as $needle |
        [.[] | select(.url == $url or .url_resolved == $url)] as $exact |
        (if ($exact|length)>0 then $exact else
            [$all[] | select((.url // "" | streamkey) == ($url | streamkey) or (.url_resolved // "" | streamkey) == ($url | streamkey))] end) as $urls |
        (if $id == "" or $needle == "" then [] else [$all[] |
            select((.name // "" | ascii_downcase | contains($needle))) |
            select((.name // "" | identity) == $id)] end) as $named |
        (if ($named|length)>0 and ([$named[]|.countrycode // ""]|unique|length)==1 and
            ([$named[]|site|select(length>0)]|unique|length)==1 and all($named[]; (site|length)>0)
            then $named else [] end) as $safe_named |
        ($urls + $safe_named) as $records |
        ([$records[] | .favicon // "" | select(type=="string" and length>0 and length<=2048)] | distinct | .[0:4][] | "I\t"+.),
        ([$records[] | .homepage // "" | select(type=="string" and length>0 and length<=2048)] | distinct | .[0:2][] | "H\t"+.)
    ' "$catalog"
}

logo_homepage_icons() {
    # Analizar enlaces estáticos del head, no ejecutar HTML/JS ni seguir base.
    local size
    [[ -f $1 && ! -L $1 ]] || return 1
    size=$(stat -c %s "$1") || return 1
    ((size > 0 && size <= 1048576)) || return 1
    LC_ALL=C awk -f "$(dirname "${BASH_SOURCE[0]}")/station-logo-links.awk" "$1"
}

logo_try_image() {
    local url=$1 job=$2
    LOGO_FAILURE_REASON='No se pudo descargar el logo'
    logo_fetch "$url" "$job" && logo_convert "$job"
}

logo_worker_cached() {
    local cache=$1 key=$2 job=$3 side=$4
    logo_read_render "$job/cached" && logo_write_render "$job/result" || return 1
    if ((side > 0)); then
        if logo_cache_read_sixel "$cache/$key.sixel" "$side"; then
            printf 'keila-sixel-v1\n%s\n%s\n' "$side" "$LOGO_SIXEL_BODY" > "$job/sixel"
        elif logo_prepare_sixel "$job" "$side"; then
            logo_cache_store "$cache" "$key" "$job/result" "$job/sixel" 0 || true
        fi
    fi
    return 0
}

logo_worker() {
    local url=$1 catalog=$2 cache=$3 job=$4 name=${5:-} side=${6:-0} mode=${7:-normal} key candidates kind candidate homepage page_url href origin base ready=0 cached=0 ttl=3600
    local -a images=() pages=()
    umask 077
    ulimit -f 4096 2>/dev/null || true
    [[ -d $cache && ! -L $cache && $mode =~ ^(normal|render)$ ]] || return 1
    logo_cache_key "$url" || return 1
    key=$LOGO_CACHE_KEY
    if logo_read_render "$cache/$key.logo"; then
        cached=1
        logo_write_render "$job/cached" || return 1
        if [[ $mode == render ]] || logo_cache_is_fresh "$cache/$key.logo" || logo_cache_read_check "$cache/$key.check"; then
            logo_worker_cached "$cache" "$key" "$job" "$side" || return 1
            return 0
        fi
    fi
    [[ $mode != render ]] || return 1
    if logo_cache_read_check "$cache/$key.check"; then printf '%s\n' "$LOGO_CACHE_REASON" > "$job/status"; return 1; fi
    if [[ ! -f "$catalog" || -L "$catalog" ]]; then
        ((cached == 0)) || logo_worker_cached "$cache" "$key" "$job" "$side" || true
        return 1
    fi
    # Escribir el intento antes de la red también limita trabajos interrumpidos.
    logo_cache_check_store "$cache" "$key" 'Comprobación pendiente' || true
    if ! candidates=$(logo_catalog_candidates "$url" "$catalog" "$name"); then
        logo_cache_check_store "$cache" "$key" 'No se pudo consultar el catálogo' || true
        ((cached == 0)) || logo_worker_cached "$cache" "$key" "$job" "$side" || true
        return 1
    fi
    LOGO_FAILURE_REASON='No hay candidato seguro en el catálogo'
    while IFS=$'\t' read -r kind candidate; do
        [[ -n $candidate ]] || continue
        case $kind in I) images+=("$candidate") ;; H) pages+=("$candidate") ;; esac
    done <<< "$candidates"
    for candidate in "${images[@]}"; do
        if logo_try_image "$candidate" "$job"; then ready=1; break; fi
    done
    if ((!ready)); then
        for homepage in "${pages[@]}"; do
            LOGO_FETCH_URL=''
            logo_fetch "$homepage" "$job" || continue
            page_url=${LOGO_FETCH_URL:-$homepage}
            candidates=$(logo_homepage_icons "$job/image") || continue
            page_url=${page_url%%\#*} page_url=${page_url%%\?*}
            [[ $page_url =~ ^(https?://[^/]+) ]] || continue
            origin=${BASH_REMATCH[1]}
            base=$origin
            [[ $page_url == "$origin" ]] || base=${page_url%/*}
            while IFS= read -r href; do
                [[ -n $href ]] || continue
                case $href in
                    https://*|http://*) candidate=$href ;;
                    //*) candidate="${page_url%%:*}:$href" ;;
                    /*) candidate="$origin$href" ;;
                    *) candidate="$base/$href" ;;
                esac
                if logo_try_image "$candidate" "$job"; then ready=1; break; fi
            done <<< "$candidates"
            ((ready)) && break
        done
    fi
    if ((!ready)); then
        printf '%s\n' "$LOGO_FAILURE_REASON" > "$job/status"
        [[ $LOGO_FAILURE_REASON != 'No hay candidato seguro en el catálogo' ]] || ttl=86400
        logo_cache_check_store "$cache" "$key" "$LOGO_FAILURE_REASON" "$ttl" || true
        ((cached == 0)) || logo_worker_cached "$cache" "$key" "$job" "$side" || true
        return 1
    fi
    ((side == 0)) || logo_prepare_sixel "$job" "$side" || true
    logo_cache_store "$cache" "$key" "$job/result" "$job/sixel" || true
    return 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -uo pipefail
    # shellcheck source=lib/lock.sh
    source "$(dirname "${BASH_SOURCE[0]}")/lock.sh"
    (($# >= 4 && $# <= 7)) || exit 2
    logo_worker "$@"
fi
