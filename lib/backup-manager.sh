#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
BACKUP_JOB_PID='' BACKUP_JOB_DIR='' BACKUP_JOB_ACTION='' BACKUP_JOB_DEADLINE=0
BACKUP_PREPARED_DIR='' BACKUP_TARGET='' BACKUP_EXPECTED=''
BACKUP_NOTICE='' BACKUP_KEEP_NOTICE='' BACKUP_RESTORE_ACTIVE=0 BACKUP_DATA_BUSY=0 BACKUP_SELECTED=0 BACKUP_OFFSET=0
BACKUP_FILES=() BACKUP_SIZES=() BACKUP_DATES=()
BACKUP_LIST_SELECTED=0 BACKUP_LIST_OFFSET=0

backup_job_stop() {
    local pid=$BACKUP_JOB_PID
    [[ -n "$pid" ]] || return 0
    # Solo el grupo privado creado por este gestor, nunca el grupo de la TUI.
    kill -TERM -- "-$pid" 2>/dev/null || true
    # Puede recibirse Esc antes de que setsid haya creado el grupo.
    kill -TERM "$pid" 2>/dev/null || true
    kill -KILL -- "-$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    BACKUP_JOB_PID=''
}

backup_discard_prepared() {
    if [[ -n "$BACKUP_PREPARED_DIR" ]]; then
        rm -rf -- "$BACKUP_PREPARED_DIR"
        BACKUP_SELECTED=$BACKUP_LIST_SELECTED BACKUP_OFFSET=$BACKUP_LIST_OFFSET
    fi
    BACKUP_PREPARED_DIR='' BACKUP_TARGET='' BACKUP_EXPECTED=''
}

backup_manager_cleanup() {
    backup_job_stop
    [[ -z "$BACKUP_JOB_DIR" ]] || rm -rf -- "$BACKUP_JOB_DIR"
    BACKUP_JOB_DIR='' BACKUP_JOB_ACTION='' BACKUP_RESTORE_ACTIVE=0 BACKUP_DATA_BUSY=0
    backup_discard_prepared
}

backup_job_start() {
    local action=$1 argument=${2:-}
    [[ -z "$BACKUP_JOB_PID" ]] || return 1
    BACKUP_JOB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keila-backup-job.XXXXXX") || return 1
    BACKUP_JOB_ACTION=$action BACKUP_JOB_DEADLINE=$((EPOCHSECONDS+90))
    [[ "$action" != restore ]] || BACKUP_RESTORE_ACTIVE=1
    if [[ "$action" == prepare ]]; then BACKUP_LIST_SELECTED=$BACKUP_SELECTED BACKUP_LIST_OFFSET=$BACKUP_OFFSET; fi
    if [[ "$action" == create || "$action" == restore ]]; then BACKUP_DATA_BUSY=1; fi
    setsid -- bash "$BASE_DIR/lib/backup-worker.sh" "$action" "$BACKUP_JOB_DIR" "$argument" \
        </dev/null > "$BACKUP_JOB_DIR/output.log" 2>&1 &
    BACKUP_JOB_PID=$!
    case "$action" in
        scan) BACKUP_NOTICE='Buscando copias locales…' ;;
        create) BACKUP_NOTICE='Creando copia privada… la radio sigue sonando.' ;;
        prepare) BACKUP_NOTICE='Comprobando copia antes de confirmar…' ;;
        restore) BACKUP_NOTICE='Guardando respaldo previo y restaurando… espera a que termine.' ;;
    esac
}

