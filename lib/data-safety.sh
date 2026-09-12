#!/usr/bin/env bash
# Formatos conocidos; nunca ejecutar contenido de archivos personales.
data_validate() {
    local file=$1 kind=$2 line key value nul count=0
    case "$kind" in favorites|labels|history|equalizer|config|state|preferences) ;; *) return 1 ;; esac
    [[ -f "$file" && -r "$file" && ! -L "$file" ]] || return 1
    # Bash descarta NUL al leer líneas: detectarlo antes de validar el formato.
    if IFS= read -r -d '' nul < "$file"; then return 1; fi
    local -A seen=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$kind" in
            favorites|labels|history)
                [[ -z "$line" ]] && continue
                [[ "$line" == *'|'* && "$line" != *[[:cntrl:]]* ]] || return 1
                key=${line%%|*} value=${line#*|}
                [[ -n "$key" && "$value" != *'|'* ]] || return 1
                [[ "$kind" == labels || -n "$value" ]] || return 1
                ;;
            equalizer)
                # Cinco valores canónicos: sin octales, expresiones ni filas extra.
                [[ "$line" =~ ^(-?(0|[1-9]|1[0-2]),){4}-?(0|[1-9]|1[0-2])$ ]] || return 1
                ;;
            config)
                # Compatibilidad con el editor manual: comentarios, CRLF, tabs,
                # claves futuras y valores inválidos (el parser usa el defecto).
                line=${line%$'\r'}
                [[ "${line//$'\t'/}" != *[[:cntrl:]]* ]] || return 1
                # Recortar solo el margen, no espacios dentro de una ruta.
                line=${line#"${line%%[![:space:]]*}"}
                [[ -z "$line" || "$line" == \#* ]] && continue
                [[ "$line" == *=* ]] || return 1
                key=${line%%=*}
                key=${key%"${key##*[![:space:]]}"}
                [[ "$key" =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]] || return 1
                ;;
            state)
                [[ "$line" == *$'\t'* ]] || return 1
                key=${line%%$'\t'*} value=${line#*$'\t'}
                [[ -n "$key" && "$value" != *[[:cntrl:]]* ]] || return 1
                [[ -z "${seen[$key]:-}" ]] || return 1
                case "$key" in
                    volume) [[ "$value" =~ ^(100|[0-9]{1,2})$ ]] || return 1 ;;
                    last_name|last_url) : ;;
                    *) return 1 ;;
                esac
                seen[$key]=1
                ;;
            preferences)
                [[ "$line" == *=* ]] || return 1
                key=${line%%=*} value=${line#*=}
                [[ -n "$key" && -z "${seen[$key]:-}" ]] || return 1
                case "$key" in
                    autoplay|color|unicode|spectrum) [[ "$value" == [01] ]] || return 1 ;;
                    key_[bfrcxgpmlzvhoq]) [[ "$value" == [bcefghilmnopqrtuvxyz] ]] || return 1 ;;
                    *) return 1 ;;
                esac
                seen[$key]=1
                ;;
            *) return 1 ;;
        esac
        ((count+=1))
    done < "$file"
    case "$kind" in
        state) ((count == 3)) ;;
        equalizer) ((count == 1)) ;;
        preferences) ((count > 0)) ;;
        *) return 0 ;;
    esac
}

# El llamante mantiene el bloqueo del destino. Copiar y publicar cada copia
# por rename: nunca truncar el respaldo que podría necesitar otra sesión.
data_copy_atomic() {
    local source=$1 destination=$2 tmp status=0
    [[ ! -L "$destination" && ( ! -e "$destination" || -f "$destination" ) ]] || return 1
    tmp=$(mktemp "$destination.tmp.${BASHPID:-$$}.XXXXXX") || return 1
    cp -- "$source" "$tmp" && chmod 600 "$tmp" && mv -fT -- "$tmp" "$destination" || status=1
    if ((status)); then rm -f -- "$tmp"; fi
    return "$status"
}

data_publish() {
    local tmp=$1 file=$2 kind=$3
    data_validate "$tmp" "$kind" || return 1
    if [[ -e "$file" || -L "$file" ]]; then
        # Una corrupción aparecida durante la sesión no se normaliza guardando.
        data_validate "$file" "$kind" || return 1
        if cmp -s -- "$tmp" "$file" && data_validate "$file.bak" "$kind"; then
            rm -f -- "$tmp"
            return
        fi
        data_copy_atomic "$file" "$file.bak" || return 1
    else
        data_copy_atomic "$tmp" "$file.bak" || return 1
    fi
    mv -fT -- "$tmp" "$file"
}

data_recover() {
    local file=$1 kind=$2 status=0 archive=''
    lock_acquire "$file.lock" || return 1
    if [[ ! -e "$file" && ! -L "$file" && ! -e "$file.bak" && ! -L "$file.bak" ]]; then
        lock_release "$file.lock"
        return
    fi
    if data_validate "$file" "$kind"; then
        # Migración sin reescribir datos: la primera carga protegida crea copia.
        if [[ ! -e "$file.bak" && ! -L "$file.bak" ]]; then
            data_copy_atomic "$file" "$file.bak" || status=1
        fi
        lock_release "$file.lock" || status=1
        return "$status"
    fi
    if ! data_validate "$file.bak" "$kind"; then
        printf 'Datos dañados o incompatibles: %s. Sin copia válida; no se modifican.\n' "$file" >&2
        lock_release "$file.lock" || true
        return 1
    fi
    if [[ -L "$file" || ( -e "$file" && ! -f "$file" ) ]]; then
        printf 'Ruta no regular: %s. No se restaura automáticamente.\n' "$file" >&2
        lock_release "$file.lock" || true
        return 1
    fi
    if [[ -f "$file" ]]; then
        archive=$(mktemp "$file.corrupt.XXXXXX") || status=1
        if ((status == 0)); then cp -- "$file" "$archive" && chmod 600 "$archive" || status=1; fi
    fi
    if ((status == 0)); then data_copy_atomic "$file.bak" "$file" || status=1; fi
    if ((status == 0)); then
        printf 'Recuperado %s desde su copia. Archivo anterior: %s\n' "$file" "${archive:-no existía}" >&2
        DATA_RECOVERY_NOTICE='Datos recuperados desde copia anterior; revisa favoritos, recientes y ajustes.'
    fi
    lock_release "$file.lock" || status=1
    return "$status"
}
