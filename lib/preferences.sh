#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Preferencias como datos, escritura atómica y atajos por contexto.
PREF_AUTOPLAY=1
PREF_COLOR=1
PREF_UNICODE=1
PREF_SPECTRUM=1
PREFERENCES_ACTIVE=0
declare -a PREF_ACTIONS=(b f r c x g p m l z v h q)
declare -a PREF_LABELS=('Buscar emisoras' Favoritas Recientes Comentarios 'Añadir/quitar favorito' Grabación Pausa Silencio 'Alarma temporal' Ecualizador Espectrograma Ayuda Salir)
declare -A PREF_KEYS=()
for pref_action in "${PREF_ACTIONS[@]}"; do PREF_KEYS[$pref_action]=$pref_action; done
unset pref_action

preferences_defaults() {
    local action
    PREF_AUTOPLAY=1 PREF_COLOR=1 PREF_UNICODE=1 PREF_SPECTRUM=1
    for action in "${PREF_ACTIONS[@]}"; do PREF_KEYS[$action]=$action; done
}

preferences_load() {
    local key value action
    preferences_defaults
    [[ -f "$KEILA_CONFIG_DIR/preferences" ]] || return 0
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key:$value" in
            autoplay:[01]) PREF_AUTOPLAY=$value ;;
            color:[01]) PREF_COLOR=$value ;;
            unicode:[01]) PREF_UNICODE=$value ;;
            spectrum:[01]) PREF_SPECTRUM=$value ;;
            key_?:?)
                key=${key#key_}
                [[ -n "${PREF_KEYS[$key]+yes}" && "$value" =~ ^[bcefghilmnopqrtuvxyz]$ ]] && PREF_KEYS[$key]=$value
                ;;
        esac
    done < "$KEILA_CONFIG_DIR/preferences"
    # Un archivo editado a mano con duplicados recupera el mapa predeterminado.
    local -A seen=()
    for key in "${PREF_ACTIONS[@]}"; do
        value=${PREF_KEYS[$key]}
        if [[ -n "${seen[$value]:-}" ]]; then
            for action in "${PREF_ACTIONS[@]}"; do PREF_KEYS[$action]=$action; done
            break
        fi
        seen[$value]=1
    done
    return 0
}

preferences_save() {
    keila_init_paths || return 1
    local tmp key status=0
    local lock_dir="$KEILA_CONFIG_DIR/preferences.lock"
    lock_acquire "$lock_dir" || return 1
    tmp=$(mktemp "$KEILA_CONFIG_DIR/.preferences.XXXXXX") || { lock_release "$lock_dir"; return 1; }
    {
        printf 'autoplay=%s\ncolor=%s\nunicode=%s\nspectrum=%s\n' "$PREF_AUTOPLAY" "$PREF_COLOR" "$PREF_UNICODE" "$PREF_SPECTRUM" || status=1
        for key in "${PREF_ACTIONS[@]}"; do
            printf 'key_%s=%s\n' "$key" "${PREF_KEYS[$key]}" || { status=1; break; }
        done
    } > "$tmp" || status=1
    if ((status == 0)); then data_publish "$tmp" "$KEILA_CONFIG_DIR/preferences" preferences || status=1; fi
    if ((status)); then rm -f -- "$tmp"; fi
    lock_release "$lock_dir" || status=1
    return "$status"
}

preferences_apply() {
    UI_UNICODE=0
    if ((PREF_UNICODE)) && ui_locale_supports_unicode; then UI_UNICODE=1; fi
    ui_configure_glyphs
    ui_configure_theme
    SPECTRUM_ENABLED=$PREF_SPECTRUM
    if ((!SPECTRUM_ENABLED)); then spectrum_stop; fi
}

preferences_translate_key() {
    local key=${1,,} action
    PREF_TRANSLATED=$1
    [[ -n "$key" ]] || return 0
    for action in "${PREF_ACTIONS[@]}"; do
        if [[ "$key" == "${PREF_KEYS[$action]}" ]]; then PREF_TRANSLATED=$action; return; fi
    done
    # No conservar involuntariamente el atajo antiguo después de reasignarlo.
    if [[ -n "${PREF_KEYS[$key]:-}" ]]; then PREF_TRANSLATED=''; fi
}

