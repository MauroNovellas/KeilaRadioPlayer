#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Preferencias como datos, escritura atómica y atajos por contexto.
PREF_AUTOPLAY=1
PREF_COLOR=1
PREF_UNICODE=1
PREF_SPECTRUM=1
PREFERENCES_ACTIVE=0
declare -a PREF_ACTIONS=(b f r c x g p m l z v h o q)
declare -a PREF_LABELS=('Buscar emisoras' Favoritas Recientes Comentarios 'Añadir/quitar favorito' Grabación Pausa Silencio 'Alarma temporal' Ecualizador Espectrograma Ayuda Opciones Salir)
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
# Ajustes y ayuda comparten filas y presentación con el centro de Opciones.
preferences_build_rows() {
    local mode=$1 i action description
    local -a states=(Desactivado Activado)
    PANEL_ROWS=()
    if [[ "$mode" == settings ]]; then
        panel_add_row '' 'Inicio automático' 'Al abrir Keila reproduce la última emisora que llegó a sonar. No restaura alarmas.' "${states[PREF_AUTOPLAY]}"
        panel_add_row '' Colores 'Usa colores si la terminal y su configuración lo permiten. El cursor sigue siendo visible sin color.' "${states[PREF_COLOR]}"
        panel_add_row '' 'Símbolos Unicode' 'Desactivado usa símbolos ASCII. Los textos conservan sus acentos.' "${states[PREF_UNICODE]}"
        panel_add_row '' Espectrograma 'Muestra el análisis de audio cuando hay captura disponible y espacio en la pantalla.' "${states[PREF_SPECTRUM]}"
    else
        panel_add_row '' 'Primeros pasos' "Busca una emisora con ${PREF_KEYS[b]^^}, escribe y pulsa Enter. Ajusta volumen con izquierda/derecha. ${PREF_KEYS[o]^^} abre Opciones; ${PREF_KEYS[q]^^} sale. Los detalles de cada fila se leen con Enter o ?."
    fi
    for i in "${!PREF_ACTIONS[@]}"; do
        action=${PREF_ACTIONS[i]}
        if [[ "$mode" == settings ]]; then
            description="Atajo de la pantalla principal. Enter permite asignar una letra; si está ocupada, se intercambian ambas acciones. Esc cancela. Las teclas dentro de los menús y editores son locales."
        else
            case "$action" in
                b) description='Escribe para buscar. Supr limpia. Enter reproduce. P filtra por país; X favorita, C comentario, M silencio, F/R listas. En pantallas pequeñas derecha muestra detalles e izquierda los oculta.' ;;
                f|r) description='Flechas arriba/abajo seleccionan; Enter reproduce. 1-9 y 0 reproducen las diez primeras de la sección. Home/End van a los extremos; PgUp/PgDn saltan por la lista.' ;;
                c) description='Edita el comentario de la emisora seleccionada. Enter guarda; Esc cancela; Ctrl+U o Supr vacían el texto. Los comentarios se conservan aunque se oculten en pantallas pequeñas.' ;;
                x) description='Añade a favoritas con una pulsación. Quitar requiere confirmar. Desde Opciones se actúa sobre la selección; moverse cancela la confirmación.' ;;
                g) description='Inicia la grabación de la emisora actual. Repite para detenerla y verificar su cierre. Opciones > Grabaciones permite comprobar y escuchar archivos. Eliminar exige confirmación y usa papelera.' ;;
                p) description='Pausa o reanuda la escucha sin cerrar la emisora.' ;;
                m) description='Silencia o recupera el sonido sin cambiar el volumen ni interrumpir una grabación.' ;;
                l) description='Escribe HHMM y Enter. Los dos puntos se añaden solos. Entrada vacía cancela la alarma. Suena una vez con la última emisora: Keila debe estar abierto y el equipo despierto.' ;;
                z) description='Izquierda/derecha seleccionan banda; arriba/abajo ajustan la ganancia. 1-5 eligen presets; C centra una banda; R deja plano. Enter o Esc vuelve. Los cambios se aplican al editarlos.' ;;
                v) description='Muestra u oculta el espectrograma. Requiere captura de audio disponible. Su preferencia se conserva al iniciar.' ;;
                h) description='Guía de uso con los atajos vigentes. Flechas seleccionan; Enter o ? abre el detalle. Esc vuelve.' ;;
                o) description='Centro de control: arriba/abajo seleccionan, Enter ejecuta, derecha abre categorías, izquierda/Esc vuelve. ? explica la opción completa. Recuerda la selección de cada categoría.' ;;
                q) description='Cierra Keila, finaliza la grabación en curso y libera el reproductor.' ;;
            esac
        fi
        panel_add_row "${PREF_KEYS[$action]^^}" "${PREF_LABELS[i]}" "$description"
    done
    if [[ "$mode" == settings ]]; then
        panel_add_row '' 'Restaurar valores predeterminados' 'Restaura visualización, inicio automático y atajos tras confirmar. Conserva emisoras, comentarios, volumen, grabaciones e historial.'
    else
        panel_add_row ',' Configuración 'Preferencias y atajos persistentes. Si el guardado falla se mantiene el valor anterior.'
        panel_add_row D Diagnóstico 'Estado del reproductor, catálogo y rutas de datos. Flechas recorren todas las filas y ? permite leer valores y rutas completos.'
        panel_add_row ';' Grabaciones 'C comprueba; E escucha o detiene la escucha; X prepara la eliminación. Enter confirma y Esc cancela. Flechas y PgUp/PgDn navegan.'
        panel_add_row '' 'Historial de sesión' 'Opciones > Sesión muestra el TXT de canciones con hora y emisora. Home/End van al principio/final. ? muestra toda la información de la entrada seleccionada.'
        panel_add_row '' Reconexión 'Keila reintenta los fallos de emisora de forma limitada. Enter vuelve a intentarlo al agotarse los intentos. No se reconecta automáticamente durante una grabación.'
    fi
}

