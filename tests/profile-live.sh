#!/usr/bin/env bash
# TUI real: registra solo tiempos, etapas y códigos de salida, no contenido.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_MODE="${1:-live}"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
PROFILE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keila-profile.XXXXXX") || exit 1
PROFILE_LOG="$PROFILE_DIR/timing.tsv"
: > "$PROFILE_LOG"
PROFILE_COUNT=0

profile_call() {
    local profile_stage="$1" profile_start profile_end profile_status=0
    shift
    profile_start=$EPOCHREALTIME
    profile_start=${profile_start//[.,]/}
    "profile_original_$profile_stage" "$@" || profile_status=$?
    profile_end=$EPOCHREALTIME
    profile_end=${profile_end//[.,]/}
    if ((PROFILE_COUNT < 20000)); then
        printf '%s\t%s\t%s\t%s\n' "$profile_stage" "$profile_start" \
            "$((profile_end-profile_start))" "$profile_status" >> "$PROFILE_LOG"
        PROFILE_COUNT=$((PROFILE_COUNT+1))
    fi
    return "$profile_status"
}

# Hook llamado justo después de publicar un cuadro completo.
keila_profile_frame() {
    local profile_stamp=$EPOCHREALTIME
    profile_stamp=${profile_stamp//[.,]/}
    if ((PROFILE_COUNT < 20000)); then
        printf 'frame_ready\t%s\t0\t0\n' "$profile_stamp" >> "$PROFILE_LOG"
        PROFILE_COUNT=$((PROFILE_COUNT+1))
    fi
}

for profile_stage in input_read catalog_poll app_poll_player player_refresh_info \
    player_query_snapshot spectrum_tick ui_draw ui_draw_spectrum_only; do
    profile_definition=$(declare -f "$profile_stage")
    profile_definition=${profile_definition/"$profile_stage ()"/"profile_original_$profile_stage ()"}
    eval "$profile_definition"
    eval "$profile_stage() { profile_call $profile_stage \"\$@\"; }"
done
unset profile_stage profile_definition

profile_report() {
    printf '\nDIAGNÓSTICO KEILA (tiempos en milisegundos)\n'
    LC_ALL=C awk -F '\t' '
        NF == 4 {
            stage=$1; count[stage]++; total[stage]+=$3
            if ($3>maximum[stage]) maximum[stage]=$3
            if (($1=="frame_ready" || $1=="ui_draw_spectrum_only" || $1=="spectrum_tick") && $4==0) {
                stamp=$2+$3
                if (last[stage]) {
                    gap=stamp-last[stage]; gaps[stage]++; gap_total[stage]+=gap
                    if(gap>gap_max[stage]) gap_max[stage]=gap
                    if(gap>100000) slow[stage]++
                }
                last[stage]=stamp
            }
        }
        END {
            for (stage in count) {
                printf "%s: %d llamadas; media %.1f ms; máximo %.1f ms\n", stage, count[stage], total[stage]/count[stage]/1000, maximum[stage]/1000
                if(gaps[stage]) printf "  Intervalo: media %.1f ms; máximo %.1f ms; pausas >100 ms: %d\n", gap_total[stage]/gaps[stage]/1000, gap_max[stage]/1000, slow[stage]
            }
        }
    ' "$PROFILE_LOG"
    printf 'Registro: %s\n' "$PROFILE_LOG"
    printf 'Las esperas de teclado son normales; los tiempos de etapas anidadas no se suman.\n'
}

trap 'cleanup; profile_report' EXIT
if [[ "$PROFILE_MODE" == --self-test ]]; then
    profile_original_player_query_snapshot() { sleep 0.12; printf '{}'; }
    [[ "$(player_query_snapshot)" == '{}' ]] || exit 1
    profile_original_spectrum_tick() { SPECTRUM_AVAILABLE=no; return 1; }
    spectrum_tick && exit 1
    [[ "$SPECTRUM_AVAILABLE" == no ]] || exit 1
    keila_profile_frame
    sleep 0.06
    keila_profile_frame
else
    main
fi
