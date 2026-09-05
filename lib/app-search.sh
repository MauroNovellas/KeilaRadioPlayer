#!/usr/bin/env bash

# Integración modal de la búsqueda. Se carga después de stations.sh y de las
# capas visuales, y sustituye solo el selector de emisoras. El launcher sigue
# usando su mismo app_search_catalog() y su mismo bucle principal.

# shellcheck source=lib/search.sh
source "$(dirname "${BASH_SOURCE[0]}")/search.sh"
# shellcheck source=lib/ui-search.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui-search.sh"

stations_select_fzf_external() {
    stations_require_search_dependencies || return 1
    stations_ensure_catalog || return 1

    local selection
    selection=$(
        stations_emit_tsv |
            fzf \
                --delimiter=$'\t' \
                --with-nth=1,2,3,4 \
                --prompt='Buscar emisora > ' \
                --header='Nombre | Ámbito | País | Formato' \
                --layout=reverse \
                --border
    ) || return $?

    [[ -n "$selection" ]] || return 1

    IFS=$'\t' read -r \
        SELECTED_NAME \
        SELECTED_AMBIT \
        SELECTED_COUNTRY \
        SELECTED_FORMAT \
        SELECTED_URL <<< "$selection"

    [[ -n "${SELECTED_NAME:-}" && -n "${SELECTED_URL:-}" ]]
}

search_handle_key() {
    local key="$1"
    case "$key" in
        $'\x7f'|$'\x08') search_backspace || true ;;
        $'\x15') search_clear || true ;;
        *) search_append "$key" || return 1 ;;
    esac
    return 0
}

search_prepare_results() {
    search_apply_pending_filter || true
}

stations_select_fzf() {
    if [[ "${KEILA_FZF_SEARCH:-0}" == '1' ]]; then
        stations_select_fzf_external
        return $?
    fi

    # app_search_catalog() ya suspendió la TUI antes de llamarnos. Aprovechamos
    # ese estado para descargar el catálogo solo si aún no existe una copia útil.
    if ! stations_catalog_valid; then
        stations_ensure_catalog || return 1
    fi

    if ! search_open; then
        return 1
    fi

    UI_HELP_VISIBLE=0
    ui_clear_message
    ui_resume
    ui_draw_search

    while true; do
        if ! input_read; then
            search_close
            return 1
        fi

        local redraw=0
        case "$INPUT_EVENT" in
            TICK)
                # El teclado se pinta inmediatamente. El filtro pesado se aplica
                # después de una breve pausa natural de input (timeout/TICK).
                if search_apply_pending_filter; then
                    redraw=1
                fi
                app_poll_player && redraw=1
                ui_message_tick && redraw=1
                ;;
            RESIZE)
                redraw=1
                ;;
            ESC)
                search_close
                return 1
                ;;
            UP)
                search_prepare_results
                search_move -1 || true
                redraw=1
                ;;
            DOWN)
                search_prepare_results
                search_move 1 || true
                redraw=1
                ;;
            HOME)
                search_prepare_results
                search_select_first || true
                redraw=1
                ;;
            END)
                search_prepare_results
                search_select_last || true
                redraw=1
                ;;
            PAGE_UP)
                search_prepare_results
                search_move -5 || true
                redraw=1
                ;;
            PAGE_DOWN)
                search_prepare_results
                search_move 5 || true
                redraw=1
                ;;
            ENTER)
                search_prepare_results
                if search_selected_load; then
                    search_close
                    return 0
                fi
                app_message "No hay resultados para reproducir." 4
                redraw=1
                ;;
            KEY)
                # search_append/backspace solo modifican el texto y marcan el
                # filtro pendiente: esta misma iteración redibuja la tecla sin
                # esperar a recorrer todo el catálogo.
                if search_handle_key "$INPUT_KEY"; then
                    redraw=1
                fi
                ;;
        esac

        ((redraw)) && ui_draw_search
    done
}
