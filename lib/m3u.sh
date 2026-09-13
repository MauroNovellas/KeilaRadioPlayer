#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Intercambio acotado, sin ejecutar etiquetas ni descargar direcciones.
M3U_ERROR='' M3U_ADDED=0 M3U_DUPLICATES=0 M3U_REJECTED=0

m3u_prepare() {
    local mode=$1 source=$2 directory=$3 line name='' url nul size count=0
    local -A seen=()
    M3U_ERROR='' M3U_DUPLICATES=0 M3U_REJECTED=0
    [[ -f "$source" && -r "$source" && ! -L "$source" ]] || { M3U_ERROR='Elige un archivo local regular y legible, no un enlace.'; return 1; }
    # O_NOFOLLOW/O_NONBLOCK y límite de lectura también si cambia tras stat.
    dd if="$source" of="$directory/snapshot" iflag=nofollow,nonblock,count_bytes count=262145 status=none 2>/dev/null || {
        M3U_ERROR='No se pudo leer el archivo.'; return 1;
    }
    size=$(stat -c %s -- "$directory/snapshot") || return 1
    ((size <= 262144)) || { M3U_ERROR='Lista demasiado grande: máximo 256 KiB y 2000 emisoras.'; return 1; }
    if IFS= read -r -d '' nul < "$directory/snapshot"; then M3U_ERROR='El archivo contiene datos binarios (NUL).'; return 1; fi
    [[ "$mode" == import || "$mode" == export ]] || return 1
    if [[ "$mode" == export ]] && ! data_validate "$directory/snapshot" favorites; then
        M3U_ERROR='Favoritas no tiene un formato válido. No se modifica ningún dato.'; return 1
    fi
    : > "$directory/rows" || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line#$'\xef\xbb\xbf'} line=${line%$'\r'}
        if [[ "$mode" == import ]]; then
            line=${line#"${line%%[![:space:]]*}"}
            line=${line%"${line##*[![:space:]]}"}
            case "$line" in
                '#EXT-X-'*) M3U_ERROR='Es una lista de segmentos HLS, no una lista de emisoras.'; return 1 ;;
                '#EXTINF:'*)
                    if [[ "$line" == *,* ]]; then name=${line#*,}; else name=''; fi
                    continue ;;
                ''|'#'*) continue ;;
            esac
            url=$line
            if [[ -z "$name" ]]; then name=${url#*://}; name=${name%%[/?#]*}; fi
        else
            name=${line%%|*} url=${line#*|}
            [[ -n "$line" ]] || continue
        fi
        if ! station_manual_valid "$name" "$url"; then
            ((M3U_REJECTED+=1)); name=''; continue
        fi
        if [[ -n "${seen[$url]:-}" ]]; then
            ((M3U_DUPLICATES+=1)); name=''; continue
        fi
        seen[$url]=1
        ((count+=1))
        ((count <= 2000)) || { M3U_ERROR='Demasiadas emisoras: máximo 2000 por intercambio.'; return 1; }
        printf '%s|%s\n' "$name" "$url" >> "$directory/rows" || return 1
        name=''
    done < "$directory/snapshot"
    ((count > 0)) || { M3U_ERROR='No hay emisoras HTTP/HTTPS válidas para intercambiar.'; return 1; }
    printf '%s %s %s\n' "$count" "$M3U_DUPLICATES" "$M3U_REJECTED" > "$directory/counts"
}

m3u_import_commit() {
    local rows=$1 lock_dir="${KEILA_FAVORITES_FILE}.lock" name url status=0 count=0
    local -a previous_names=() previous_urls=()
    local -A seen=()
    M3U_ERROR='' M3U_ADDED=0 M3U_DUPLICATES=0
    ((${BACKUP_DATA_BUSY:-0} == 0)) || { M3U_ERROR='Espera a que termine la restauración de datos.'; return 1; }
    data_validate "$rows" favorites || { M3U_ERROR='La vista previa ya no es válida.'; return 1; }
    lock_acquire "$lock_dir" || { M3U_ERROR='Favoritas está ocupada. Puedes reintentar.'; return 1; }
    if ! data_validate "$KEILA_FAVORITES_FILE" favorites; then
        lock_release "$lock_dir" || true
        M3U_ERROR='Favoritas no es válida; no se ha modificado.'; return 1
    fi
    favorites_load
    previous_names=("${FAVORITE_NAMES[@]}") previous_urls=("${FAVORITE_URLS[@]}")
    for url in "${FAVORITE_URLS[@]}"; do seen[$url]=1; done
    while IFS='|' read -r name url || [[ -n "$name" ]]; do
        [[ -n "$name" ]] || continue
        ((count+=1))
        if ((count > 2000)) || ! station_manual_valid "$name" "$url"; then status=1; break; fi
        if [[ -n "${seen[$url]:-}" ]]; then ((M3U_DUPLICATES+=1)); continue; fi
        seen[$url]=1
        FAVORITE_NAMES+=("$name") FAVORITE_URLS+=("$url")
        ((M3U_ADDED+=1))
    done < "$rows"
    # Una sola publicación con bloqueo y copia .bak, nunca una por emisora.
    if ((status == 0 && M3U_ADDED > 0)); then favorites_save_unlocked || status=1; fi
    if ((status)); then
        FAVORITE_NAMES=("${previous_names[@]}") FAVORITE_URLS=("${previous_urls[@]}")
        M3U_ADDED=0 M3U_ERROR='No se pudo guardar. Se conservan tus favoritas anteriores.'
    fi
    lock_release "$lock_dir" || { status=1; M3U_ERROR='Importación terminada, pero no se pudo liberar su bloqueo. Revisa Favoritas.'; }
    return "$status"
}

m3u_export_commit() {
    local rows=$1 target=$2 tmp name url status=0
    M3U_ERROR=''
    [[ ! -e "$target" && ! -L "$target" ]] || { M3U_ERROR='El destino ya existe. Elige otro nombre: nunca se sobrescribe.'; return 1; }
    data_validate "$rows" favorites || { M3U_ERROR='Vista previa no válida.'; return 1; }
    tmp=$(mktemp "$target.tmp.XXXXXX") || { M3U_ERROR='No se puede crear el archivo en esa carpeta.'; return 1; }
    {
        printf '#EXTM3U\n' || status=1
        while IFS='|' read -r name url || [[ -n "$name" ]]; do
            if ! station_manual_valid "$name" "$url"; then status=1; break; fi
            printf '#EXTINF:-1,%s\n%s\n' "$name" "$url" || { status=1; break; }
        done < "$rows"
    } > "$tmp" || status=1
    # Temporal hermano: rename en el mismo filesystem; -n no sustituye ni
    # enlaces ni archivos aparecidos desde la vista previa. Comprobar si movió.
    if ((status == 0)); then
        mv -nT -- "$tmp" "$target" || status=1
        [[ ! -e "$tmp" ]] || status=1
    fi
    if ((status)); then
        rm -f -- "$tmp"
        M3U_ERROR='No se pudo publicar: destino ocupado o error de escritura. No se sobrescribe nada.'
    fi
    return "$status"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    umask 077
    m3u_base=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    source "$m3u_base/station-options.sh"
    source "$m3u_base/data-safety.sh"
    m3u_status=0
    m3u_prepare "$1" "$2" "$3" || m3u_status=1
    printf '%s\n' "${M3U_ERROR:-No se pudo preparar la lista.}" > "$3/notice"
    printf '%s\n' "$m3u_status" > "$3/status.tmp"
    mv -T -- "$3/status.tmp" "$3/status"
    exit "$m3u_status"
fi
