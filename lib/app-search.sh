#!/usr/bin/env bash

# Integración de la búsqueda. En desktop reutiliza el dashboard principal y da
# foco a la mitad inferior de la columna de navegación; en tamaños menores
# conserva la vista modal responsive. El launcher sigue usando su mismo
# app_search_catalog() y su mismo bucle principal.

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
                --with-nth=1,2,3,4,6 \
                --prompt='Buscar emisora > ' \
                --header='Nombre | Ámbito/Tags | País | Formato | Código' \
                --layout=reverse \
                --border
    ) || return $?

    [[ -n "$selection" ]] || return 1

    local record="${selection//$'\t'/$'\x1f'}"
    IFS=$'\x1f' read -r \
        SELECTED_NAME \
        SELECTED_AMBIT \
        SELECTED_COUNTRY \
        SELECTED_FORMAT \
        SELECTED_URL \
        SELECTED_COUNTRYCODE <<< "$record"

    [[ -n "${SELECTED_NAME:-}" && -n "${SELECTED_URL:-}" ]]
}

search_handle_key() {
    local key="$1"
    case "$key" in
        $'\x7f'|$'\x08') search_backspace || true ;;
        *) search_append "$key" || return 1 ;;
    esac
    return 0
}

search_prepare_results() {
    search_apply_pending_filter || true
}

# Modifica Favoritos usando el resultado activo sin abandonar la búsqueda ni
# alterar la reproducción. F y E mayúsculas se reservan como comandos; la f
# minúscula sigue siendo texto normal para consultas como "fm" o "francia".
# Añadir es inmediato; quitar exige una segunda X sobre el mismo resultado.
search_toggle_selected_favorite() {
    search_prepare_results
    if ! search_selected_load; then
        app_message "No hay ningún resultado para modificar en favoritos." 5
        return 1
    fi

    local name="$SELECTED_NAME" url="$SELECTED_URL"
    local index confirm_status=0 action_status=0
    FAVORITES_TOGGLE_ACTION=''

    if ! favorites_load; then
        app_message "No se pudieron cargar favoritos." 6
        return 1
    fi

    if index=$(favorites_find_url "$url"); then
        favorites_confirm_removal 'search' "$url" || confirm_status=$?
        if ((confirm_status == 2)); then
            app_message "Pulsa X otra vez para eliminar de favoritos: $name" 4
            return 0
        fi
        if ((confirm_status != 0)); then
            app_message "No se pudo preparar la confirmación de eliminación." 6
            return 1
        fi

        if ! favorites_remove_index "$index"; then
            app_message "No se pudo eliminar de favoritos: $name" 6
            return 1
        fi
        FAVORITES_TOGGLE_ACTION='removed'
        favorites_load || {
            app_message "Favorito eliminado, pero no se pudieron recargar los datos." 6
            return 1
        }
        ui_sync_selection
        app_message "Eliminada de favoritos: $name" 4
        return 0
    fi

    favorites_confirm_clear
    favorites_add "$name" "$url" || action_status=$?
    case "$action_status" in
        0)
            FAVORITES_TOGGLE_ACTION='added'
            favorites_load || {
                app_message "Favorito añadido, pero no se pudieron recargar los datos." 6
                return 1
            }
            ui_select_url "$url" >/dev/null 2>&1 || true
            app_message "Añadida a favoritos: $name" 4
            ;;
        2)
            favorites_load >/dev/null 2>&1 || true
            app_message "Ya estaba en favoritos: $name" 4
            ;;
        *)
            app_message "No se pudo añadir a favoritos: $name" 6
            return 1
            ;;
    esac
    return 0
}

search_desktop_available() {
    ui_refresh_size
    local mode
    mode=$(ui_layout_mode "$UI_COLS" "$UI_LINES")
    ui_desktop_enabled "$UI_COLS" "$UI_LINES" "$mode"
}

search_draw_view() {
    if search_desktop_available; then
        # ui_draw vuelve a calcular el tamaño y, en desktop, la capa
        # ui-desktop-search-pane.sh pinta Favoritos + búsqueda en la derecha.
        ui_draw
    else
        ui_draw_search
    fi
}

