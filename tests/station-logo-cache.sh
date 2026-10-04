#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'logo_cleanup >/dev/null; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
keila_init_paths || fail rutas
url=https://radio.invalid/cache
pixels=$(printf '%036864d' 0); pixels=${pixels//0/A}
white_pixels=${pixels//A//}
hex=$(printf '%0864d' 0); white_hex=${hex//0/f}
printf 'keila-logo-v1\n%s\n%s\n' "$pixels" "$hex" > "$task_tmp/black.logo"
printf 'keila-logo-v1\n%s\n%s\n' "$white_pixels" "$white_hex" > "$task_tmp/white.logo"
logo_cache_key "$url" || fail clave
key=$LOGO_CACHE_KEY cache=$KEILA_CACHE_DIR/logos
mkdir "$cache"
cp "$task_tmp/black.logo" "$cache/$key.logo"
logo_choose_backend() { LOGO_BACKEND=blocks; }
player_is_running() { return 0; }
unset PREFIX TERMUX_VERSION
TERM=xterm-256color UI_COLS=132 UI_LINES=30 UI_COLOR=1 UI_UNICODE=1 PREF_LOGO=1 PLAYER_PID=$$ PLAYER_NAME=Radio PLAYER_URL=$url
LOGO_WORKER=$ROOT_DIR/tests/fixtures/logo-slow-worker.sh
logo_poll || fail 'primer hit'
[[ -z $LOGO_PID && $LOGO_READY_URL == "$url" && $LOGO_PIXELS_BASE64 == "$pixels" && ${#LOGO_ROWS[@]} == 6 ]] || fail 'hit fresco espera trabajo o catálogo'
generation=$LOGO_GENERATION
LOGO_CATALOG_GENERATION=$((LOGO_CATALOG_GENERATION+1))
logo_poll || fail 'revisar catálogo'
[[ $LOGO_GENERATION == "$generation" && -z $LOGO_PID ]] || fail 'nuevo catálogo repite imagen/trabajo fresco'
for ((i=0; i<100; i++)); do logo_poll && fail 'tick repite hit'; done

# Una copia antigua aparece antes de terminar la actualización y permanece
# cuando el trabajo falla/interrumpe, sin incrementar generación ni parpadear.
touch -d '2 days ago' "$cache/$key.logo"
printf '[]\n' > "$KEILA_STATIONS_JSON"
LOGO_REQUEST=''
logo_poll || fail 'revisión antigua'
[[ -n $LOGO_PID && $LOGO_READY_URL == "$url" && $LOGO_PIXELS_BASE64 == "$pixels" && $LOGO_GENERATION == "$generation" ]] || fail 'oculta copia antigua mientras actualiza'
old_job=$LOGO_JOB
for ((i=0; i<100; i++)); do [[ ! -f $old_job/child ]] || break; sleep .01; done
[[ -f $old_job/child ]] || fail 'actualización no empieza'
player_terminate_group_bounded "$LOGO_PID" "$LOGO_PID" >/dev/null || fail 'cerrar tarea de prueba'
LOGO_CHECK_AT=0
logo_poll || fail 'resultado interrumpido'
[[ -z $LOGO_PID && ! -e $old_job && $LOGO_READY_URL == "$url" && $LOGO_PIXELS_BASE64 == "$pixels" && $LOGO_GENERATION == "$generation" ]] || fail 'fallo pierde copia o trabajo'
[[ $LOGO_STATUS == *'no se pudo actualizar'* ]] || fail 'no indica actualización fallida'
logo_accept_render "$task_tmp/black.logo" '' || fail adoptar
[[ $LOGO_GENERATION == "$generation" ]] || fail 'imagen idéntica provoca parpadeo'
logo_accept_render "$task_tmp/white.logo" '' || fail 'adoptar logo distinto'
[[ $LOGO_GENERATION == "$((generation+1))" && $LOGO_PIXELS_BASE64 == "$white_pixels" ]] || fail 'logo nuevo no se muestra'
printf 'keila-logo-v1\n\033[2J\n00\n' > "$task_tmp/corrupt"
logo_accept_render "$task_tmp/corrupt" '' && fail 'acepta imagen corrupta'
[[ $LOGO_PIXELS_BASE64 == "$white_pixels" ]] || fail 'fallo de validación altera imagen'
logo_cleanup >/dev/null

# Worker controlado sin red ni ffmpeg: se descargan únicamente misses/revisiones
# vencidas. Un intento fallido conserva RGB; los siguientes respetan el plazo.
cache=$task_tmp/worker-cache
mkdir "$cache"
fetches=0 broken=0
# El catálogo se recoge por sustitución de comando: registrar también consultas
# fuera de ese subshell, sin depender de un contador en memoria.
logo_catalog_candidates() { printf x >> "$task_tmp/queries"; printf 'I\thttps://logo.invalid/image.png\n'; }
logo_fetch() { fetches=$((fetches+1)); ((broken == 0)); }
logo_convert() { cp "$task_tmp/white.logo" "$1/result" && logo_read_render "$1/result"; }
ffmpeg() { fail 'vuelve a decodificar una imagen guardada'; }
mkdir "$task_tmp/first"
logo_worker "$url" "$KEILA_STATIONS_JSON" "$cache" "$task_tmp/first" Radio || fail 'primera descarga'
[[ $fetches == 1 && $(<"$task_tmp/queries") == x && ! -e $cache/$key.check ]] || fail 'primera descarga o intento no cerrado'
[[ $(stat -c %a "$cache/$key.logo") == 600 ]] || fail permisos
mkdir "$task_tmp/fresh"
logo_worker "$url" '' "$cache" "$task_tmp/fresh" Radio || fail 'cache offline'
[[ $fetches == 1 && $(<"$task_tmp/queries") == x ]] || fail 'hit busca o descarga de nuevo'
touch -d '2 days ago' "$cache/$key.logo"
checksum=$(cksum "$cache/$key.logo") age=$(stat -c %Y "$cache/$key.logo")
broken=1
mkdir "$task_tmp/failure"
logo_worker "$url" "$KEILA_STATIONS_JSON" "$cache" "$task_tmp/failure" Radio && fail 'fallo no indicado'
[[ $fetches == 2 && $(<"$task_tmp/queries") == xx && $(cksum "$cache/$key.logo") == "$checksum" ]] || fail 'fallo borra imagen o repite candidatos'
cmp -s "$cache/$key.logo" "$task_tmp/failure/result" || fail 'no publica copia anterior en fallo'
logo_cache_read_check "$cache/$key.check" || fail 'no conserva plazo de fallo'
[[ $LOGO_CACHE_REASON == 'No se pudo descargar el logo' && $(stat -c %a "$cache/$key.check") == 600 ]] || fail 'motivo o permisos'
mkdir "$task_tmp/backoff"
logo_worker "$url" "$KEILA_STATIONS_JSON" "$cache" "$task_tmp/backoff" Radio || fail 'reutilizar durante reintento aplazado'
[[ $fetches == 2 && $(<"$task_tmp/queries") == xx ]] || fail 'ignora plazo de reintento'

# La geometría utiliza solo el RGB. Guardar SIXEL no rejuvenece la imagen ni
# borra su backoff. Reabrir con el mismo tamaño no recodifica siquiera SIXEL.
mkdir "$task_tmp/render"
logo_worker "$url" '' "$cache" "$task_tmp/render" Radio 60 render || fail 'preparación local de foot'
python3 "$ROOT_DIR/tests/fixtures/check-sixel.py" "$task_tmp/render/sixel" "$task_tmp/render/rgb" 60 || fail 'píxeles de SIXEL cacheado'
[[ -f $cache/$key.sixel && $(stat -c %a "$cache/$key.sixel") == 600 && $(stat -c %Y "$cache/$key.logo") == "$age" ]] || fail 'SIXEL o edad persistente'
logo_cache_read_check "$cache/$key.check" || fail 'resize borra reintento'
(
    logo_prepare_sixel() { fail 'repite codificación SIXEL cacheada'; }
    mkdir "$task_tmp/render-hit"
    logo_worker "$url" '' "$cache" "$task_tmp/render-hit" Radio 60 render || fail 'hit SIXEL'
    cmp -s "$task_tmp/render/sixel" "$task_tmp/render-hit/sixel" || fail 'SIXEL distinto'
) || fail 'reutilización SIXEL'
[[ $fetches == 2 && $(<"$task_tmp/queries") == xx ]] || fail 'resize consulta red/catalogo'
logo_read_render "$task_tmp/black.logo" || fail 'cargar otro RGB'
logo_cache_read_sixel "$cache/$key.sixel" 60 && fail 'SIXEL no ligado a sus píxeles'
logo_read_render "$cache/$key.logo" || fail 'restaurar RGB'
logo_cache_read_sixel "$cache/$key.sixel" 96 && fail 'SIXEL de otra geometría'

# Al volver a abrir Keila: caché válida visible desde el primer poll, incluso sin
# ffmpeg ni catálogo y sin un job para volver a codificar/subir desde el servidor.
touch "$cache/$key.logo"
mkdir -p "$task_tmp/restart/logos"
cp "$cache/$key.logo" "$cache/$key.sixel" "$task_tmp/restart/logos/"
fresh=$(bash -c '
    launcher=$1; cache=$2; url=$3; set -- --version; source "$launcher" >/dev/null
    trap "logo_cleanup >/dev/null" EXIT
    KEILA_CACHE_DIR=$cache; PLAYER_URL=$url; PLAYER_PID=$$; PLAYER_NAME=Radio
    PREF_LOGO=1 UI_COLS=132 UI_LINES=30 UI_COLOR=1 UI_UNICODE=1 TERM=foot
    unset PREFIX TERMUX_VERSION
    player_is_running() { return 0; }
    logo_prepare_backend() { LOGO_BACKEND=sixel LOGO_SIXEL_SIDE=60; return 0; }
    LOGO_WORKER=/worker-que-no-se-debe-lanzar
    logo_poll || { printf "FAIL poll al reiniciar: %s\n" "$LOGO_STATUS" >&2; exit 1; }
    [[ $LOGO_READY_URL == "$url" && -z $LOGO_PID && -n $LOGO_SIXEL_BODY ]] || {
        printf "FAIL reinicio: %s; cache=%s; listo=%s; trabajo=%s; sixel=%s\n" "$LOGO_STATUS" "$KEILA_CACHE_DIR" "$LOGO_READY_URL" "$LOGO_PID" "${#LOGO_SIXEL_BODY}" >&2
        exit 2
    }
    printf listo
' bash "$ROOT_DIR/keila-radio" "$task_tmp/restart" "$url") || fail 'reinicio con logo persistente'
[[ $fresh == listo ]] || fail 'nuevo proceso no lee caché'

# Tras vencer el plazo, una actualización correcta sustituye la copia y cierra
# el backoff. El SIXEL de la versión anterior no puede usarse con el RGB nuevo.
touch -d '2 days ago' "$cache/$key.logo"
printf 'keila-logo-check-v1\n%s\n3600\nNo se pudo descargar el logo\n' "$((EPOCHSECONDS-3601))" > "$cache/$key.check"
broken=0
logo_convert() { cp "$task_tmp/black.logo" "$1/result" && logo_read_render "$1/result"; }
mkdir "$task_tmp/refreshed"
logo_worker "$url" "$KEILA_STATIONS_JSON" "$cache" "$task_tmp/refreshed" Radio || fail 'revisión positiva'
cmp -s "$cache/$key.logo" "$task_tmp/black.logo" || fail 'no sustituye logo actualizado'
[[ $fetches == 3 && $(<"$task_tmp/queries") == xxx && ! -e $cache/$key.check ]] || fail 'revisión no cierra backoff'
logo_cache_is_fresh "$cache/$key.logo" || fail 'revisión no renueva fecha'
logo_cache_read_sixel "$cache/$key.sixel" 60 && fail 'mezcla RGB nuevo y SIXEL anterior'

# Ausencia de logo también se recuerda. Un catálogo vacío no se recorre de
# nuevo en cada visita; expiración o reloj atrasado nunca bloquean para siempre.
logo_catalog_candidates() { printf n >> "$task_tmp/queries"; }
missing=https://radio.invalid/missing
logo_cache_key "$missing"; missing_key=$LOGO_CACHE_KEY
mkdir "$task_tmp/no-logo" "$task_tmp/no-logo-hit"
logo_worker "$missing" "$KEILA_STATIONS_JSON" "$cache" "$task_tmp/no-logo" Radio && fail 'inventa logo'
logo_worker "$missing" "$KEILA_STATIONS_JSON" "$cache" "$task_tmp/no-logo-hit" Radio && fail 'inventa hit negativo'
[[ $(<"$task_tmp/queries") == xxxn && $fetches == 3 ]] || fail 'repite consulta negativa'
logo_cache_read_check "$cache/$missing_key.check" || fail 'plazo negativo'
printf 'keila-logo-check-v1\n%s\n86400\nNo hay candidato seguro en el catálogo\n' "$((EPOCHSECONDS-86401))" > "$cache/$missing_key.check"
logo_cache_read_check "$cache/$missing_key.check" && fail 'plazo expirado activo'
printf 'keila-logo-check-v1\n%s\n3600\nComprobación pendiente\n' "$((EPOCHSECONDS+100))" > "$cache/$missing_key.check"
logo_cache_read_check "$cache/$missing_key.check" && fail 'reloj atrás bloquea logo'
printf 'keila-logo-check-v1\n0\n86400\n\033[2J\n' > "$task_tmp/check-corrupt"
logo_cache_read_check "$task_tmp/check-corrupt" && fail 'acepta controles de metadatos'
ln -s "$cache/$key.sixel" "$task_tmp/frame-link"
logo_cache_read_sixel "$task_tmp/frame-link" 60 && fail 'SIXEL sigue enlace'

# Un límite conjunto, sin retirar otras entradas cuando se renueva la misma.
for ((i=1; i<=62; i++)); do
    printf -v name '%064x' "$i"
    printf 'keila-logo-check-v1\n%s\n3600\nComprobación pendiente\n' "$EPOCHSECONDS" > "$cache/$name.check"
done
printf -v oldest '%064x' 1
touch -d '10 days ago' "$cache/$oldest.check"
printf auxiliar > "$cache/$oldest.sixel"
printf conservar > "$cache/personal.txt"
printf -v incoming '%064x' 999
logo_cache_check_store "$cache" "$incoming" 'Comprobación pendiente' || fail 'nuevo negativo'
[[ ! -e $cache/$oldest.check && ! -e $cache/$oldest.sixel && $(<"$cache/personal.txt") == conservar ]] || fail 'evicción incompleta o archivo ajeno'
entries=("$cache"/*.check)
[[ ${#entries[@]} == 63 && -f $cache/$key.logo ]] || fail 'límite total no es 64'
logo_cache_store "$cache" "$key" "$task_tmp/white.logo" "$task_tmp/render/sixel" || fail 'renovar existente'
[[ -f $cache/$incoming.check && $(<"$cache/personal.txt") == conservar ]] || fail 'renovar expulsa otra emisora'
printf 'ok   logos persistentes: hit inmediato, revisión sin parpadeo, offline/backoff, SIXEL ligado al RGB y límite conjunto\n'
