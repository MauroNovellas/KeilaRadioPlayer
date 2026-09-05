#!/usr/bin/env bash

# Integración de la búsqueda dentro del bucle principal de Keila.
# Se carga al final del launcher, cuando las funciones base ya existen.

# shellcheck source=lib/search.sh
source "$BASE_DIR/lib/search.sh"
# shellcheck source=lib/ui-search.sh
source "$BASE_DIR/lib/ui-search.sh"

app_search_catalog_fzf() {
    ui_suspend
    local status=0
    stations_select_fzf || status=$?
    ui_resume
    if ((status != 0)); then
        app_message "Búsqueda cancelada." 3
        return 0
    fi
    app_play "$SELECTED_NAME" "$SELECTED_URL"
}

app_search_catalog() {
    if [[ "${KEILA_FZF_SEARCH:-0}" == '1' ]]; then
        app_search_catalog_fzf
        return $?
    fi

    # Si ya existe una copia válida, entrar en búsqueda es inmediato. Solo la
    # primera vez, sin catálogo local, suspendemos la TUI mientras se descarga.
    if ! stations_catalog_valid; then
        ui_suspend
        local status=0
        stations_ensure_catalog || status=$?
        ui_resume
        if ((status != 0)); then
            app_message "No hay un catálogo válido para buscar emisoras." 7
            return 1
        fi
    fi

    UI_HELP_VISIBLE=0
    ui_clear_message
    if ! search_open; then
        app_message "No se pudo cargar el catálogo para la búsqueda integrada." 7
        return 1
    fi
}

app_draw() {
    if ((SEARCH_ACTIVE)); then
        ui_draw_search
    else
        ui_draw
    fi
}

app_handle_search_key() {
    local key="$1"

    case "$key" in
        $'\x7f'|$'\x08') search_backspace || true ;;
        $'\x15') search_clear || true ;;
        *) search_append "$key" || return 1 ;;
    esac
    return 0
}

app_play_search_selected() {
    if ! search_selected_load; then
        app_message "No hay resultados para reproducir." 4
        return 1
    fi

    local name="$SELECTED_NAME"
    local url="$SELECTED_URL"
    search_close
    app_play "$name" "$url"
}

app_loop() {
    input_init
    ui_enter
    app_draw

    while true; do
        if ! input_read; then
            return 0
        fi

        local redraw=0

        if ((SEARCH_ACTIVE)); then
            case "$INPUT_EVENT" in
                TICK)
                    app_poll_player && redraw=1
                    ui_message_tick && redraw=1
                    ;;
                RESIZE)
                    redraw=1
                    ;;
                ESC)
                    search_close
                    redraw=1
                    ;;
                UP)
                    search_move -1 || true
                    redraw=1
                    ;;
                DOWN)
                    search_move 1 || true
                    redraw=1
                    ;;
                HOME)
                    search_select_first || true
                    redraw=1
                    ;;
                END)
                    search_select_last || true
                    redraw=1
                    ;;
                PAGE_UP)
                    search_move -5 || true
                    redraw=1
                    ;;
                PAGE_DOWN)
                    search_move 5 || true
                    redraw=1
                    ;;
                ENTER)
                    app_play_search_selected || true
                    redraw=1
                    ;;
                KEY)
                    if app_handle_search_key "$INPUT_KEY"; then
                        redraw=1
                    fi
                    ;;
            esac
        else
            case "$INPUT_EVENT" in
                TICK)
                    app_poll_player && redraw=1
                    ui_message_tick && redraw=1
                    ;;
                RESIZE)
                    redraw=1
                    ;;
                ESC)
                    if ((UI_HELP_VISIBLE)); then
                        ui_toggle_help
                        redraw=1
                    fi
                    ;;
                UP)
                    ui_move_selection -1 || true
                    redraw=1
                    ;;
                DOWN)
                    ui_move_selection 1 || true
                    redraw=1
                    ;;
                LEFT)
                    app_change_volume "$((-KEILA_VOLUME_STEP))"
                    redraw=1
                    ;;
                RIGHT)
                    app_change_volume "$KEILA_VOLUME_STEP"
                    redraw=1
                    ;;
                HOME)
                    ui_select_first || true
                    redraw=1
                    ;;
                END)
                    ui_select_last || true
                    redraw=1
                    ;;
                PAGE_UP)
                    ui_move_selection -5 || true
                    redraw=1
                    ;;
                PAGE_DOWN)
                    ui_move_selection 5 || true
                    redraw=1
                    ;;
                ENTER)
                    app_play_selected || true
                    redraw=1
                    ;;
                KEY)
                    app_handle_key "$INPUT_KEY"
                    local key_status=$?
                    if ((key_status == 2)); then
                        app_draw
                        return 0
                    elif ((key_status == 0)); then
                        redraw=1
                    fi
                    ;;
            esac
        fi

        ((redraw)) && app_draw
    done
}
