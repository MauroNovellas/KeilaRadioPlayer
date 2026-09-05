#!/usr/bin/env bash

# Comprobación de actualizaciones integrada en la TUI.
#
# La consulta de GitHub se ejecuta en segundo plano para que el arranque de
# Keila nunca dependa de la red. La UI solo muestra algo cuando existe una
# versión nueva; un fallo de red permanece silencioso.

UI_UPDATE_CHECK_STATE='idle'
UI_UPDATE_AVAILABLE_VERSION=''
UI_UPDATE_CHECK_PID=''
UI_UPDATE_CHECK_DIR=''
UI_UPDATE_CHECK_RESULT=''
UI_UPDATE_DESKTOP_ROW=0

ui_update_background_cleanup() {
    if [[ -n "${UI_UPDATE_CHECK_PID:-}" ]]; then
        if kill -0 "$UI_UPDATE_CHECK_PID" 2>/dev/null; then
            kill "$UI_UPDATE_CHECK_PID" 2>/dev/null || true
        fi
        wait "$UI_UPDATE_CHECK_PID" 2>/dev/null || true
    fi

    if [[ -n "${UI_UPDATE_CHECK_DIR:-}" && -d "$UI_UPDATE_CHECK_DIR" ]]; then
        rm -rf -- "${UI_UPDATE_CHECK_DIR:?}"
    fi

    UI_UPDATE_CHECK_PID=''
    UI_UPDATE_CHECK_DIR=''
    UI_UPDATE_CHECK_RESULT=''
}

ui_update_background_start() {
    [[ "$UI_UPDATE_CHECK_STATE" == 'idle' ]] || return 1

    if [[ "${KEILA_NO_UPDATE_CHECK:-0}" == '1' ]]; then
        UI_UPDATE_CHECK_STATE='disabled'
        return 1
    fi

    # update_latest_version pertenece a lib/update.sh y ya está cargado por el
    # launcher antes de la UI. Si alguien usa este módulo aisladamente, no
    # iniciamos ningún proceso.
    declare -F update_latest_version >/dev/null 2>&1 || {
        UI_UPDATE_CHECK_STATE='unavailable'
        return 1
    }

    local runtime current
    runtime="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
    if [[ ! -d "$runtime" || ! -w "$runtime" ]]; then
        runtime="${TMPDIR:-/tmp}"
    fi

    UI_UPDATE_CHECK_DIR=$(mktemp -d "$runtime/keila-update-check.XXXXXX") || {
        UI_UPDATE_CHECK_STATE='error'
        return 1
    }
    UI_UPDATE_CHECK_RESULT="$UI_UPDATE_CHECK_DIR/result"
    current="${KEILA_VERSION:-dev}"
    UI_UPDATE_CHECK_STATE='checking'

    (
        local latest cmp state result_tmp
        result_tmp="$UI_UPDATE_CHECK_RESULT.tmp"

        if ! latest=$(update_latest_version "$current" 2>/dev/null); then
            printf 'error\t\n' > "$result_tmp"
            mv -- "$result_tmp" "$UI_UPDATE_CHECK_RESULT"
            exit 0
        fi

        if ! cmp=$(update_compare_versions "$latest" "$current" 2>/dev/null); then
            printf 'error\t\n' > "$result_tmp"
            mv -- "$result_tmp" "$UI_UPDATE_CHECK_RESULT"
            exit 0
        fi

        case "$cmp" in
            1) state='available' ;;
            0) state='current' ;;
            -1) state='newer' ;;
            *) state='error' ;;
        esac

        printf '%s\t%s\n' "$state" "$latest" > "$result_tmp"
        mv -- "$result_tmp" "$UI_UPDATE_CHECK_RESULT"
    ) &
    UI_UPDATE_CHECK_PID=$!
}

