#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Coste del mantenimiento local: sin red, decodificación ni datos personales.
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/lib/station-logo-cache.sh"
task_tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
cache=$task_tmp/$'logos con espacio\ny salto'
mkdir "$cache"
for ((index=1; index<=64; index++)); do
    printf -v key '%064x' "$index"
    printf 'fixture\n' > "$cache/$key.check"
    if ((index <= 16)); then printf 'fixture\n' > "$cache/$key.logo"; fi
done
incoming=$key
# No confundir dos archivos de una emisora con dos emisoras; no tocar ajenos.
printf 'personal\n' > "$cache/personal.txt"
printf -v linked '%064x' 90
ln -s "$cache/personal.txt" "$cache/$linked.logo"
stat() {
    printf 'call\n' >> "$task_tmp/stat-calls"
    command stat "$@"
}
start=${EPOCHREALTIME//[.,]/}
for ((frame=0; frame<10; frame++)); do logo_cache_prune "$cache" "$incoming"; done
finish=${EPOCHREALTIME//[.,]/}
printf 'Caché con 64 emisoras: %d us/mantenimiento\n' "$(((finish-start)/10))"
calls=()
[[ ! -f $task_tmp/stat-calls ]] || mapfile -t calls < "$task_tmp/stat-calls"
printf 'Consultas stat sin desbordamiento: %d\n' "${#calls[@]}"
((${#calls[@]} == 0)) || fail 'consulta fechas sin necesitar evicción'

# Al superar el límite, contar la fecha más reciente de logo/check. El RGB
# antiguo de una emisora que acaba de fallar no convierte la entrada en vieja.
printf -v oldest '%064x' 1
printf -v second '%064x' 2
touch -d '3 days ago' "$cache/$oldest.logo"
touch -d '4 days ago' "$cache/$incoming.check"
touch -d '2 days ago' "$cache/$second.logo" "$cache/$second.check"
printf 'sixel\n' > "$cache/$second.sixel"
printf -v extra '%064x' 65
printf 'fixture\n' > "$cache/$extra.check"
start=${EPOCHREALTIME//[.,]/}
logo_cache_prune "$cache" "$incoming"
finish=${EPOCHREALTIME//[.,]/}
printf 'Evicción de una emisora: %d us\n' "$((finish-start))"
mapfile -t calls < "$task_tmp/stat-calls"
((${#calls[@]} == 1)) || fail 'no agrupa las fechas en una única consulta'
[[ ! -e $cache/$second.logo && ! -e $cache/$second.check && ! -e $cache/$second.sixel ]] || fail 'no retira auxiliares de la más antigua'
[[ -f $cache/$oldest.logo && -f $cache/$incoming.check && -f $cache/$extra.check && -f $cache/personal.txt && -L $cache/$linked.logo ]] || fail 'evicción cambia emisora reciente/entrante o archivos ajenos'
printf 'ok   límite de caché y mantenimiento local\n'