stations_select_fzf() {
    if [[ "${KEILA_FZF_SEARCH:-0}" == '1' ]]; then
        stations_select_fzf_external
        return $?
    fi

    # La búsqueda integrada vive dentro de la pantalla alternativa que ya está
    # activa. No suspendemos/reanudamos la TUI: ui_draw reposiciona el cursor en
    # 0,0 y repinta sin borrar toda la terminal, evitando el destello al pulsar B.
    # Si aún no existe catálogo, la preparación se hace silenciosamente antes
    # del primer render del buscador.
    if declare -F stations_tsv_valid >/dev/null 2>&1 && ! stations_tsv_valid; then
        if [[ -n "${CATALOG_PID:-}" ]]; then
            app_message "${CATALOG_STATUS:-Preparando índice local…}" 4
            return 1
        fi
        if declare -F stations_json_valid >/dev/null 2>&1 && stations_json_valid; then
            app_message 'Preparando índice local…' 4
            if declare -F stations_rebuild_tsv >/dev/null 2>&1 && stations_rebuild_tsv >/dev/null 2>&1 && stations_tsv_valid; then
                app_message 'Índice local preparado.' 2
            else
                if declare -F catalog_start >/dev/null 2>&1; then
                    catalog_start || true
                fi
                app_message "${CATALOG_STATUS:-Preparando índice local…}" 4
                return 1
            fi
        fi
        if ! stations_tsv_valid && declare -F catalog_start >/dev/null 2>&1; then
            catalog_start force || true
            app_message "${CATALOG_STATUS:-Cargando emisoras…}" 4
            return 1
        fi
    fi

    if ! stations_catalog_valid; then
        if [[ -n "${CATALOG_PID:-}" ]]; then
            app_message 'Cargando emisoras…' 3
            return 1
        fi
        if declare -F catalog_start >/dev/null; then
            catalog_start force || true
            return 1
        fi
        stations_ensure_catalog >/dev/null 2>&1 || return 1
    fi

    if ! search_open; then
        return 1
    fi

    favorites_confirm_clear
    UI_HELP_VISIBLE=0
    ui_clear_message
    search_draw_view

    while true; do
        if ! input_read; then
            favorites_confirm_clear
            search_close
            return 1
        fi

        local redraw=0
        case "$INPUT_EVENT" in
            TICK)
                if declare -F catalog_poll >/dev/null && catalog_poll; then redraw=1; fi
                favorites_confirm_expire >/dev/null 2>&1 || true
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
                favorites_confirm_clear
                search_close
                return 1
                ;;
            UP)
                favorites_confirm_clear
                search_prepare_results
                search_move -1 || true
                redraw=1
                ;;
            DOWN)
                favorites_confirm_clear
                search_prepare_results
                search_move 1 || true
                redraw=1
                ;;
            LEFT)
                favorites_confirm_clear
                SEARCH_DETAILS_VISIBLE=0
                app_message 'Detalles de búsqueda ocultos.' 2
                redraw=1
                ;;
            RIGHT)
                favorites_confirm_clear
                SEARCH_DETAILS_VISIBLE=1
                app_message 'Detalles de búsqueda visibles.' 2
                redraw=1
                ;;
            HOME)
                favorites_confirm_clear
                search_prepare_results
                search_select_first || true
                redraw=1
                ;;
            END)
                favorites_confirm_clear
                search_prepare_results
                search_select_last || true
                redraw=1
                ;;
            PAGE_UP)
                favorites_confirm_clear
                search_prepare_results
                search_move -5 || true
                redraw=1
                ;;
            PAGE_DOWN)
                favorites_confirm_clear
                search_prepare_results
                search_move 5 || true
                redraw=1
                ;;
            DELETE)
                favorites_confirm_clear
                search_clear || true
                redraw=1
                ;;
            ENTER)
                favorites_confirm_clear
                search_prepare_results
                if search_selected_load; then
                    search_close
                    return 0
                fi
                app_message "No hay resultados para reproducir." 4
                redraw=1
                ;;
            KEY)
                if [[ "$INPUT_KEY" == 'X' ]]; then
                    search_toggle_selected_favorite || true
                    redraw=1
                elif [[ "$INPUT_KEY" == 'F' || "$INPUT_KEY" == 'R' ]]; then
                    favorites_confirm_clear
                    search_close
                    if [[ "$INPUT_KEY" == 'F' ]]; then ui_select_emisoras || true; else ui_select_recientes || true; fi
                    return 1
                elif [[ "$INPUT_KEY" == 'M' ]]; then
                    app_toggle_mute || true
                    redraw=1
                elif [[ "$INPUT_KEY" == 'P' ]]; then
                    favorites_confirm_clear
                    search_country_filter_toggle
                    search_apply_pending_filter || true
                    if ((SEARCH_COUNTRY_FILTER_ENABLED)); then
                        app_message "Filtro país activado: $KEILA_CATALOG_COUNTRY_FILTER" 4
                    else
                        app_message "Filtro país desactivado: búsqueda global" 4
                    fi
                    redraw=1
                elif [[ "$INPUT_KEY" == 'C' ]]; then
                    favorites_confirm_clear
                    app_edit_label || true
                    redraw=1
                # El resto de caracteres, incluidas e y f minúsculas, siguen siendo
                # texto. append/backspace solo marcan el filtro pendiente para
                # que esta misma iteración pueda pintar el teclado al instante.
                else
                    favorites_confirm_clear
                    if search_handle_key "$INPUT_KEY"; then
                        redraw=1
                    fi
                fi
                ;;
        esac

        ((redraw)) && search_draw_view
    done
}
