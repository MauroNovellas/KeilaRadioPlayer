#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'pending_cleanup; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
pending_scan_start() { return 0; }
recording_init "$task_tmp/recordings"
file="$RECORDINGS_DIR/Original.mp3"
printf 'audio de prueba\n' > "$file"
printf 'closed\n' > "$file.pending"
cp "$file" "$task_tmp/audio"; cp "$file.pending" "$task_tmp/marker"
identity=$(stat -c '%d:%i:%y' "$file")
signature=$(pending_signature "$file")
recording_rename "$file" 'Música con espacios' "$signature" || fail renombrado
renamed="$RECORDINGS_DIR/Música con espacios.mp3"
[[ ! -e "$file" && ! -e "$file.pending" && -f "$renamed.pending" ]] || fail 'no traslada par'
[[ $(stat -c '%d:%i:%y' "$renamed") == "$identity" ]] || fail 'copia o modifica audio'
cmp "$renamed" "$task_tmp/audio"; cmp "$renamed.pending" "$task_tmp/marker"
signature=$(pending_signature "$renamed")
for invalid in '' '   ' '../fuera' '/absoluta' '.oculta' 'sub/ruta' 'sub\ruta' $'salto\nlinea'; do
    if recording_rename "$renamed" "$invalid" "$signature"; then fail "acepta nombre inválido $invalid"; fi
done
for type in file directory link marker; do
    target="$RECORDINGS_DIR/$type.mp3"
    case "$type" in
        file) printf AJENO > "$target" ;;
        directory) mkdir "$target" ;;
        link) ln -s "$task_tmp/ausente" "$target" ;;
        marker) printf closed > "$target.pending" ;;
    esac
    if recording_rename "$renamed" "$type" "$signature"; then fail "sobrescribe $type"; fi
    [[ $(pending_signature "$renamed") == "$signature" ]] || fail 'colisión altera origen'
done
[[ $(<"$RECORDINGS_DIR/file.mp3") == AJENO && ! -e "$task_tmp/ausente" ]] || fail 'daña destino'
PENDING_PROBE_PID=$$ PENDING_TARGET=$renamed
if recording_rename "$renamed" Ocupada "$signature"; then fail 'renombra durante probe'; fi
PENDING_PROBE_PID=''
PENDING_PREVIEW_PID=$$ PENDING_PREVIEW_FILE=$renamed
if recording_rename "$renamed" Ocupada "$signature"; then fail 'renombra durante escucha'; fi
PENDING_PREVIEW_PID=''
printf cambio >> "$renamed"
if recording_rename "$renamed" Cambiada "$signature"; then fail 'acepta firma obsoleta'; fi

# Colisión aparecida dentro de mv: incluso si devuelve 0 al omitir, no es éxito.
collision=1 blocked='' crash='' after_move=0
mv() {
    local target=${*: -1}
    if [[ "$target" == "$RECORDINGS_DIR/Carrera.mp3" && $collision == 1 ]]; then printf AJENO > "$target"; fi
    if [[ -n "$blocked" && "$target" == "$blocked" ]]; then return 1; fi
    if [[ -n "$crash" && "$target" == "$crash" ]]; then
        ((after_move == 0)) || command mv "$@"
        kill -KILL "$BASHPID"
    fi
    command mv "$@"
}
signature=$(pending_signature "$renamed")
if recording_rename "$renamed" Carrera "$signature"; then fail 'colisión tratada como éxito'; fi
[[ -f "$renamed" && $(<"$RECORDINGS_DIR/Carrera.mp3") == AJENO && ! -e "$RECORDINGS_DIR/Carrera.mp3.pending" ]] || fail 'colisión daña datos'
blocked="$RECORDINGS_DIR/Fallo.mp3"
if recording_rename "$renamed" Fallo "$signature"; then fail 'oculta fallo de mv'; fi
[[ $(pending_signature "$renamed") == "$signature" && ! -e "$blocked.pending" ]] || fail 'fallo pierde datos'
blocked=''

