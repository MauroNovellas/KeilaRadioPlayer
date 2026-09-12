#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ui_refresh_size() { :; }
tput() { :; }
UI_COLOR=0 UI_MESSAGE=''
FAVORITE_NAMES=() FAVORITE_URLS=()
SESSION_LOG_FILE='/sesiones/registro.txt'
SESSION_HISTORY_ROWS=($'2026-09-12 10:00:00\tRadio Test\tCanción anterior' $'2026-09-12 10:05:00\tRadio Test\tNueva canción')
session_history_refresh() { return 1; }
STATUS_ROWS=('Versión|Keila 2.1' 'Volumen|50%' 'Config|/una/ruta/muy/larga/para/probar/los/detalles/preferences')
STATUS_REFRESH_AT=$((EPOCHSECONDS + 3600))
PENDING_FILES=('/grabaciones/Radio con un nombre muy largo.mp3')
PENDING_NOTICE=''
BACKUP_FILES=('/copias/keila-backup-con-nombre-muy-largo.tar.gz')
BACKUP_SIZES=(8192) BACKUP_DATES=('2026-09-12 10:00:00')
BACKUP_TARGET=${BACKUP_FILES[0]} BACKUP_NOTICE='Copia privada de datos personales'
declare -A PENDING_METADATA=([/grabaciones/Radio\ con\ un\ nombre\ muy\ largo.mp3]='4096|2026-09-12 10:00:00')
PANEL_PARENT_PATH='OPCIONES > PRUEBA'
OPTIONS_TITLE='PADRE' OPTIONS_SELECTED=7 OPTIONS_SCROLL=2 OPTIONS_ROWS=('P|Padre|Se conserva|menu:main||')

check_frame() {
    local frame=$1 screen=$2 line count=0 selected_line=''
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((count += 1))
        ((${#line} < UI_COLS)) || fail "$screen desborda ancho: ${#line}/$UI_COLS"
        [[ "$line" != '> '* ]] || selected_line=$line
    done <<< "$frame"
    ((count == UI_LINES)) || fail "$screen desborda alto: $count/$UI_LINES"
    [[ "$frame" != *$'\033'* && "$frame" != *$'\t'* ]] || fail "$screen filtra controles"
    if ((UI_COLS >= 20 && UI_LINES >= 6)); then
        [[ -n "$selected_line" ]] || fail "$screen oculta la selección"
        [[ "$frame" == *'Esc '* ]] || fail "$screen oculta la salida"
        if [[ "$screen" == comentarios ]]; then
            [[ "$selected_line" == *'Z_'* ]] || fail 'se pierde el cursor al editar comentario largo'
            [[ "$frame" != *'? detalle'* ]] || fail 'se anuncia una ayuda que roba texto al comentario'
        fi
    fi
}

for geometry in '160 45' '110 24' '97 16' '96 16' '80 24' '62 16' '50 13' '42 11' '40 10' '30 8' '20 6' '8 5' '2 1'; do
    read -r UI_COLS UI_LINES <<< "$geometry"
    for unicode in 0 1; do
        UI_UNICODE=$unicode; ui_configure_glyphs
        for screen in preferencias ayuda alarma ecualizador comentarios historial grabaciones diagnostico copias confirmacion; do
            BACKUP_PREPARED_DIR=''
            case "$screen" in
                preferencias) preferences_build_rows settings; frame=$(panel_draw PREFERENCIAS 0 0 'Enter cambiar | Esc volver' '') ;;
                ayuda) preferences_build_rows help; frame=$(panel_draw AYUDA 0 0 'Enter detalle | Esc volver' '') ;;
                alarma) frame=$(alarm_editor_draw '12:3') ;;
                ecualizador) frame=$(equalizer_editor_draw) ;;
                comentarios) frame=$(label_editor_draw 'Radio con nombre largo' 'Comentario largo para comprobar que el cursor de escritura queda siempre visible Z') ;;
                historial) frame=$(session_history_draw) ;;
                grabaciones) frame=$(pending_draw 0 0) ;;
                diagnostico) frame=$(status_draw) ;;
                copias) frame=$(backup_manager_draw) ;;
                confirmacion) BACKUP_PREPARED_DIR='/copias/preparada'; frame=$(backup_manager_draw) ;;
            esac
            check_frame "$frame" "$screen $geometry"
            # Comprobar el cursor con el nombre simple para habilitar su aserto.
            [[ "$screen" != comentarios ]] || check_frame "$frame" comentarios
        done
    done
done

# El render de una pantalla hija no altera el menú que la abrió.
UI_COLS=100 UI_LINES=24
preferences_build_rows settings
panel_draw PREFERENCIAS 3 0 'Enter cambiar | Esc volver' '' >/dev/null
[[ "$OPTIONS_TITLE:$OPTIONS_SELECTED:$OPTIONS_SCROLL" == PADRE:7:2 ]] || fail 'el hijo altera selección o título del padre'
[[ "${OPTIONS_ROWS[0]}" == 'P|Padre|Se conserva|menu:main||' ]] || fail 'el hijo reemplaza las filas del padre'

printf 'ok   diez pantallas: 13 geometrías, dos modos, cursor de edición y aislamiento del padre\n'