app_preferences_menu() {
    local mode=${1:-settings} selected=0 offset=0 capture=0 confirm=0 notice='' event key action other old redraw=1 title='PREFERENCIAS'
    local previous_preferences=$PREFERENCES_ACTIVE
    local old_auto old_color old_unicode old_spectrum
    local -A previous_keys=()
    local -a PANEL_ROWS=()
    local PANEL_SELECTED=0 PANEL_SCROLL=0 PANEL_VISIBLE=1
    [[ "$mode" == help ]] && title='AYUDA'
    local restore_index=$((4 + ${#PREF_ACTIONS[@]}))
    PREFERENCES_ACTIVE=1
    while true; do
        if ((redraw)); then
            preferences_build_rows "$mode"
            local footer='Flechas mover | Enter cambiar | Esc volver'
            [[ "$mode" != help ]] || footer='Flechas mover | Enter detalle | Esc volver'
            ((capture)) && footer='Pulsa nueva letra | Esc cancela'
            ((confirm)) && footer='Enter confirma | Esc cancela'
            panel_draw "$title" "$selected" "$offset" "$footer" "${notice:-${UI_MESSAGE:-}}"
            selected=$PANEL_SELECTED offset=$PANEL_SCROLL
        fi
        input_read || break
        event=$INPUT_EVENT key=$INPUT_KEY redraw=1
        if [[ "$event" == TICK ]]; then
            redraw=0; panel_poll && redraw=1
            continue
        fi
        [[ "$event" != RESIZE ]] || continue
        old_auto=$PREF_AUTOPLAY old_color=$PREF_COLOR old_unicode=$PREF_UNICODE old_spectrum=$PREF_SPECTRUM
        for action in "${PREF_ACTIONS[@]}"; do previous_keys[$action]=${PREF_KEYS[$action]}; done
        if ((confirm)); then
            confirm=0
            if [[ "$event" != ENTER ]]; then notice='Restauración cancelada.'; continue; fi
            preferences_defaults
        elif ((capture)); then
            if [[ "$event" == ESC ]]; then capture=0; notice='Asignación cancelada.'; continue; fi
            [[ "$event" == KEY ]] || continue
            key=${key,,}
            if [[ ! "$key" =~ ^[bcefghilmnopqrtuvxyz]$ ]]; then notice='Letra no válida; A/D/W/S/J/K están reservadas.'; continue; fi
            action=${PREF_ACTIONS[selected-4]}
            old=${PREF_KEYS[$action]}
            for other in "${PREF_ACTIONS[@]}"; do
                [[ "${PREF_KEYS[$other]}" != "$key" ]] || PREF_KEYS[$other]=$old
            done
            PREF_KEYS[$action]=$key
            capture=0
        else
            case "$event" in
                ESC|LEFT) break ;;
                UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                    panel_move "$event" "$selected" "${#PANEL_ROWS[@]}" "$PANEL_VISIBLE"
                    selected=$PANEL_SELECTED; notice=''; continue ;;
                KEY)
                    if [[ "$mode" == help && ( "$key" == h || "$key" == H ) ]]; then break; fi
                    if [[ "$key" == '?' ]]; then panel_detail "$title" "$selected"; fi
                    continue ;;
                ENTER)
                    if [[ "$mode" == help ]]; then panel_detail "$title" "$selected"; continue; fi
                    case "$selected" in
                        0) PREF_AUTOPLAY=$((1-PREF_AUTOPLAY)) ;;
                        1) PREF_COLOR=$((1-PREF_COLOR)) ;;
                        2) PREF_UNICODE=$((1-PREF_UNICODE)) ;;
                        3) PREF_SPECTRUM=$((1-PREF_SPECTRUM)) ;;
                        "$restore_index") confirm=1; notice='Restaurar ajustes: Enter confirma; Esc cancela.'; continue ;;
                        *) capture=1; notice='Pulsa la nueva letra. Esc cancela.'; continue ;;
                    esac ;;
                *) continue ;;
            esac
        fi
        if preferences_save; then
            preferences_apply
            notice='Guardado.'
        else
            PREF_AUTOPLAY=$old_auto PREF_COLOR=$old_color PREF_UNICODE=$old_unicode PREF_SPECTRUM=$old_spectrum
            for action in "${PREF_ACTIONS[@]}"; do PREF_KEYS[$action]=${previous_keys[$action]}; done
            notice='No se pudo guardar. Se conserva el valor anterior.'
        fi
    done
    PREFERENCES_ACTIVE=$previous_preferences
    ((previous_preferences)) || ui_draw
    return 0
}
