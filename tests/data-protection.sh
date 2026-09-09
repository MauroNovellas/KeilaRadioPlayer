#!/usr/bin/env bash
# Los stubs son llamados indirectamente por las funciones bajo prueba.
# shellcheck disable=SC2317
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
trap 'rm -rf -- "$task_tmp"' EXIT
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
set +e
source "$ROOT_DIR/keila-radio" >/dev/null
set -e
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
keila_init_paths
favorites_init
favorites_add Original https://original.invalid
labels_set https://original.invalid 'Comentario original'
STATE_VOLUME=37 STATE_LAST_NAME=Original STATE_LAST_URL=https://original.invalid
state_save
preferences_save
files=("$KEILA_FAVORITES_FILE" "$KEILA_CONFIG_DIR/labels" "$KEILA_STATE_FILE" "$KEILA_CONFIG_DIR/preferences")
for i in "${!files[@]}"; do cp "${files[i]}" "$task_tmp/original.$i"; done

# Fallo de publicación: el original debe seguir intacto y el error propagarse.
mv() { return 1; }
if favorites_add Nuevo https://nuevo.invalid; then fail favoritos; fi
if labels_set https://original.invalid Cambiado; then fail comentarios; fi
STATE_VOLUME=88
if state_save; then fail estado; fi
PREF_COLOR=0
if preferences_save; then fail preferencias; fi
unset -f mv
for i in "${!files[@]}"; do cmp "${files[i]}" "$task_tmp/original.$i" || fail 'original modificado'; done
# Los locks no liberados por el fallo simulado se recuperan al morir su dueño.
# Aquí el dueño sigue vivo: liberar explícitamente antes de la siguiente prueba.
for file in "${files[@]}"; do lock_release "$file.lock"; done

# Fallos de escritura, incluso si una escritura posterior podría tener éxito.
printf() {
    # Reenviar formato y argumentos intactos al printf real.
    # shellcheck disable=SC2059
    case "$1" in
        'volume\t%s\n'|'key_%s=%s\n'|'%s|%s\n') return 1 ;;
        *) builtin printf "$@" ;;
    esac
}
if state_save; then fail 'escritura de estado'; fi
if preferences_save; then fail 'escritura de preferencias'; fi
if favorites_add Nuevo https://nuevo.invalid; then fail 'escritura de favoritos'; fi
if labels_set https://original.invalid Cambiado; then fail 'escritura de comentario'; fi
unset -f printf
for i in "${!files[@]}"; do cmp "${files[i]}" "$task_tmp/original.$i" || fail 'escritura parcial publicada'; done

# La configuración inicial no se publica si falla la escritura del contenido.
cat() { return 1; }
if config_write_default; then fail 'configuración parcial aceptada'; fi
unset -f cat
[[ ! -e "$KEILA_CONFIG_FILE" ]] || fail 'configuración parcial publicada'
config_write_default
cp "$KEILA_CONFIG_FILE" "$task_tmp/config.original"
config_write_default
cmp "$KEILA_CONFIG_FILE" "$task_tmp/config.original"

# Matar el escritor justo antes del rename, cuando el temporal ya está completo.
for action in favorites labels state preferences; do
    (
        trap - EXIT
        mv() { kill -KILL "$BASHPID"; }
        case "$action" in
            favorites) favorites_add Nuevo https://nuevo.invalid ;;
            labels) labels_set https://original.invalid Cambiado ;;
            state) state_save ;;
            preferences) preferences_save ;;
        esac
    ) >/dev/null 2>&1 &
    writer=$!
    wait "$writer" 2>/dev/null && fail 'escritor no interrumpido'
done
for i in "${!files[@]}"; do cmp "${files[i]}" "$task_tmp/original.$i" || fail 'interrupción dañó original'; done
favorites_add Después https://despues.invalid
labels_set https://original.invalid Recuperado
state_save
preferences_save
# Lectura en otra sesión, sin depender de las variables de la sesión anterior.
bash -c 'launcher=$1; set -- --version; source "$launcher" >/dev/null; trap - EXIT; favorites_load; labels_load; state_load; preferences_load; [[ ${#FAVORITE_URLS[@]} == 2 && ${FAVORITE_LABELS[https://original.invalid]} == Recuperado && $STATE_VOLUME == 88 && $PREF_COLOR == 0 ]]' bash "$ROOT_DIR/keila-radio" || fail 'reinicio'

# Reserva concurrente, nombre y segundo idénticos; tampoco seguir enlaces rotos.
recording_init "$task_tmp/recordings"
date() { printf '2026-01-01_00-00-00'; }
first=$(recording_next_file Radio mp3)
printf 'NO TOCAR' > "$first"
ln -s "$task_tmp/ausente" "${first%.mp3}_2.mp3"
pids=()
for i in {1..12}; do
    recording_next_file Radio mp3 > "$task_tmp/path.$i" &
    pids+=("$!")
done
for writer in "${pids[@]}"; do wait "$writer" || fail reserva; done
declare -A seen=()
for i in {1..12}; do
    path=$(<"$task_tmp/path.$i")
    [[ -f "$path" && -z "${seen[$path]:-}" ]] || fail 'nombre duplicado'
    seen[$path]=1
done
[[ $(<"$first") == 'NO TOCAR' && ! -e "$task_tmp/ausente" ]] || fail 'sobrescritura'
printf 'ok   datos: fallos de publicación, SIGKILL, reinicio y reservas concurrentes\n'
