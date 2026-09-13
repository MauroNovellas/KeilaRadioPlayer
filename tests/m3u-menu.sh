#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
keila_init_paths; favorites_init; favorites_load
tput() { :; }
ui_draw() { :; }
ui_refresh_size() { UI_COLS=80 UI_LINES=24; }
ui_navigation_refresh() { :; }
polls=0 plays=0 details=0
panel_poll() { polls=$((polls+1)); return 1; }
app_play() { plays=$((plays+1)); }
station_field_edit() { STATION_FIELD_RESULT=$fixture; return 0; }
panel_detail() {
    details=$((details+1))
    [[ ${PANEL_ROWS[$2]} == *https://radio.invalid/original* ]] || fail 'detalle no corresponde a vista previa'
}
fixture="$task_tmp/input.m3u"
printf '#EXTM3U\n#EXTINF:-1,Original\nhttps://radio.invalid/original\n' > "$fixture"
scenario=cancel step=0
input_read() {
    INPUT_KEY=''
    # Estado local del diálogo llamante (alcance dinámico de Bash).
    # shellcheck disable=SC2154
    if ((prepared == 0)); then sleep .01; INPUT_EVENT=TICK; return 0; fi
    step=$((step+1))
    case "$scenario:$step" in
        cancel:1) INPUT_EVENT=RESIZE ;;
        detail:1) INPUT_EVENT=DOWN ;;
        detail:2) INPUT_EVENT=ENTER ;;
        commit:1|collision:1) INPUT_EVENT=KEY; INPUT_KEY=G ;;
        snapshot:1)
            printf 'https://radio.invalid/changed\n' > "$fixture"
            INPUT_EVENT=ENTER ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_m3u_dialog import >/dev/null && fail 'cancelación declara guardado'
[[ ${#FAVORITE_URLS[@]} == 0 && $polls -gt 0 && $PREFERENCES_ACTIVE == 0 ]] || fail 'cancelación, ticks o foco'
scenario=detail step=0
app_m3u_dialog import >/dev/null && fail 'detalle guarda'
[[ $details == 1 && ${#FAVORITE_URLS[@]} == 0 ]] || fail 'detalle altera datos'
scenario=snapshot step=0
app_m3u_dialog import >/dev/null || fail 'confirmación importa'
[[ ${#FAVORITE_URLS[@]} == 1 && ${FAVORITE_URLS[0]} == https://radio.invalid/original && $plays == 0 ]] || fail 'no usa snapshot o reproduce'
fixture="$task_tmp/exportada.m3u" scenario=commit step=0
app_m3u_dialog export >/dev/null || fail exportar
[[ $(<"$fixture") == *'#EXTINF:-1,Original'* ]] || fail formato
before=$(sha256sum "$fixture")
scenario=collision step=0
app_m3u_dialog export >/dev/null && fail 'sobrescritura desde menú'
[[ $(sha256sum "$fixture") == "$before" ]] || fail 'colisión cambia archivo'
fixture="$task_tmp/no-existe.m3u" step=0
app_m3u_dialog import >/dev/null && fail 'archivo inexistente'
[[ $PREFERENCES_ACTIVE == 0 && ${#FAVORITE_URLS[@]} == 1 ]] || fail 'error pierde foco o favoritos'
[[ -z $M3U_JOB_PID && -z $M3U_JOB_DIR ]] || fail 'trabajo o temporal abandonado'
# La salida global también puede cancelar un trabajador que no termina.
M3U_JOB_DIR=$(mktemp -d "$task_tmp/job.XXXXXX")
job_dir=$M3U_JOB_DIR
setsid -- sleep 20 &
M3U_JOB_PID=$!
job_pid=$M3U_JOB_PID
m3u_cleanup
if kill -0 "$job_pid" 2>/dev/null || [[ -e "$job_dir" ]]; then fail 'limpieza deja proceso o temporal'; fi
printf 'ok   M3U UI: vista previa, detalle, cancelación, trabajo asíncrono y confirmación\n'
