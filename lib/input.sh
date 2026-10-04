#!/usr/bin/env bash

# Entrada de teclado de Keila Radio Player v2.
# Convierte teclas y secuencias ANSI en eventos simples para la aplicación.
#
# Los terminales pueden generar autorepeat bastante más deprisa de lo que una
# TUI Bash puede procesar + redibujar. Para que una tecla mantenida no deje una
# larga cola después de soltarla, agrupamos repeticiones idénticas que ya estén
# esperando en el buffer y limitamos cuánto de esa cola antigua se aplica.

INPUT_EVENT=""
INPUT_KEY=""
INPUT_REPEAT_COUNT=1
INPUT_RESIZE_PENDING=0
INPUT_RESIZE_GENERATION=0
INPUT_PENDING_EVENT=""
INPUT_PENDING_KEY=""
INPUT_CELL_WIDTH=0
INPUT_CELL_HEIGHT=0
INPUT_POLL_INTERVAL="${KEILA_INPUT_POLL_INTERVAL:-0.02}"
INPUT_READ_TIMEOUT=$INPUT_POLL_INTERVAL
INPUT_REPEAT_CAP="${KEILA_INPUT_REPEAT_CAP:-3}"
INPUT_REPEAT_DRAIN_LIMIT="${KEILA_INPUT_REPEAT_DRAIN_LIMIT:-512}"
INPUT_REPEAT_DRAIN_TIMEOUT="${KEILA_INPUT_REPEAT_DRAIN_TIMEOUT:-0.002}"

input_init() {
    INPUT_CELL_WIDTH=0 INPUT_CELL_HEIGHT=0
    INPUT_RESIZE_PENDING=0
    INPUT_PENDING_EVENT=""
    INPUT_PENDING_KEY=""
    INPUT_REPEAT_COUNT=1
    INPUT_RESIZE_GENERATION=$((INPUT_RESIZE_GENERATION+1))
    trap 'INPUT_RESIZE_PENDING=1; INPUT_RESIZE_GENERATION=$((INPUT_RESIZE_GENERATION+1))' WINCH
}

input_shutdown() {
    trap - WINCH
    INPUT_PENDING_EVENT=""
    INPUT_PENDING_KEY=""
    INPUT_REPEAT_COUNT=1
}

input_emit_resize_if_pending() {
    if ((INPUT_RESIZE_PENDING)); then
        INPUT_RESIZE_PENDING=0
        INPUT_EVENT="RESIZE"
        INPUT_KEY=""
        INPUT_REPEAT_COUNT=1
        return 0
    fi

    return 1
}

input_read_escape_sequence() {
    local second third fourth report char i height width

    INPUT_EVENT="ESC"
    INPUT_KEY=""

    if ! IFS= read -rsn1 -t 0.03 second; then
        return 0
    fi

    case "$second" in
        '[')
            if ! IFS= read -rsn1 -t 0.03 third; then
                return 0
            fi

            case "$third" in
                A) INPUT_EVENT="UP" ;;
                B) INPUT_EVENT="DOWN" ;;
                C) INPUT_EVENT="RIGHT" ;;
                D) INPUT_EVENT="LEFT" ;;
                H) INPUT_EVENT="HOME" ;;
                F) INPUT_EVENT="END" ;;
                6)
                    if IFS= read -rsn1 -t 0.03 fourth; then
                        if [[ $fourth == '~' ]]; then
                            INPUT_EVENT=PAGE_DOWN
                        elif [[ $fourth == ';' ]]; then
                            # Respuesta a CSI 16 t (alto/ancho de celda). Se lee
                            # como evento, nunca mediante un read ajeno al bucle.
                            # No convertir sus cifras en texto de búsqueda.
                            report=''
                            for ((i=0; i<16; i++)); do
                                IFS= read -rsn1 -t 0.03 char || break
                                [[ $char != t ]] || break
                                [[ $char == [0-9\;] ]] || break
                                report+=$char
                            done
                            INPUT_EVENT=TICK
                            if [[ ${char:-} == t && $report =~ ^([0-9]{1,3})\;([0-9]{1,3})$ ]]; then
                                height=$((10#${BASH_REMATCH[1]})) width=$((10#${BASH_REMATCH[2]}))
                                if ((height > 0 && height <= 256 && width > 0 && width <= 128)); then
                                    INPUT_CELL_HEIGHT=$height INPUT_CELL_WIDTH=$width
                                fi
                            fi
                        fi
                    fi
                    ;;
                1|3|4|5)
                    if IFS= read -rsn1 -t 0.03 fourth && [[ "$fourth" == '~' ]]; then
                        case "$third" in
                            1) INPUT_EVENT="HOME" ;;
                            3) INPUT_EVENT="DELETE" ;;
                            4) INPUT_EVENT="END" ;;
                            5) INPUT_EVENT="PAGE_UP" ;;
                        esac
                    fi
                    ;;
            esac
            ;;
        O)
            if IFS= read -rsn1 -t 0.03 third; then
                case "$third" in
                    A) INPUT_EVENT="UP" ;;
                    B) INPUT_EVENT="DOWN" ;;
                    C) INPUT_EVENT="RIGHT" ;;
                    D) INPUT_EVENT="LEFT" ;;
                    H) INPUT_EVENT="HOME" ;;
                    F) INPUT_EVENT="END" ;;
                esac
            fi
            ;;
    esac
}

