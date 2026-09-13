#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Estado de sesión. Ningún proceso auxiliar ni escritura por segundo.
SLEEP_TIMER_AT=0
SLEEP_TIMER_FINISHED=0

sleep_timer_status() {
    local remaining=$((SLEEP_TIMER_AT - EPOCHSECONDS))
    SLEEP_TIMER_STATUS='Sin programar'
    if ((SLEEP_TIMER_AT > 0)); then
        ((remaining >= 0)) || remaining=0
        printf -v SLEEP_TIMER_STATUS '%02d:%02d:%02d restantes' "$((remaining/3600))" "$((remaining/60%60))" "$((remaining%60))"
    elif ((SLEEP_TIMER_FINISHED)); then SLEEP_TIMER_STATUS='Finalizado'; fi
}

sleep_timer_set() {
    local minutes=$1 now=${2:-$EPOCHSECONDS}
    if [[ -z "$minutes" ]]; then
        SLEEP_TIMER_AT=0 SLEEP_TIMER_FINISHED=0
        app_message 'Temporizador de parada cancelado.' 5
        return 0
    fi
    if [[ ! "$minutes" =~ ^[0-9]{1,4}$ ]] || ((10#$minutes < 1 || 10#$minutes > 1440)); then
        app_message 'Introduce de 1 a 1440 minutos. Esc conserva el temporizador anterior.' 7
        return 1
    fi
    SLEEP_TIMER_AT=$((now + 10#$minutes * 60)) SLEEP_TIMER_FINISHED=0
    app_message "Parada en $((10#$minutes)) minutos. No apaga el equipo; conserva las alarmas futuras." 8
}

sleep_timer_tick() {
    ((SLEEP_TIMER_AT > 0 && EPOCHSECONDS >= SLEEP_TIMER_AT)) || return 1
    # Consumir primero: ni un segundo tick ni la reconexión pueden reactivarla.
    SLEEP_TIMER_AT=0 SLEEP_TIMER_FINISHED=1
    app_reconnect_reset
    # Si ambas vencieron durante una suspensión, prima la parada. Una alarma
    # todavía futura se conserva y podrá volver a encender la radio.
    if ((${ALARM_AT:-0} > 0 && ALARM_AT <= EPOCHSECONDS)); then ALARM_AT=0 ALARM_LABEL=''; fi
    PENDING_RADIO_RESUME=0
    pending_preview_stop
    spectrum_stop
    local recorded=${RECORDING_ACTIVE:-0} status=0 notice='Temporizador: reproducción detenida.'
    if ((recorded)); then recording_stop || status=$?; fi
    player_stop
    # Un cierre de stream pendiente se verifica solo después de cerrar mpv.
    if ((recorded && RECORDING_ACTIVE)); then
        status=0; recording_stop || status=$?
    fi
    app_reconnect_reset
    if ((recorded)); then
        if ((status)) || [[ -n "${RECORDING_LAST_ERROR:-}" ]]; then
            notice+=' Grabación conservada; revisa su estado en Grabaciones.'
        else notice+=' Grabación cerrada.'; fi
    fi
    app_message "$notice" 10
    return 0
}

app_edit_sleep_timer() {
    local text='' notice='' redraw=1
    while true; do
        if ((redraw)); then
            station_field_draw 'PARADA EN MINUTOS' "$text" \
                'De 1 a 1440 minutos. Enter programa; vacío cancela la parada. Esc conserva la anterior. No apaga el equipo. La alarma futura se conserva.' "$notice"
        fi
        input_read || return 1
        redraw=1
        case "$INPUT_EVENT" in
            ESC) return 0 ;;
            ENTER) if sleep_timer_set "$text"; then return 0; else notice=${UI_MESSAGE:-Minutos inválidos.}; fi ;;
            DELETE) text='' notice='' ;;
            RESIZE) ;;
            TICK) redraw=0; panel_poll && redraw=1 ;;
            KEY)
                case "$INPUT_KEY" in
                    [0-9]) ((${#text} >= 4)) || text+=$INPUT_KEY ;;
                    $'\x7f'|$'\x08') text=${text%?} ;;
                    $'\x15') text='' ;;
                esac ;;
        esac
    done
}
