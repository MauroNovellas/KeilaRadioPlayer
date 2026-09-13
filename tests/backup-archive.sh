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
BACKUP_TEST_COLLISION=0
ln() {
    if ((BACKUP_TEST_COLLISION)); then printf 'COPIA DE OTRA SESIÓN' > "${*: -1}"; fi
    command ln "$@"
}
config_load "$task_tmp/recordings" || fail configuración
favorites_init '' || fail inicio
favorites_add Original https://original.invalid || fail favorita
PLAYER_VOLUME=83 PLAYER_NAME=Sonando PLAYER_URL=https://sonando.invalid PLAYER_MUTED=1 ALARM_AT=123456
app_init_data() { fail 'la copia reinicializa la aplicación'; }
backup_create "$task_tmp/good.tar.gz" >/dev/null || fail creación
[[ $PLAYER_VOLUME == 83 && $PLAYER_NAME == Sonando && $PLAYER_MUTED == 1 && $ALARM_AT == 123456 ]] || fail 'crear altera audio o alarma'
[[ $(stat -c %a "$task_tmp/good.tar.gz") == 600 ]] || fail permisos
cp "$task_tmp/good.tar.gz" "$task_tmp/unchanged"
if backup_create "$task_tmp/good.tar.gz" >/dev/null 2>&1; then fail 'sobrescribe copia'; fi
cmp "$task_tmp/good.tar.gz" "$task_tmp/unchanged" || fail 'daña copia existente'
command ln -s "$task_tmp/absent" "$task_tmp/link.tar.gz"
if backup_create "$task_tmp/link.tar.gz" >/dev/null 2>&1; then fail 'sigue enlace roto'; fi
[[ ! -e "$task_tmp/absent" ]] || fail 'escribe mediante enlace'

# Colisión justo en la publicación, cuando la compresión ya terminó.
BACKUP_TEST_COLLISION=1
if backup_create "$task_tmp/collision.tar.gz" >/dev/null 2>&1; then fail 'ignora colisión'; fi
BACKUP_TEST_COLLISION=0
[[ $(<"$task_tmp/collision.tar.gz") == 'COPIA DE OTRA SESIÓN' ]] || fail 'borra copia ajena al fallar'

fixture="$task_tmp/fixture"
mkdir -p "$fixture"
tar -C "$fixture" -xzf "$task_tmp/good.tar.gz" || fail fixture
cp "$KEILA_FAVORITES_FILE" "$task_tmp/personal.original"
reject() {
    local archive=$1
    if backup_restore "$archive" >/dev/null 2>&1; then fail "acepta $archive"; fi
    cmp "$KEILA_FAVORITES_FILE" "$task_tmp/personal.original" || fail 'rechazo modifica datos'
}
printf roto > "$task_tmp/broken.tar.gz"
reject "$task_tmp/broken.tar.gz"
tar -C "$fixture" -czf "$task_tmp/duplicate.tar.gz" keila-backup keila-backup/config/favorites
reject "$task_tmp/duplicate.tar.gz"
tar -C "$fixture" --transform='s,keila-backup/config/favorites,../escape,' -czf "$task_tmp/traversal.tar.gz" keila-backup
reject "$task_tmp/traversal.tar.gz"
[[ ! -e "$task_tmp/escape" ]] || fail 'extrae fuera del temporal'
rm -- "$fixture/keila-backup/config/favorites"
ln -s "$task_tmp/personal.original" "$fixture/keila-backup/config/favorites"
tar -C "$fixture" -czf "$task_tmp/symlink.tar.gz" keila-backup
reject "$task_tmp/symlink.tar.gz"
rm -- "$fixture/keila-backup/config/favorites"
ln "$task_tmp/personal.original" "$fixture/keila-backup/config/favorites"
ln "$task_tmp/personal.original" "$fixture/keila-backup/config/labels"
tar -C "$fixture" -czf "$task_tmp/hardlink.tar.gz" keila-backup
reject "$task_tmp/hardlink.tar.gz"
rm -- "$fixture/keila-backup/config/favorites" "$fixture/keila-backup/config/labels"
truncate -s "$((BACKUP_MAX_MEMBER+1))" "$fixture/keila-backup/config/favorites"
tar -C "$fixture" -czf "$task_tmp/oversize.tar.gz" keila-backup
reject "$task_tmp/oversize.tar.gz"
rm -- "$fixture/keila-backup/config/favorites"
cp "$task_tmp/personal.original" "$fixture/keila-backup/config/favorites"
printf '0,0,0,0,0\nno permitido\n' > "$fixture/keila-backup/config/equalizer"
tar -C "$fixture" -czf "$task_tmp/invalid-data.tar.gz" keila-backup
reject "$task_tmp/invalid-data.tar.gz"

# La confirmación usa un snapshot privado e inmutable, no otra lectura del TAR.
mkdir "$task_tmp/prepared" "$task_tmp/restore-work"
backup_prepare "$task_tmp/good.tar.gz" "$task_tmp/prepared" || fail preparación
printf 'roto' > "$task_tmp/good.tar.gz"
favorites_add Segunda https://segunda.invalid || fail 'segunda favorita'
backup_restore_prepared "$task_tmp/prepared/tree/keila-backup" "$task_tmp/restore-work" >/dev/null || fail restauración
favorites_load
[[ ${#FAVORITE_URLS[@]} == 1 && ${FAVORITE_URLS[0]} == https://original.invalid ]] || fail 'no usa snapshot'
[[ -s "$task_tmp/restore-work/pre-restore" ]] || fail 'sin respaldo previo'
pre_restore=$(<"$task_tmp/restore-work/pre-restore")
mkdir "$task_tmp/previous"
backup_prepare "$pre_restore" "$task_tmp/previous" || fail 'respaldo previo ilegible'
[[ $(wc -l < "$task_tmp/previous/tree/keila-backup/config/favorites") == 2 ]] || fail 'respaldo previo no tiene el estado sustituido'

# Fallar la copia previa debe impedir incluso la primera escritura de restore.
favorites_add Tercera https://tercera.invalid || fail tercera
cp "$KEILA_FAVORITES_FILE" "$task_tmp/before-failure"
backup_publish_archive() { return 1; }
mkdir "$task_tmp/failed-work"
if backup_restore_prepared "$task_tmp/prepared/tree/keila-backup" "$task_tmp/failed-work" >/dev/null 2>&1; then fail 'restaura sin copia previa'; fi
cmp "$KEILA_FAVORITES_FILE" "$task_tmp/before-failure" || fail 'restaura pese al fallo previo'
printf 'ok   copias: no sobrescritura, snapshot, tipos/rutas/tamaños y respaldo obligatorio\n'
