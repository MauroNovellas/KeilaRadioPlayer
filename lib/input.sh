#!/usr/bin/env bash

# Entrada de teclado de Keila Radio Player v2.
# Convierte teclas y secuencias ANSI en eventos simples para la aplicación.

INPUT_EVENT=""
INPUT_KEY=""
INPUT_RESIZE_PENDING=0
INPUT_POLL_INTERVAL="${KEILA_INPUT_POLL_INTERVAL:-0.25}"

input_init() {
    INPUT_RESIZE_PENDING=0
    trap 'INPUT_RESIZE_PENDING=1' WINCH
}

input_shutdown() {
    trap - WINCH
}

input_emit_resize_if_pending() {
    if ((INPUT_RESIZE_PENDING)); then
        INPUT_RESIZE_PENDING=0
        INPUT_EVENT="RESIZE"
        INPUT_KEY=""
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

input_read() {
    local key status

    INPUT_EVENT=""
    INPUT_KEY=""

    if input_emit_resize_if_pending; then
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
}
