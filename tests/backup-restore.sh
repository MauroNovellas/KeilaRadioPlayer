#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap - EXIT

config_load "$task_tmp/recordings" || fail config
favorites_init '' || fail favoritos
favorites_add 'Radio Uno' 'https://radio.invalid/uno' || fail favorito
labels_set 'https://radio.invalid/uno' 'Noticias' || fail comentario
history_record 'Radio Uno' 'https://radio.invalid/uno' || fail historial
STATE_VOLUME=77
STATE_LAST_NAME='Radio Uno'
STATE_LAST_URL='https://radio.invalid/uno'
state_save || fail estado
PREF_AUTOPLAY=0
preferences_save || fail preferencias
EQUALIZER_GAINS=(1 2 3 4 5)
equalizer_save || fail ecualizador

backup_file="$task_tmp/keila.tar.gz"
backup_create "$backup_file" >/dev/null || fail backup
[[ -f "$backup_file" ]] || fail 'no creó archivo'
listing=$(tar -tzf "$backup_file") || fail 'backup ilegible'
[[ "$listing" == *'keila-backup/config/favorites'* ]] || fail 'falta favoritos'
[[ "$listing" == *'keila-backup/config/labels'* ]] || fail 'falta comentarios'
[[ "$listing" == *'keila-backup/state/history'* ]] || fail 'falta historial'
[[ "$listing" != *'radio.tsv'* && "$listing" != *'grabaciones'* ]] || fail 'incluye caché o grabaciones'

favorites_add 'Radio Dos' 'https://radio.invalid/dos' || fail 'modificar favoritos'
labels_set 'https://radio.invalid/uno' 'Cambiado' || fail 'modificar comentario'
STATE_VOLUME=12
state_save || fail 'modificar estado'
PREF_AUTOPLAY=1
preferences_save || fail 'modificar preferencias'
EQUALIZER_GAINS=(0 0 0 0 0)
equalizer_save || fail 'modificar ecualizador'

backup_restore "$backup_file" >/dev/null || fail restore
favorites_load
labels_load
history_load
state_load
preferences_load
equalizer_load

[[ ${#FAVORITE_URLS[@]} == 1 && "${FAVORITE_URLS[0]}" == 'https://radio.invalid/uno' ]] || fail 'favoritos no restaurados'
[[ "${FAVORITE_LABELS[https://radio.invalid/uno]}" == 'Noticias' ]] || fail 'comentario no restaurado'
[[ "$STATE_VOLUME" == 77 && "$STATE_LAST_NAME" == 'Radio Uno' ]] || fail 'estado no restaurado'
[[ "$PREF_AUTOPLAY" == 0 ]] || fail 'preferencias no restauradas'
[[ "${EQUALIZER_GAINS[*]}" == '1 2 3 4 5' ]] || fail 'ecualizador no restaurado'
compgen -G "$KEILA_CONFIG_DIR/pre-restore-*.tar.gz" >/dev/null || fail 'falta respaldo previo'

bad_parent="$task_tmp/bad"
mkdir -p "$bad_parent/keila-backup/config"
printf 'format=keila-backup-v1\n' > "$bad_parent/keila-backup/manifest"
printf 'mal\n' > "$bad_parent/keila-backup/config/favorites"
tar -C "$bad_parent" -czf "$task_tmp/bad.tar.gz" keila-backup
if backup_restore "$task_tmp/bad.tar.gz" >/dev/null 2>&1; then fail 'restauró copia inválida'; fi

printf 'ok   backup/restore: exporta datos, valida y respalda antes de restaurar\n'
