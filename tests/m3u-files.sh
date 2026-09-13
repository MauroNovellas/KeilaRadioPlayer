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
keila_init_paths; favorites_init
labels_path="$KEILA_CONFIG_DIR/labels"
favorites_add 'Original' https://radio.invalid/original || fail inicial
printf 'https://radio.invalid/original|Comentario privado\n' > "$labels_path"
comments=$(sha256sum "$labels_path")
mkdir "$task_tmp/preview" "$task_tmp/roundtrip"
printf '\357\273\277#EXTM3U\r\n#EXTINF:-1,Nuevo nombre\r\nhttps://radio.invalid/original\r\n#EXTINF:-1,Música, jazz\r\nhttps://radio.invalid/jazz?a=1&b=2\r\nhttps://radio.invalid/jazz?a=1&b=2\r\nfile:///tmp/no.mp3\r\nhttps://user:password@radio.invalid/live\r\n#EXTVLCOPT:ignored\r\nhttps://radio.invalid/plain' > "$task_tmp/input.m3u"
source_hash=$(sha256sum "$task_tmp/input.m3u")
m3u_prepare import "$task_tmp/input.m3u" "$task_tmp/preview" || fail preparar
[[ $(<"$task_tmp/preview/counts") == '3 1 2' ]] || fail conteos
m3u_import_commit "$task_tmp/preview/rows" || fail importar
[[ $M3U_ADDED == 2 && $M3U_DUPLICATES == 1 && ${#FAVORITE_URLS[@]} == 3 && ${FAVORITE_NAMES[0]} == Original && ${FAVORITE_NAMES[1]} == 'Música, jazz' ]] || fail 'fusión no destructiva'
[[ $(sha256sum "$labels_path") == "$comments" && $(sha256sum "$task_tmp/input.m3u") == "$source_hash" ]] || fail 'modifica comentarios o fuente'
before=$(sha256sum "$KEILA_FAVORITES_FILE")
m3u_import_commit "$task_tmp/preview/rows" || fail repetir
[[ $M3U_ADDED == 0 && $(sha256sum "$KEILA_FAVORITES_FILE") == "$before" ]] || fail 'importación no idempotente'
m3u_prepare export "$KEILA_FAVORITES_FILE" "$task_tmp/preview" || fail 'preparar exportación'
m3u_export_commit "$task_tmp/preview/rows" "$task_tmp/output.m3u" || fail exportar
[[ $(stat -c %a "$task_tmp/output.m3u") == 600 ]] || fail permisos
m3u_prepare import "$task_tmp/output.m3u" "$task_tmp/roundtrip" || fail 'leer exportación'
cmp -s "$KEILA_FAVORITES_FILE" "$task_tmp/roundtrip/rows" || fail 'ida y vuelta pierde nombres u orden'
export_hash=$(sha256sum "$task_tmp/output.m3u")
m3u_export_commit "$task_tmp/preview/rows" "$task_tmp/output.m3u" && fail sobrescritura
[[ $(sha256sum "$task_tmp/output.m3u") == "$export_hash" ]] || fail 'altera destino existente'
ln -s "$task_tmp/output.m3u" "$task_tmp/link.m3u"
m3u_prepare import "$task_tmp/link.m3u" "$task_tmp/preview" && fail 'lee enlace'
m3u_export_commit "$task_tmp/roundtrip/rows" "$task_tmp/link.m3u" && fail 'sobrescribe enlace'
mkfifo "$task_tmp/fifo"
m3u_prepare import "$task_tmp/fifo" "$task_tmp/preview" && fail 'acepta FIFO'
printf '#EXTM3U\n#EXT-X-TARGETDURATION:10\nhttps://radio.invalid/segment.ts\n' > "$task_tmp/hls"
m3u_prepare import "$task_tmp/hls" "$task_tmp/preview" && fail 'importa segmentos HLS'
printf '#EXTM3U\000https://radio.invalid/a\n' > "$task_tmp/binary"
m3u_prepare import "$task_tmp/binary" "$task_tmp/preview" && fail binario
head -c 262145 /dev/zero > "$task_tmp/large"
m3u_prepare import "$task_tmp/large" "$task_tmp/preview" && fail 'ignora límite de bytes'
for ((i=0;i<2001;i++)); do printf 'https://radio.invalid/%s\n' "$i"; done > "$task_tmp/many"
m3u_prepare import "$task_tmp/many" "$task_tmp/preview" && fail 'ignora límite de emisoras'
printf 'Nueva|https://radio.invalid/new\n' > "$task_tmp/rows"
BACKUP_DATA_BUSY=1
m3u_import_commit "$task_tmp/rows" && fail 'importa durante restauración'
BACKUP_DATA_BUSY=0
data_publish() { return 1; }
m3u_import_commit "$task_tmp/rows" && fail 'acepta escritura fallida'
[[ $(sha256sum "$KEILA_FAVORITES_FILE") == "$before" && ${#FAVORITE_URLS[@]} == 3 ]] || fail 'fallo pierde memoria o disco'
source "$ROOT_DIR/lib/data-safety.sh"
# Al confirmar se relee el destino bajo bloqueo: no se pierde una alta externa.
favorites_add Concurrente https://radio.invalid/concurrent
m3u_import_commit "$task_tmp/rows" || fail 'alta concurrente'
[[ $M3U_ADDED == 1 && ${#FAVORITE_URLS[@]} == 5 ]] || fail 'pierde cambios desde vista previa'
# Colisión creada justo antes del rename, no solo antes de abrir el diálogo.
mv() { printf 'Otro archivo\n' > "$task_tmp/race.m3u"; command mv "$@"; }
m3u_export_commit "$task_tmp/rows" "$task_tmp/race.m3u" && fail 'colisión durante publicación'
[[ $(<"$task_tmp/race.m3u") == 'Otro archivo' ]] || fail 'sobrescribe colisión'
unset -f mv
if compgen -G "$task_tmp/race.m3u.tmp.*" >/dev/null; then fail 'temporal abandonado tras fallo'; fi
printf 'ok   M3U: formato, límites, ida/vuelta, fusión atómica, colisiones y privacidad\n'