# Menú desplazable que sigue atendiendo reproducción y reconexión.
# Las teclas de edición son locales; no se remapean caracteres de búsquedas.
app_preferences_menu() {
    local mode=${1:-settings} selected=0 offset=0 capture=0 notice='' event key i height width action other old redraw=1 title='CONFIGURACIÓN' confirm=0 description=''
    [[ "$mode" == help ]] && title='AYUDA'
    local -a rows=()
    local -a labels=(Desactivado Activado)
    local restore_index=$((4 + ${#PREF_ACTIONS[@]}))
    local -a explanations=(
        'Al abrir: reproduce la última escucha.'
        'Usa color si la terminal lo permite.'
        'Desactivado: símbolos ASCII sencillos.'
        'Muestra el análisis de audio.'
    )
    PREFERENCES_ACTIVE=1
    while true; do
        if ((redraw)); then
        rows=("Inicio automático: ${labels[PREF_AUTOPLAY]}" "Colores: ${labels[PREF_COLOR]}" "Unicode: ${labels[PREF_UNICODE]}" "Espectrograma: ${labels[PREF_SPECTRUM]}")
        for i in "${!PREF_ACTIONS[@]}"; do
            action=${PREF_ACTIONS[i]}
            rows+=("[${PREF_KEYS[$action]^^}] ${PREF_LABELS[i]}")
        done
        if [[ "$mode" == help ]]; then
            rows+=(
                ', Configuración · ? Ayuda completa'
                '; Grabaciones: revisar/escuchar'
                '↑↓ seleccionar · ←→ volumen'
                'Enter: reproducir selección'
                '1–9/0: diez primeras de la sección'
                'Home/End: extremos · PgUp/PgDn: saltar'
                "${PREF_KEYS[x]^^}: añadir; repetir para quitar favorito"
                'Búsqueda: minúsculas escriben'
                'Búsqueda: X favorito; C comentario'
                'Búsqueda: F/R listas; M silencio'
                'Búsqueda: Esc vuelve; Ctrl-U limpia'
                'Comentarios: Enter guarda; Esc cancela'
                'Ecualizador: ←→ banda; ↑↓ ganancia'
                'Ecualizador: 1–5 presets'
                'Ecualizador: C centrar; R plano'
                'Ecualizador: Esc vuelve'
                'Diagnóstico: D mayúscula estado en vivo'
                'Alarma: HHMM; Enter guarda; vacío cancela'
                'Alarma solo de sesión: equipo despierto'
                'Atajos personalizados: pantalla principal'
                'Los editores conservan sus teclas locales'
                'Volumen y última escucha: guardado'
                'Grabación: repite atajo para acabar'
                'Grabando no se reconecta automáticamente'
                'Reconexión: hasta 3 intentos por defecto'
                'Tras agotarlos: Enter reintenta'
            )
        else
            rows+=('Restaurar valores predeterminados')
        fi
        ui_refresh_size
        width=$((UI_COLS - 1)); ((width < 1)) && width=1
        height=$((UI_LINES - 6)); ((height < 1)) && height=1
        ((selected < offset)) && offset=$selected
        ((selected >= offset + height)) && offset=$((selected - height + 1))
        tput cup 0 0 2>/dev/null || true
        ui_print_styled_padded "$width" "KEILA · $title" title; printf '\n'
        for ((i=offset; i<offset+height && i<${#rows[@]}; i++)); do
            local marker='  '; ((i == selected)) && marker='> '
            ui_print_styled_padded "$width" "$marker${rows[i]}" accent; printf '\n'
        done
        description='Enter: asignar letra; Esc cancela.'
        if ((selected < 4)); then description=${explanations[selected]}; fi
        if ((selected == restore_index)); then description='Conserva emisoras y volumen.'; fi
        if [[ "$mode" == help ]]; then description='↑↓ / PgUp/PgDn · Home/End · Esc volver'; fi
        ui_print_padded "$width" "$description"; printf '\n'
        if [[ "$mode" == settings ]]; then ui_print_padded "$width" '↑↓ navegar · Enter cambiar · Esc volver'; else ui_print_padded "$width" 'Atajos principales y controles locales'; fi
        printf '\n'
        ui_print_padded "$width" "$notice"
        tput ed 2>/dev/null || true
        fi
        input_read || break
        event=$INPUT_EVENT key=$INPUT_KEY
        redraw=1
        if [[ "$event" == TICK ]]; then
            old=${UI_MESSAGE:-}
            app_poll_player || true
            ui_message_tick || true
            catalog_poll || true
            redraw=0
            if [[ "${UI_MESSAGE:-}" != "$old" && -n "${UI_MESSAGE:-}" ]]; then notice=$UI_MESSAGE; redraw=1; fi
            continue
        fi
        if ((confirm)); then
            confirm=0
            if [[ "$event" == ENTER ]]; then
                preferences_defaults
                if preferences_save; then notice='Valores predeterminados restaurados.'; else notice='Error al guardar la restauración.'; fi
                preferences_apply
                continue
            fi
            notice='Restauración cancelada.'
            continue
        fi
        if ((capture)); then
            if [[ "$event" == ESC ]]; then capture=0; notice=''; continue; fi
            [[ "$event" == KEY ]] || continue
            key=${key,,}
            if [[ ! "$key" =~ ^[bcefghilmnopqrtuvxyz]$ ]]; then notice='Usa una letra libre; A/D/W/S/J/K están reservadas.'; continue; fi
            action=${PREF_ACTIONS[selected-4]}
            old=${PREF_KEYS[$action]}
            for other in "${PREF_ACTIONS[@]}"; do
                [[ "${PREF_KEYS[$other]}" == "$key" ]] && PREF_KEYS[$other]=$old
            done
            PREF_KEYS[$action]=$key
            capture=0
        else
            case "$event" in
                ESC) break ;;
                UP) ((selected > 0)) && ((selected-=1)); continue ;;
                DOWN) ((selected+1 < ${#rows[@]})) && ((selected+=1)); continue ;;
                HOME) selected=0; continue ;;
                END) selected=$((${#rows[@]}-1)); continue ;;
                PAGE_UP) selected=$((selected-height)); ((selected<0)) && selected=0; continue ;;
                PAGE_DOWN) selected=$((selected+height)); ((selected>=${#rows[@]})) && selected=$((${#rows[@]}-1)); continue ;;
                ENTER)
                    [[ "$mode" == settings ]] || continue
                    case "$selected" in
                        0) PREF_AUTOPLAY=$((1-PREF_AUTOPLAY)) ;;
                        1) PREF_COLOR=$((1-PREF_COLOR)) ;;
                        2) PREF_UNICODE=$((1-PREF_UNICODE)) ;;
                        3) PREF_SPECTRUM=$((1-PREF_SPECTRUM)) ;;
                        "$restore_index") confirm=1; notice='Enter confirma restauración; otra tecla cancela.'; continue ;;
                        *) capture=1; notice='Pulsa la nueva letra (si está ocupada, intercambia).'; continue ;;
                    esac ;;
                *) continue ;;
            esac
        fi
        if preferences_save; then notice='Guardado.'; else notice='Error al guardar; el cambio solo dura esta sesión.'; fi
        preferences_apply
    done
    PREFERENCES_ACTIVE=0
    ui_draw
}