# Devuelve 0 únicamente cuando el estado acaba de cambiar y conviene redibujar.
ui_update_background_poll() {
    [[ "$UI_UPDATE_CHECK_STATE" == 'checking' ]] || return 1

    if [[ ! -f "$UI_UPDATE_CHECK_RESULT" ]]; then
        if [[ -n "$UI_UPDATE_CHECK_PID" ]] && ! kill -0 "$UI_UPDATE_CHECK_PID" 2>/dev/null; then
            wait "$UI_UPDATE_CHECK_PID" 2>/dev/null || true
            UI_UPDATE_CHECK_PID=''
            UI_UPDATE_CHECK_STATE='error'
            if [[ -n "$UI_UPDATE_CHECK_DIR" && -d "$UI_UPDATE_CHECK_DIR" ]]; then
                rm -rf -- "${UI_UPDATE_CHECK_DIR:?}"
            fi
            UI_UPDATE_CHECK_DIR=''
            UI_UPDATE_CHECK_RESULT=''
            return 0
        fi
        return 1
    fi

    local state version
    IFS=$'\t' read -r state version < "$UI_UPDATE_CHECK_RESULT" || state='error'

    case "$state" in
        available)
            UI_UPDATE_CHECK_STATE='available'
            UI_UPDATE_AVAILABLE_VERSION="$version"
            ;;
        current|newer)
            UI_UPDATE_CHECK_STATE="$state"
            UI_UPDATE_AVAILABLE_VERSION=''
            ;;
        *)
            UI_UPDATE_CHECK_STATE='error'
            UI_UPDATE_AVAILABLE_VERSION=''
            ;;
    esac

    if [[ -n "$UI_UPDATE_CHECK_PID" ]]; then
        wait "$UI_UPDATE_CHECK_PID" 2>/dev/null || true
    fi
    UI_UPDATE_CHECK_PID=''

    if [[ -n "$UI_UPDATE_CHECK_DIR" && -d "$UI_UPDATE_CHECK_DIR" ]]; then
        rm -rf -- "${UI_UPDATE_CHECK_DIR:?}"
    fi
    UI_UPDATE_CHECK_DIR=''
    UI_UPDATE_CHECK_RESULT=''
    return 0
}

# Conservamos los helpers visuales originales y añadimos únicamente los hooks
# necesarios para iniciar/pollear/cancelar la consulta de actualización.
if ! declare -F ui_enter_without_update_check >/dev/null 2>&1; then
    UI_UPDATE_DEF=$(declare -f ui_enter)
    UI_UPDATE_DEF=${UI_UPDATE_DEF/ui_enter ()/ui_enter_without_update_check ()}
    eval "$UI_UPDATE_DEF"

    UI_UPDATE_DEF=$(declare -f ui_leave)
    UI_UPDATE_DEF=${UI_UPDATE_DEF/ui_leave ()/ui_leave_without_update_check ()}
    eval "$UI_UPDATE_DEF"

    UI_UPDATE_DEF=$(declare -f ui_message_tick)
    UI_UPDATE_DEF=${UI_UPDATE_DEF/ui_message_tick ()/ui_message_tick_without_update_check ()}
    eval "$UI_UPDATE_DEF"

    UI_UPDATE_DEF=$(declare -f ui_desktop_header_rule)
    UI_UPDATE_DEF=${UI_UPDATE_DEF/ui_desktop_header_rule ()/ui_desktop_header_rule_without_update_check ()}
    eval "$UI_UPDATE_DEF"

    UI_UPDATE_DEF=$(declare -f ui_desktop_row)
    UI_UPDATE_DEF=${UI_UPDATE_DEF/ui_desktop_row ()/ui_desktop_row_without_update_check ()}
    eval "$UI_UPDATE_DEF"
    unset UI_UPDATE_DEF
fi

ui_enter() {
    ui_enter_without_update_check || return $?
    ui_update_background_start >/dev/null 2>&1 || true
}

ui_leave() {
    ui_update_background_cleanup
    ui_leave_without_update_check
}

ui_message_tick() {
    local changed=1

    if ui_message_tick_without_update_check; then
        changed=0
    fi
    if ui_update_background_poll; then
        changed=0
    fi

    return "$changed"
}

ui_desktop_header_rule() {
    UI_UPDATE_DESKTOP_ROW=0
    ui_desktop_header_rule_without_update_check "$@"
}

ui_desktop_row() {
    local left_text="${1:-}"
    local left_badge="${2:-}"
    local left_style="${3:-}"
    local left_badge_style="${4:-}"
    local right_text="${5:-}"
    local right_badge="${6:-}"
    local right_style="${7:-}"
    local right_badge_style="${8:-}"
    local selected="${9:-0}"
    local row=$UI_UPDATE_DESKTOP_ROW

    UI_UPDATE_DESKTOP_ROW=$((UI_UPDATE_DESKTOP_ROW + 1))

    # La última fila útil del desktop mínimo (20 líneas) queda reservada para
    # un aviso discreto. Si la ayuda reduce el cuerpo, simplemente no aparece.
    if ((row == 12)) && [[ "$UI_UPDATE_CHECK_STATE" == 'available' && -n "$UI_UPDATE_AVAILABLE_VERSION" ]]; then
        left_text='ACTUALIZACIÓN'
        left_badge="$UI_UPDATE_AVAILABLE_VERSION disponible"
        left_style='warning'
        left_badge_style='warning'
    fi

    ui_desktop_row_without_update_check \
        "$left_text" "$left_badge" "$left_style" "$left_badge_style" \
        "$right_text" "$right_badge" "$right_style" "$right_badge_style" "$selected"
}