# Lee un evento que ya debería estar esperando en el buffer. No produce TICK ni
# consume el WINCH pendiente: si no hay otro byte inmediato, simplemente falla.
input_read_buffered_event() {
    local key status

    INPUT_EVENT=""
    INPUT_KEY=""

    IFS= read -rsn1 -t "$INPUT_REPEAT_DRAIN_TIMEOUT" key
    status=$?
    ((status == 0)) || return 1

    case "$key" in
        $'\x1b')
            input_read_escape_sequence
            ;;
        '')
            INPUT_EVENT="ENTER"
            ;;
        *)
            INPUT_EVENT="KEY"
            INPUT_KEY="$key"
            ;;
    esac
    return 0
}

# Agrupamos también una misma tecla de texto durante una búsqueda. Esto evita
# filtrar y redibujar una pantalla completa por cada repetición de Retroceso.
input_event_is_repeatable() {
    local event="$1" key="${2:-}"

    case "$event" in
        UP|DOWN|LEFT|RIGHT|PAGE_UP|PAGE_DOWN)
            return 0
            ;;
        KEY)
            if ((${SEARCH_ACTIVE:-0})); then
                [[ "$key" == $'\x7f' || "$key" == $'\x08' || "$key" == [[:print:]] ]] && return 0
                return 1
            fi
            case "$key" in
                a|A|d|D|w|W|s|S) return 0 ;;
            esac
            ;;
    esac
    return 1
}

input_event_equals() {
    local left_event="$1" left_key="$2" right_event="$3" right_key="$4"
    [[ "$left_event" == "$right_event" && "$left_key" == "$right_key" ]]
}

input_repeat_cap_value() {
    local cap="$INPUT_REPEAT_CAP"
    [[ "$cap" =~ ^[0-9]+$ ]] || cap=3
    ((cap < 1)) && cap=1
    ((cap > 8)) && cap=8
    if [[ ${1:-} == state ]]; then INPUT_CAP_VALUE=$cap; else printf '%s\n' "$cap"; fi
}

input_repeat_drain_limit_value() {
    local limit="$INPUT_REPEAT_DRAIN_LIMIT"
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=512
    ((limit < 1)) && limit=1
    ((limit > 4096)) && limit=4096
    if [[ ${1:-} == state ]]; then INPUT_DRAIN_LIMIT_VALUE=$limit; else printf '%s\n' "$limit"; fi
}

