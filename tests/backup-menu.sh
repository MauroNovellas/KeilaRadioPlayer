#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
FAVORITE_NAMES=() FAVORITE_URLS=() RECENT_NAMES=() RECENT_URLS=()
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ui_refresh_size() { UI_COLS=40 UI_LINES=10; }
ui_draw() { :; }
tput() { :; }
polls=0 prepares=0 restores=0
app_poll_player() { ((polls+=1)); return 1; }
catalog_poll() { return 1; }
pending_scan_poll() { return 1; }
ui_message_tick() { return 1; }
backup_manager_cleanup() { BACKUP_JOB_PID='' BACKUP_JOB_ACTION='' BACKUP_RESTORE_ACTIVE=0; backup_discard_prepared; }
backup_job_start() { BACKUP_JOB_ACTION=$1 BACKUP_JOB_PID=simulado; [[ "$1" != prepare ]] || ((prepares+=1)); return 0; }
backup_job_poll() {
    [[ -n "$BACKUP_JOB_PID" ]] || return 1
    case "$BACKUP_JOB_ACTION" in
        scan) BACKUP_FILES=("$task_tmp/copia.tar.gz"); BACKUP_SIZES=(512); BACKUP_DATES=('2026-09-12 10:00:00') ;;
        prepare)
            BACKUP_PREPARED_DIR="$task_tmp/prepared"
            mkdir -p "$BACKUP_PREPARED_DIR/tree/keila-backup/config"
            printf 'Radio|https://radio.invalid\n' > "$BACKUP_PREPARED_DIR/tree/keila-backup/config/favorites"
            BACKUP_EXPECTED=simulada ;;
        restore) BACKUP_RESTORE_ACTIVE=0 ;;
    esac
    BACKUP_JOB_PID='' BACKUP_JOB_ACTION=''
    return 0
}
backup_manager_confirm() { ((restores+=1)); BACKUP_RESTORE_ACTIVE=1; backup_job_start restore; }
step=0
input_read() {
    ((step+=1)); INPUT_KEY=''
    case "$step" in
        1|3|8) INPUT_EVENT=TICK ;;
        2|7) INPUT_EVENT=KEY; INPUT_KEY=r ;;
        4) INPUT_EVENT=RESIZE ;;
        5) [[ -n "$BACKUP_PREPARED_DIR" ]] || fail 'resize cancela confirmación'; INPUT_EVENT=DOWN ;;
        6) INPUT_EVENT=ESC ;;
        9) INPUT_EVENT=KEY; INPUT_KEY=r ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_backups_menu list >/dev/null || fail menú
[[ $prepares == 2 && $restores == 0 && $polls == 3 ]] || fail 'R confirma sin Enter, o faltan sondeos'
[[ -z "$BACKUP_PREPARED_DIR" && $PREFERENCES_ACTIVE == 0 ]] || fail 'salida deja confirmación o foco'

# Enter en la lista es detalle de lectura, nunca restauración.
step=0
input_read() {
    ((step+=1)); INPUT_KEY=''
    case "$step" in
        1) INPUT_EVENT=TICK ;;
        2) INPUT_EVENT=ENTER ;;
        3) INPUT_EVENT=KEY; INPUT_KEY=r ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_backups_menu list >/dev/null || fail detalle
[[ $restores == 0 && $prepares == 2 ]] || fail 'detalle permite restaurar'

# Solo Enter en la pantalla de confirmación inicia el cambio. Esc no interrumpe
# a mitad de la publicación de un conjunto; el polling sigue atendiendo radio.
step=0
input_read() {
    ((step+=1)); INPUT_KEY=''
    case "$step" in
        1|3|6) INPUT_EVENT=TICK ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=r ;;
        4) INPUT_EVENT=ENTER ;;
        5) INPUT_EVENT=ESC ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_backups_menu list >/dev/null || fail confirmar
[[ $restores == 1 && $step == 8 ]] || fail 'confirmación no espera al trabajo o no vuelve'

# Entrada desde el árbol, sin cambiar atajos globales ni perder el menú padre.
opens=0 creates=0
app_backups_menu() { if [[ ${1:-list} == create ]]; then ((creates+=1)); else ((opens+=1)); fi; }
OPTIONS_SELECTIONS=() OPTIONS_OFFSETS=()
step=0
input_read() {
    ((step+=1)); INPUT_KEY=''
    case "$step" in
        1) INPUT_EVENT=KEY; INPUT_KEY=a ;;
        2) INPUT_EVENT=KEY; INPUT_KEY=c ;;
        3) INPUT_EVENT=KEY; INPUT_KEY=r ;;
        *) INPUT_EVENT=ESC ;;
    esac
}
app_options_menu >/dev/null || fail 'árbol de opciones'
[[ $opens == 1 && $creates == 1 ]] || fail 'rutas O A C / O A R'
printf 'ok   menú de copias: árbol, detalle, resize, cancelación, confirmación y ticks\n'
