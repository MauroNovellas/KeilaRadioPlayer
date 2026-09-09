#!/usr/bin/env bash
# Alarma de sesión: solo date al configurarla, comparación entera en cada tick.
ALARM_AT=0
ALARM_LABEL=''
PLAYER_MUTED=0

alarm_set() {
    local value="$1" now=${2:-$EPOCHSECONDS} day target
    if [[ -z "$value" ]]; then
        ALARM_AT=0 ALARM_LABEL=''
        app_message 'Alarma cancelada.' 5
        return 0
    fi
    [[ "$value" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || {
        app_message 'Hora inválida. Usa HH:MM (00:00–23:59).' 5; return 1;
    }
    day=$(date -d "@$now" +%F) || return 1
    target=$(date -d "$day $value" +%s 2>/dev/null) || return 1
    if ((target <= now)); then
        day=$(date -d "$day +1 day" +%F) || return 1
        target=$(date -d "$day $value" +%s 2>/dev/null) || return 1
    fi
    ALARM_AT=$target
    ALARM_LABEL=$(date -d "@$target" '+%d/%m %H:%M')
    app_message "Alarma: $ALARM_LABEL. Mantén Keila abierto y el equipo despierto." 8
}

alarm_tick() {
    ((ALARM_AT > 0 && EPOCHSECONDS >= ALARM_AT)) || return 1
    ALARM_AT=0 ALARM_LABEL=''
    local name="${HISTORY_NAMES[0]:-${STATE_LAST_NAME:-}}" url="${HISTORY_URLS[0]:-${STATE_LAST_URL:-}}"
    if [[ -z "$url" ]]; then app_message 'Alarma: no hay una última emisora guardada.' 10; return 0; fi
    # app_play finaliza de forma segura una grabación antes de cambiar de stream.
    if app_play "$name" "$url"; then
        if player_ipc '{"command":["set_property","mute",false]}'; then
            PLAYER_MUTED=0
            app_message "Alarma: $name" 10
        else
            app_message 'Alarma iniciada; no se pudo confirmar la activación del sonido.' 10
        fi
    else
        app_message "Alarma: no se pudo iniciar $name. Comprueba la conexión." 10
    fi
    return 0
}

app_toggle_mute() {
    player_is_running || { app_message 'No hay emisora reproduciéndose para silenciar.' 5; return 1; }
    local value=true next=1
    if ((PLAYER_MUTED)); then value=false next=0; fi
    if player_ipc "{\"command\":[\"set_property\",\"mute\",$value]}"; then
        PLAYER_MUTED=$next
        if ((next)); then app_message 'Silenciado · repite el atajo de silencio para recuperar sonido.' 5; else app_message 'Sonido activado.' 4; fi
    else
        app_message 'No se pudo cambiar el silencio.' 5
        return 1
    fi
}

app_edit_alarm() {
    local text='' redraw=1
    while true; do
        if ((redraw)); then
            app_message "Alarma HH:MM: ${text}_ · Enter guardar (vacío cancela) · Esc volver" 0
            ui_draw
        fi
        input_read || { ui_clear_message; return 1; }
        redraw=1
        case "$INPUT_EVENT" in
            ESC) ui_clear_message; return 0 ;;
            ENTER) if alarm_set "$text"; then return 0; else ui_draw; redraw=0; fi ;;
            TICK) redraw=0; app_poll_player && redraw=1; catalog_poll && redraw=1; if declare -F ui_message_tick >/dev/null; then ui_message_tick && redraw=1; fi ;;
            KEY)
                case "$INPUT_KEY" in
                    $'\x7f'|$'\x08')
                        # Al borrar minutos, quitar primero los dos puntos
                        # automáticos para que el cursor vuelva a HH.
                        if [[ "$text" == *: ]]; then text=${text%:}; fi
                        text=${text%?}
                        ;;
                    $'\x15') text='' ;;
                    [0-9])
                        if ((${#text} < 2)); then
                            text+="$INPUT_KEY"
                            ((${#text} == 2)) && text+=':'
                        elif ((${#text} >= 3 && ${#text} < 5)); then
                            text+="$INPUT_KEY"
                        fi
                        ;;
                    :) ((${#text} == 2)) && text+=':' ;;
                esac ;;
        esac
    done
}