backup_reload_runtime() {
    local selected_url='' index=$UI_SELECTED_INDEX status=0
    if ((index < ${#FAVORITE_URLS[@]})); then selected_url=${FAVORITE_URLS[index]:-}
    else selected_url=${RECENT_URLS[index-${#FAVORITE_URLS[@]}]:-}; fi
    favorites_load && labels_load && history_load && state_load && preferences_load && equalizer_load || status=1
    config_load "$BASE_DIR/grabaciones" || status=1
    history_recent_refresh
    preferences_apply
    equalizer_apply || status=1
    PLAYER_INFO_INTERVAL=$KEILA_PLAYER_INFO_INTERVAL
    # No cargar PLAYER_VOLUME/URL desde state: restaurar no cambia de emisora,
    # no desmutea, no rearma alarmas ni abre la carpeta importada de grabaciones.
    UI_SELECTED_INDEX=0
    local -a urls=("${FAVORITE_URLS[@]}" "${RECENT_URLS[@]}")
    for index in "${!urls[@]}"; do [[ "${urls[index]}" != "$selected_url" ]] || { UI_SELECTED_INDEX=$index; break; }; done
    ui_sync_selection
    STATUS_REFRESH_AT=0
    return "$status"
}

backup_job_poll() {
    [[ -n "$BACKUP_JOB_PID" ]] || return 1
    local status=1 action=$BACKUP_JOB_ACTION work=$BACKUP_JOB_DIR row rest old_file=${BACKUP_FILES[BACKUP_SELECTED]:-} index
    if [[ -f "$work/result" ]]; then
        status=$(<"$work/result")
        wait "$BACKUP_JOB_PID" 2>/dev/null || true
        BACKUP_JOB_PID=''
    elif ((EPOCHSECONDS >= BACKUP_JOB_DEADLINE)) || ! kill -0 "$BACKUP_JOB_PID" 2>/dev/null; then
        backup_job_stop
    else return 1; fi
    BACKUP_JOB_DIR='' BACKUP_JOB_ACTION='' BACKUP_RESTORE_ACTIVE=0 BACKUP_DATA_BUSY=0
    if [[ "$status" != 0 ]]; then
        BACKUP_NOTICE='No se completó la operación. Los archivos originales se conservan.'
        if [[ -s "$work/output.log" ]]; then
            local error=''
            IFS= read -r error < "$work/output.log" || true
            error=${error//[[:cntrl:]]/ }
            BACKUP_NOTICE+=" ${error:0:180}"
        fi
    fi
    case "$action" in
        scan)
            if [[ "$status" == 0 ]]; then
                if [[ -n "${BACKUP_CREATED_PATH:-}" ]]; then old_file=$BACKUP_CREATED_PATH; BACKUP_CREATED_PATH=''; fi
                BACKUP_FILES=() BACKUP_SIZES=() BACKUP_DATES=()
                while IFS= read -r -d '' row; do
                    rest=${row#*$'\t'}
                    BACKUP_SIZES+=("${rest%%$'\t'*}"); rest=${rest#*$'\t'}
                    BACKUP_DATES+=("${rest%%$'\t'*}"); BACKUP_FILES+=("${rest#*$'\t'}")
                done < "$work/files"
                BACKUP_SELECTED=0
                for index in "${!BACKUP_FILES[@]}"; do
                    [[ "${BACKUP_FILES[index]}" != "$old_file" ]] || { BACKUP_SELECTED=$index; break; }
                done
                BACKUP_NOTICE="${#BACKUP_FILES[@]} copias. C crea; R comprueba antes de restaurar."
                if [[ -n "$BACKUP_KEEP_NOTICE" ]]; then BACKUP_NOTICE=$BACKUP_KEEP_NOTICE; BACKUP_KEEP_NOTICE=''; fi
            fi ;;
        create)
            if [[ "$status" == 0 ]]; then
                BACKUP_NOTICE="Copia creada: $(<"$work/created")"
                BACKUP_CREATED_PATH=$(<"$work/created")
                BACKUP_RESCAN=1
            fi ;;
        prepare)
            if [[ "$status" == 0 ]]; then
                BACKUP_PREPARED_DIR=$work BACKUP_EXPECTED=$(<"$work/signature")
                BACKUP_SELECTED=0 BACKUP_OFFSET=0
                BACKUP_NOTICE='Copia verificada. Revisa el contenido; Enter confirma y Esc cancela.'
                return 0
            fi
            backup_discard_prepared ;;
        restore)
            if [[ -s "$work/pre-restore" ]]; then
                if [[ "$status" == 0 ]]; then BACKUP_NOTICE='Restauración terminada.'
                else BACKUP_NOTICE='Restauración incompleta. Algunos datos pueden haber cambiado.'; fi
                BACKUP_NOTICE+=" Copia previa: $(<"$work/pre-restore")"
                backup_reload_runtime || BACKUP_NOTICE+=' No se pudieron aplicar todos los ajustes; reinicia Keila.'
            fi
            backup_discard_prepared
            BACKUP_RESCAN=1 ;;
    esac
    rm -rf -- "$work"
    return 0
}

backup_manager_build_rows() {
    local i size date file
    PANEL_ROWS=()
    if [[ -n "$BACKUP_PREPARED_DIR" ]]; then
        panel_add_row '' "${BACKUP_TARGET##*/}" "Archivo: $BACKUP_TARGET. Sustituye solo los datos enumerados. Se creará antes una copia de los datos actuales. No incluye grabaciones, catálogo, canciones de sesión ni alarmas. Enter confirma; Esc cancela." 'Confirmación'
        for i in "${!BACKUP_MEMBERS[@]}"; do
            [[ -f "$BACKUP_PREPARED_DIR/tree/keila-backup/${BACKUP_MEMBERS[i]}" ]] || continue
            panel_add_row '' "${BACKUP_LABELS[i]}" 'Se sustituirá por el contenido de la copia. Los datos no incluidos se conservan. La emisora actual, silencio y volumen siguen igual; el volumen de inicio y la carpeta de grabaciones se usan al reiniciar.' 'Incluido'
        done
        return
    fi
    for i in "${!BACKUP_FILES[@]}"; do
        file=${BACKUP_FILES[i]} size=${BACKUP_SIZES[i]} date=${BACKUP_DATES[i]}
        panel_add_row '' "${file##*/}" "Archivo: $file. Fecha de modificación: ${date:0:19}. Tamaño: $size bytes. Enter o ? muestra el detalle; R comprueba y después pide confirmar la restauración. No se modifica nada al seleccionar." "${date:0:10} $size B"
    done
    if ((${#BACKUP_FILES[@]} == 0)); then
        panel_add_row '' 'No hay copias disponibles' "Pulsa C para crear la primera. Puedes colocar copias importadas .tar.gz en $KEILA_STATE_DIR/backups y pulsar U para actualizar. No se incluyen grabaciones ni registros de canciones." 'C crear'
    fi
}

backup_manager_draw() {
    local -a PANEL_ROWS=()
    local footer='C crear | R restaurar | U actualizar | Esc volver' title='COPIAS DE SEGURIDAD'
    backup_manager_build_rows
    if [[ -n "$BACKUP_PREPARED_DIR" ]]; then title='CONFIRMAR RESTAURACIÓN'; footer='Enter confirma | Esc cancela'; fi
    ((BACKUP_RESTORE_ACTIVE == 0)) || footer='Restaurando… espera | La radio sigue'
    panel_draw "$title" "$BACKUP_SELECTED" "$BACKUP_OFFSET" "$footer" "$BACKUP_NOTICE" "${#BACKUP_FILES[@]} copias | Datos personales, sin audio"
    BACKUP_SELECTED=$PANEL_SELECTED BACKUP_OFFSET=$PANEL_SCROLL
}

backup_manager_confirm() {
    local actual
    [[ -n "$BACKUP_PREPARED_DIR" ]] || return 1
    if ((RECORDING_ACTIVE)) || [[ -n "$PENDING_PREVIEW_PID" ]]; then
        BACKUP_NOTICE='Detén la grabación o su escucha antes de restaurar.'; return 1
    fi
    if ((UI_COLS < 20 || UI_LINES < 6)); then BACKUP_NOTICE='Amplía la terminal para revisar y confirmar la restauración.'; return 1; fi
    actual=$(backup_signature "$BACKUP_TARGET") || actual=''
    if [[ "$actual" != "$BACKUP_EXPECTED" ]]; then
        backup_discard_prepared
        BACKUP_NOTICE='La copia cambió o desapareció. Selecciónala de nuevo.'
        return 1
    fi
    backup_job_start restore "$BACKUP_PREPARED_DIR"
}

app_backups_menu() {
    local initial=${1:-list} previous_preferences=$PREFERENCES_ACTIVE redraw=1 key event result=0
    local BACKUP_RESCAN=0 BACKUP_CREATED_PATH='' PANEL_VISIBLE=1 PANEL_SELECTED=0 PANEL_SCROLL=0
    backup_manager_cleanup
    BACKUP_KEEP_NOTICE=''
    BACKUP_SELECTED=0 BACKUP_OFFSET=0
    PREFERENCES_ACTIVE=1
    if [[ "$initial" == create ]]; then backup_job_start create || BACKUP_NOTICE='No se pudo iniciar la copia.'
    else backup_job_start scan || BACKUP_NOTICE='No se pudo buscar copias.'; fi
    while true; do
        ((redraw)) && backup_manager_draw
        input_read || { result=1; break; }
        event=$INPUT_EVENT key=${INPUT_KEY,,} redraw=1
        case "$event" in
            TICK)
                redraw=0
                panel_poll && redraw=1
                backup_job_poll && redraw=1
                if ((BACKUP_RESCAN)) && [[ -z "$BACKUP_JOB_PID" ]]; then
                    BACKUP_RESCAN=0 BACKUP_KEEP_NOTICE=$BACKUP_NOTICE
                    backup_job_start scan || BACKUP_NOTICE='No se pudo actualizar la lista.'
                    redraw=1
                fi
                ;;
            RESIZE) ;;
            *)
                if ((BACKUP_RESTORE_ACTIVE)); then continue; fi
                if [[ -n "$BACKUP_PREPARED_DIR" ]]; then
                    case "$event" in
                        ENTER) backup_manager_confirm || true ;;
                        ESC|LEFT) backup_discard_prepared; BACKUP_NOTICE='Restauración cancelada. No se han cambiado datos.' ;;
                        *)
                            # Se puede leer toda la lista antes de confirmar.
                            local -a PANEL_ROWS=()
                            backup_manager_build_rows
                            panel_move "$event" "$BACKUP_SELECTED" "${#PANEL_ROWS[@]}" "$PANEL_VISIBLE"
                            BACKUP_SELECTED=$PANEL_SELECTED ;;
                    esac
                    continue
                fi
                case "$event" in
                    ESC|LEFT) break ;;
                    UP|DOWN|HOME|END|PAGE_UP|PAGE_DOWN)
                        panel_move "$event" "$BACKUP_SELECTED" "${#BACKUP_FILES[@]}" "$PANEL_VISIBLE"
                        BACKUP_SELECTED=$PANEL_SELECTED ;;
                    ENTER|KEY)
                        [[ -z "$BACKUP_JOB_PID" ]] || { BACKUP_NOTICE='Operación en curso; puedes seguir navegando o volver con Esc.'; continue; }
                        if [[ "$event" == ENTER || "$key" == '?' ]]; then
                            local -a PANEL_ROWS=()
                            backup_manager_build_rows
                            panel_detail 'COPIAS DE SEGURIDAD' "$BACKUP_SELECTED"
                        else
                            case "$key" in
                                c) backup_job_start create || BACKUP_NOTICE='No se pudo iniciar la copia.' ;;
                                u) backup_job_start scan || BACKUP_NOTICE='No se pudo buscar copias.' ;;
                                r)
                                    if ((RECORDING_ACTIVE)) || [[ -n "$PENDING_PREVIEW_PID" ]]; then BACKUP_NOTICE='Detén la grabación o su escucha antes de restaurar.'
                                    elif ((${#BACKUP_FILES[@]})); then
                                        BACKUP_TARGET=${BACKUP_FILES[BACKUP_SELECTED]}
                                        backup_job_start prepare "$BACKUP_TARGET" || BACKUP_NOTICE='No se pudo comprobar la copia.'
                                    fi ;;
                            esac
                        fi ;;
                esac ;;
        esac
    done
    backup_manager_cleanup
    PREFERENCES_ACTIVE=$previous_preferences
    ((previous_preferences)) || ui_draw
    return "$result"
}