# Consume las repeticiones idénticas que ya están en cola. INPUT_REPEAT_COUNT
# queda acotado: conservamos sensación de tecla mantenida, pero descartamos el
# exceso atrasado que produciría movimiento durante segundos tras soltarla.
# Si encontramos otro evento diferente, lo guardamos para la siguiente vuelta.
input_coalesce_repeat_burst() {
    local original_event="$INPUT_EVENT"
    local original_key="$INPUT_KEY"

    input_event_is_repeatable "$original_event" "$original_key" || {
        INPUT_REPEAT_COUNT=1
        return 0
    }

    local seen=1 drained=0 next_event next_key
    local limit cap
    input_repeat_drain_limit_value state
    input_repeat_cap_value state
    limit=$INPUT_DRAIN_LIMIT_VALUE cap=$INPUT_CAP_VALUE

    while ((drained < limit)); do
        if ! input_read_buffered_event; then
            break
        fi
        next_event="$INPUT_EVENT"
        next_key="$INPUT_KEY"
        ((drained += 1))

        if input_event_equals "$original_event" "$original_key" "$next_event" "$next_key"; then
            ((seen += 1))
            continue
        fi

        INPUT_PENDING_EVENT="$next_event"
        INPUT_PENDING_KEY="$next_key"
        break
    done

    INPUT_EVENT="$original_event"
    INPUT_KEY="$original_key"
    # Texto y Retroceso son datos: nunca aplicar el límite pensado para
    # navegación/volumen. El límite de drenaje conserva el resto en el buffer.
    if ((${SEARCH_ACTIVE:-0})) && [[ "$original_event" == KEY ]]; then
        INPUT_REPEAT_COUNT=$seen
    elif ((seen > cap)); then
        INPUT_REPEAT_COUNT=$cap
    else
        INPUT_REPEAT_COUNT=$seen
    fi
}

input_pop_pending_event() {
    [[ -n "$INPUT_PENDING_EVENT" ]] || return 1
    INPUT_EVENT="$INPUT_PENDING_EVENT"
    INPUT_KEY="$INPUT_PENDING_KEY"
    INPUT_PENDING_EVENT=""
    INPUT_PENDING_KEY=""
    INPUT_REPEAT_COUNT=1
    return 0
}

# read despierta inmediatamente cuando llega una tecla, aunque su timeout sea
# largo. Solo necesitamos ticks rápidos para animación visible o trabajo de
# búsqueda pendiente; el mantenimiento sin animación se atiende a 5 Hz.
input_poll_timeout() {
    INPUT_READ_TIMEOUT=$INPUT_POLL_INTERVAL
    # Conservar tanto la variable de entorno como un intervalo ajustado en vivo.
    [[ -z ${KEILA_INPUT_POLL_INTERVAL:-} && $INPUT_POLL_INTERVAL == 0.02 ]] || return 0
    if ((${SEARCH_ACTIVE:-0})) && { ((${SEARCH_FILTER_DIRTY:-0})) || [[ -n ${SEARCH_WORK_PID:-} ]]; }; then
        return 0
    fi
    [[ -z ${QUALITY_JOB_PID:-}${LOGO_PID:-} ]] || return 0
    if ((${SPECTRUM_ENABLED:-0} && !${PLAYER_PAUSED:-0} &&
          !${PREFERENCES_ACTIVE:-0} && !${UI_SUSPENDED:-0} &&
          (${PLAYER_STREAM_READY:-0} || ${PLAYER_INFO_READY:-0}))) &&
       [[ -n ${PLAYER_PID:-} && ${SPECTRUM_AVAILABLE:-unknown} != no ]]; then
        return 0
    fi
    INPUT_READ_TIMEOUT=0.2
}

input_read() {
    local key status

    if ((${APP_EXIT_INTERRUPT_PENDING:-0})); then
        app_process_interrupt_exit
        return 0
    fi
    INPUT_EVENT=""
    INPUT_KEY=""
    INPUT_REPEAT_COUNT=1

    if input_emit_resize_if_pending; then
        return 0
    fi

    if input_pop_pending_event; then
        input_coalesce_repeat_burst
        return 0
    fi

    input_poll_timeout
    IFS= read -rsn1 -t "$INPUT_READ_TIMEOUT" key
    status=$?

    if ((${APP_EXIT_INTERRUPT_PENDING:-0})); then
        app_process_interrupt_exit
        return 0
    fi
    if ((status != 0)); then
        if input_emit_resize_if_pending; then
            return 0
        fi

        # Bash devuelve >128 cuando read expira por timeout. Eso nos permite
        # hacer comprobaciones periódicas sin bloquear la TUI indefinidamente.
        if ((status > 128)); then
            INPUT_EVENT="TICK"
            return 0
        fi

        return 1
    fi

    case "$key" in
        $'\x1b')
            input_read_escape_sequence
            ;;
        '')
            INPUT_EVENT="ENTER"
            ;;
        *)
            INPUT_EVENT="KEY"
            INPUT_KEY="$key"
            ;;
    esac

    input_coalesce_repeat_burst
}
