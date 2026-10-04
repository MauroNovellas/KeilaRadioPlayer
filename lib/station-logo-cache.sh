#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Caché de emisoras visitadas: RGB validado, un SIXEL ligado a esos píxeles y
# plazos de reintento como datos. Ninguna consulta del catálogo al usar un hit.

logo_cache_key() {
    LOGO_CACHE_KEY=$(printf '%s' "$1" | sha256sum) || return 1
    LOGO_CACHE_KEY=${LOGO_CACHE_KEY%% *}
    [[ $LOGO_CACHE_KEY =~ ^[0-9a-f]{64}$ ]]
}

logo_cache_is_fresh() {
    local modified
    [[ -f $1 && ! -L $1 ]] || return 1
    modified=$(stat -c %Y -- "$1") || return 1
    [[ $modified =~ ^[0-9]{1,10}$ ]] || return 1
    ((EPOCHSECONDS >= modified && EPOCHSECONDS-modified < 86400))
}

logo_cache_read_check() {
    local file=$1 blob='' rest checked ttl reason LC_ALL=C
    LOGO_CACHE_REASON=''
    [[ -f $file && ! -L $file ]] || return 1
    IFS= read -r -N 256 blob < "$file" || true
    ((${#blob} < 256)) && [[ ${blob%%$'\n'*} == keila-logo-check-v1 ]] || return 1
    rest=${blob#*$'\n'} checked=${rest%%$'\n'*}
    rest=${rest#*$'\n'} ttl=${rest%%$'\n'*} reason=${rest#*$'\n'} reason=${reason%$'\n'}
    [[ $checked =~ ^(0|[1-9][0-9]{0,9})$ && $ttl =~ ^(3600|86400)$ ]] || return 1
    case $reason in
        'Comprobación pendiente'|'No se pudo consultar el catálogo'|'No hay candidato seguro en el catálogo'|\
        'No se pudo descargar el logo'|'Imagen no válida'|'Formato no admitido (SVG/HTML u otro)') ;;
        *) return 1 ;;
    esac
    ((EPOCHSECONDS >= checked && EPOCHSECONDS-checked < ttl)) || return 1
    LOGO_CACHE_REASON=$reason
}

logo_cache_read_sixel() {
    local file=$1 side=$2 blob='' rest pixels LC_ALL=C
    [[ -f $file && ! -L $file ]] || return 1
    IFS= read -r -N 300000 blob < "$file" || true
    ((${#blob} < 300000)) && [[ ${blob%%$'\n'*} == keila-logo-frame-v1 ]] || return 1
    rest=${blob#*$'\n'} pixels=${rest%%$'\n'*} rest=${rest#*$'\n'}
    # Vinculación exacta: una publicación concurrente/incompleta nunca puede
    # presentar el SIXEL anterior como si perteneciera a una imagen nueva.
    [[ $pixels == "$LOGO_PIXELS_BASE64" && ${#pixels} == 36864 ]] || return 1
    logo_decode_sixel "$rest" "$side"
}

# Solo lo llama un escritor bajo cache.lock. Contar una emisora una vez, también
# cuando no tiene logo, y retirar sus auxiliares juntos. No tocar archivos ajenos.
logo_cache_prune() {
    local cache=$1 incoming=$2 path name key modified record oldest='' oldest_time count=0
    local -A times=()
    local -a paths=()
    for path in "$cache"/*.logo "$cache"/*.check; do
        name=${path##*/} key=${name%.*}
        [[ $key =~ ^[0-9a-f]{64}$ && -f $path && ! -L $path ]] || continue
        if [[ -z ${times[$key]+yes} ]]; then times[$key]=0; count=$((count+1)); fi
        paths+=("$path")
    done
    # La escritura habitual no necesita fechas ni procesos externos. Solo
    # ordenar si de verdad excedemos el límite; una consulta recoge todas las
    # fechas. NUL permite rutas XDG con espacios o saltos de línea.
    ((count > 64)) || return 0
    while IFS= read -r -d '' record; do
        name=${record##*/} key=${name%.*} modified=${record%% *}
        [[ $key =~ ^[0-9a-f]{64}$ && -n ${times[$key]+yes} && $modified =~ ^-?[0-9]{1,10}$ ]] || continue
        ((${times[$key]:-0} >= modified)) || times[$key]=$modified
    done < <(stat --printf '%Y %n\0' -- "${paths[@]}" 2>/dev/null)
    while ((count > 64)); do
        oldest='' oldest_time=9223372036854775807
        for key in "${!times[@]}"; do
            [[ $key != "$incoming" ]] || continue
            if ((${times[$key]} < oldest_time)); then oldest=$key oldest_time=${times[$key]}; fi
        done
        [[ $oldest =~ ^[0-9a-f]{64}$ ]] || break
        rm -f -- "$cache/$oldest.logo" "$cache/$oldest.sixel" "$cache/$oldest.check"
        unset 'times[$oldest]'
        count=$((count-1))
    done
}

logo_cache_check_store() {
    local cache=$1 key=$2 reason=$3 ttl=${4:-3600} tmp
    [[ $key =~ ^[0-9a-f]{64}$ && -d $cache && ! -L $cache ]] || return 1
    # Estas funciones publican solo datos privados; no esperar a otra sesión.
    # lock_acquire consume la variable mediante alcance dinámico.
    # shellcheck disable=SC2034
    local KEILA_LOCK_ATTEMPTS=1
    lock_acquire "$cache/cache.lock" || return 0
    tmp=$(umask 077; mktemp "$cache/.check.XXXXXX") || { lock_release "$cache/cache.lock"; return 1; }
    if printf 'keila-logo-check-v1\n%s\n%s\n%s\n' "$EPOCHSECONDS" "$ttl" "$reason" > "$tmp"; then
        mv -fT -- "$tmp" "$cache/$key.check" || rm -f -- "$tmp"
        logo_cache_prune "$cache" "$key"
    else rm -f -- "$tmp"; fi
    lock_release "$cache/cache.lock"
}

logo_cache_store() {
    local cache=$1 key=$2 result=$3 sixel=${4:-} publish_rgb=${5:-1} tmp
    [[ $key =~ ^[0-9a-f]{64}$ && -d $cache && ! -L $cache ]] || return 1
    logo_read_render "$result" || return 1
    # shellcheck disable=SC2034
    local KEILA_LOCK_ATTEMPTS=1
    lock_acquire "$cache/cache.lock" || return 0
    if ((publish_rgb)); then
        tmp=$(umask 077; mktemp "$cache/.logo.XXXXXX") || { lock_release "$cache/cache.lock"; return 1; }
        if logo_write_render "$tmp"; then
            if mv -fT -- "$tmp" "$cache/$key.logo"; then rm -f -- "$cache/$key.check"
            else rm -f -- "$tmp"; fi
        else rm -f -- "$tmp"; fi
    fi
    # Un cambio de geometría no renueva la edad del RGB ni provoca descargas.
    if [[ -f $cache/$key.logo && ! -L $cache/$key.logo && -n $sixel ]] && logo_read_sixel "$sixel"; then
        tmp=$(umask 077; mktemp "$cache/.sixel.XXXXXX") || { lock_release "$cache/cache.lock"; return 1; }
        if { printf 'keila-logo-frame-v1\n%s\n' "$LOGO_PIXELS_BASE64"; cat -- "$sixel"; } > "$tmp"; then
            mv -fT -- "$tmp" "$cache/$key.sixel" || rm -f -- "$tmp"
        else rm -f -- "$tmp"; fi
    fi
    logo_cache_prune "$cache" "$key"
    lock_release "$cache/cache.lock"
}
