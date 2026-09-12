#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Entrada única para desarrollo y CI. No instala dependencias ni inicia radio.
set -uo pipefail
CHECK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

check_manifest() {
    local dir=$1 group file argument extra path failed=0 identity
    local -A covered=() entries=()
    CHECK_ENTRIES=()
    [[ -r "$dir/suites.txt" ]] || { printf 'Falta suites.txt\n' >&2; return 1; }
    while IFS='|' read -r group file argument extra || [[ -n "$group" ]]; do
        [[ -z "$group" || "$group" == \#* ]] && continue
        case "$group" in fast|integration|performance|packaging|manual) ;; *)
            printf 'Grupo desconocido: %s\n' "$group" >&2; failed=1; continue ;; esac
        if [[ ! "$file" =~ ^[a-z0-9-]+\.(sh|py)$ || ! -f "$dir/$file" || -n "$extra" || "$file" == check.sh ]]; then
            printf 'Entrada no válida: %s|%s\n' "$group" "$file" >&2; failed=1; continue
        fi
        case "$argument" in ''|--self-test) ;; *)
            printf 'Argumento no permitido: %s\n' "$argument" >&2; failed=1; continue ;; esac
        identity="$file|$argument"
        if [[ -n "${entries[$identity]:-}" ]]; then
            printf 'Prueba duplicada: %s\n' "$identity" >&2; failed=1
        fi
        covered[$file]=1 entries[$identity]=1
        CHECK_ENTRIES+=("$group|$file|$argument")
    done < "$dir/suites.txt"
    for path in "$dir"/*.sh "$dir"/*.py; do
        [[ -f "$path" ]] || continue
        file=${path##*/}
        [[ "$file" == check.sh || -n "${covered[$file]:-}" ]] && continue
        printf 'Prueba sin clasificar: %s\n' "$file" >&2; failed=1
    done
    ((${#CHECK_ENTRIES[@]} > 0)) || failed=1
    return "$failed"
}

check_selected() {
    [[ "$1" == "$2" || ( "$1" == all && "$2" =~ ^(fast|integration|performance)$ ) ]]
}

check_main() {
    local suite=all list=0 arg entry group file argument tool missing=0
    for arg in "$@"; do
        case "$arg" in
            --list) list=1 ;;
            all|fast|integration|performance|packaging) suite=$arg ;;
            --help|-h)
                printf 'Uso: bash tests/check.sh [all|fast|integration|performance|packaging] [--list]\n'
                printf 'Sin argumentos: todas las pruebas offline, excepto empaquetado Debian.\n'
                printf '--list incluye también el inventario manual; no ejecuta pruebas.\n'
                return 0 ;;
            *) printf 'Opción desconocida: %s\n' "$arg" >&2; return 2 ;;
        esac
    done
    check_manifest "$CHECK_DIR" || return 1
    if ((list)); then
        for entry in "${CHECK_ENTRIES[@]}"; do
            IFS='|' read -r group file argument <<< "$entry"
            if check_selected "$suite" "$group" || [[ "$suite" == all ]]; then
                printf '%-12s %s %s\n' "$group" "$file" "$argument"
            fi
        done
        return 0
    fi
    # Los antiguos skips no deben producir un resultado verde incompleto.
    local -a dependencies=(bash timeout mktemp jq python3)
    if [[ "$suite" == all || "$suite" == fast ]]; then dependencies+=(shellcheck); fi
    if [[ "$suite" == all || "$suite" == integration ]]; then
        dependencies+=(ffmpeg ffprobe script setsid mpv socat)
    fi
    [[ "$suite" != packaging ]] || dependencies+=(dpkg-deb)
    for tool in "${dependencies[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || { printf 'Falta dependencia de pruebas: %s\n' "$tool" >&2; missing=1; }
    done
    ((missing == 0)) || return 2
    local timeout_seconds=${KEILA_TEST_TIMEOUT:-180}
    [[ "$timeout_seconds" =~ ^[1-9][0-9]{0,4}$ ]] || { printf 'KEILA_TEST_TIMEOUT no válido\n' >&2; return 2; }
    local workspace test_dir status passed=0 failed=0 start=$SECONDS
    workspace=$(mktemp -d "${TMPDIR:-/tmp}/keila-check.XXXXXX") || return 1
    printf 'Batería %s. Registros: %s\n' "$suite" "$workspace"
    for entry in "${CHECK_ENTRIES[@]}"; do
        IFS='|' read -r group file argument <<< "$entry"
        check_selected "$suite" "$group" || continue
        test_dir="$workspace/${file%.*}"
        mkdir -p "$test_dir/tmp" || return 1
        local -a command=(bash "$CHECK_DIR/$file")
        [[ "$file" != *.py ]] || command=(python3 "$CHECK_DIR/$file")
        [[ -z "$argument" ]] || command+=("$argument")
        printf '  %-12s %-34s ' "$group" "$file"
        status=0
        # Un perfil y temporales distintos por prueba, incluso para módulos que
        # se limitan a cargar el launcher. No cambiar HOME ni usar datos reales.
        XDG_CONFIG_HOME="$test_dir/config" XDG_STATE_HOME="$test_dir/state" \
        XDG_CACHE_HOME="$test_dir/cache" TMPDIR="$test_dir/tmp" TERM=xterm-256color \
            timeout --kill-after=5s "${timeout_seconds}s" "${command[@]}" > "$test_dir/output.log" 2>&1 || status=$?
        if ((status == 0)); then
            printf 'OK\n'; ((passed+=1))
        else
            printf 'FALLO (%s)\n' "$status"; ((failed+=1))
            cat -- "$test_dir/output.log"
        fi
    done
    printf '\nResultado: %d correctas; %d fallidas; %d segundos.\nRegistros: %s\n' "$passed" "$failed" "$((SECONDS-start))" "$workspace"
    ((passed + failed > 0 && failed == 0))
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then check_main "$@"; fi
