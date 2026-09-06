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
INPUT_PENDING_EVENT=""
INPUT_PENDING_KEY=""
INPUT_POLL_INTERVAL="${KEILA_INPUT_POLL_INTERVAL:-0.02}"
INPUT_REPEAT_CAP="${KEILA_INPUT_REPEAT_CAP:-3}"
INPUT_REPEAT_DRAIN_LIMIT="${KEILA_INPUT_REPEAT_DRAIN_LIMIT:-512}"
INPUT_REPEAT_DRAIN_TIMEOUT="${KEILA_INPUT_REPEAT_DRAIN_TIMEOUT:-0.002}"

input_init() {
    INPUT_RESIZE_PENDING=0
    INPUT_PENDING_EVENT=""
    INPUT_PENDING_KEY=""
    INPUT_REPEAT_COUNT=1
    trap 'INPUT_RESIZE_PENDING=1' WINCH
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
    local second third fourth

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
                1|4|5|6)
                    if IFS= read -rsn1 -t 0.03 fourth && [[ "$fourth" == '~' ]]; then
                        case "$third" in
                            1) INPUT_EVENT="HOME" ;;
                            4) INPUT_EVENT="END" ;;
                            5) INPUT_EVENT="PAGE_UP" ;;
                            6) INPUT_EVENT="PAGE_DOWN" ;;
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

# Solo agrupamos acciones que tiene sentido mantener pulsadas. Durante búsqueda
# las letras son texto, por lo que nunca agrupamos KEY mientras SEARCH_ACTIVE=1.
input_event_is_repeatable() {
    local event="$1" key="${2:-}"

    case "$event" in
        UP|DOWN|LEFT|RIGHT|PAGE_UP|PAGE_DOWN)
            return 0
            ;;
        KEY)
            ((${SEARCH_ACTIVE:-0})) && return 1
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
    printf '%s\n' "$cap"
}

input_repeat_drain_limit_value() {
    local limit="$INPUT_REPEAT_DRAIN_LIMIT"
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=512
    ((limit < 1)) && limit=1
    ((limit > 4096)) && limit=4096
    printf '%s\n' "$limit"
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
    limit=$(input_repeat_drain_limit_value)
    cap=$(input_repeat_cap_value)

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
    if ((seen > cap)); then
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

input_read() {
    local key status

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

    IFS= read -rsn1 -t "$INPUT_POLL_INTERVAL" key
    status=$?

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