# Si falla retirar el marcador antiguo, el destino tiene audio y marcador;
# se informa de la operación parcial y no se intenta un rollback destructivo.
partial="$RECORDINGS_DIR/Parcial.mp3"
printf AUDIO > "$partial"; printf closed > "$partial.pending"
blocked_remove="$partial.pending"
rm() { [[ "${*: -1}" != "$blocked_remove" ]] || return 1; command rm "$@"; }
if recording_rename "$partial" 'Parcial nueva' "$(pending_signature "$partial")"; then fail 'oculta marcador sobrante'; fi
[[ -f "$RECORDINGS_DIR/Parcial nueva.mp3" && -f "$RECORDINGS_DIR/Parcial nueva.mp3.pending" && -f "$partial.pending" && $RECORDING_FILES_NOTICE == 'Audio trasladado'* ]] || fail 'fallo de marcador pierde datos'
blocked_remove=''

# Papelera antigua y actual; recuperar con colisión exige confirmar otro destino.
pending_trash "$renamed" "$signature" || fail papelera
trashed=$RECORDING_FILES_RESULT
[[ -f "$trashed" && -f "$trashed.pending" && ! -e "$renamed" ]] || fail 'papelera no conserva par'
printf AJENO > "$renamed"
recording_restore_destination "$trashed" || fail destino
target=$RECORDING_RESTORE_TARGET
[[ "$target" == "$RECORDINGS_DIR/Música con espacios (recuperada 1).mp3" ]] || fail 'no propone alternativa'
printf NUEVO > "$target"
signature=$(pending_signature "$trashed")
if recording_restore "$trashed" "$target" "$signature"; then fail 'restaura sobre nuevo archivo'; fi
[[ -f "$trashed" && $(<"$target") == NUEVO ]] || fail 'colisión de recuperación daña datos'
recording_restore_destination "$trashed"
target=$RECORDING_RESTORE_TARGET
recording_restore "$trashed" "$target" "$signature" || fail recuperar
[[ -f "$target.pending" && ! -e "${trashed%/*}" && $(<"$renamed") == AJENO ]] || fail recuperación
mkdir -p "$RECORDINGS_DIR/.trash/recording.legacy"
legacy="$RECORDINGS_DIR/.trash/recording.legacy/Antigua.wav"
printf AUDIO > "$legacy"
printf 'conservar' > "${legacy%/*}/nota.txt"
recording_restore_destination "$legacy"
recording_restore "$legacy" "$RECORDING_RESTORE_TARGET" "$(pending_signature "$legacy")" || fail 'papelera antigua'
[[ -f "${legacy%/*}/nota.txt" && ! -e "$RECORDING_RESTORE_TARGET.pending" ]] || fail 'borra contenido adicional o inventa marcador'
ln -s "$task_tmp" "$RECORDINGS_DIR/.trash/recording.link"
if recording_restore_destination "$RECORDINGS_DIR/.trash/recording.link/audio.mp3"; then fail 'sigue carpeta enlazada'; fi

# Caída antes y después del rename: siempre queda audio completo y marcador.
for after_move in 0 1; do
    source_file="$RECORDINGS_DIR/Interrupción$after_move.ts"
    printf AUDIO > "$source_file"; printf closed > "$source_file.pending"
    crash="$RECORDINGS_DIR/Caída$after_move.ts"
    signature=$(pending_signature "$source_file")
    (trap - EXIT; recording_rename "$source_file" "Caída$after_move" "$signature") >/dev/null 2>&1 &
    writer=$!; status=0; wait "$writer" 2>/dev/null || status=$?
    ((status == 137)) || fail "no simula interrupción $after_move (salida $status)"
    if ((after_move)); then
        [[ ! -e "$source_file" && $(<"$crash") == AUDIO && -f "$crash.pending" && -f "$source_file.pending" ]] || fail 'caída tras rename pierde audio/marcador'
    else
        [[ $(<"$source_file") == AUDIO && -f "$source_file.pending" && ! -e "$crash" && -f "$crash.pending" ]] || fail 'caída antes de rename pierde audio/marcador'
    fi
done
crash=''
recording_files_lock || fail 'no recupera lock tras SIGKILL'
recording_files_unlock
# Una grabación nueva no puede reutilizar un nombre reservado por su marcador.
date() { printf '2000-01-01_00-00-00'; }
printf closed > "$RECORDINGS_DIR/Test_2000-01-01_00-00-00.ts.pending"
next=$(recording_next_file Test ts) || fail reserva
[[ "$next" == "$RECORDINGS_DIR/Test_2000-01-01_00-00-00_2.ts" ]] || fail 'reutiliza reserva pendiente'
printf 'ok   archivos: renombrado, recuperación, colisiones, fallos, SIGKILL y reservas\n'
