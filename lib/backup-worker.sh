#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Proceso aislado, sin radio propia. Lo inicia el gestor con setsid.
set -uo pipefail
worker_action=${1:-} worker_dir=${2:-} worker_argument=${3:-}
[[ -d "$worker_dir" && ! -L "$worker_dir" ]] || exit 2
worker_base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
set -- --version
source "$worker_base/keila-radio" >/dev/null
trap - EXIT INT TERM
umask 077
mkdir -p -- "$worker_dir/tmp" || exit 1
export TMPDIR="$worker_dir/tmp"
worker_status=0
case "$worker_action" in
    scan)
        (
            shopt -s nullglob
            for directory in "$KEILA_STATE_DIR/backups" "$KEILA_CONFIG_DIR" "$BASE_DIR"; do
                [[ -d "$directory" && ! -L "$directory" ]] || continue
                for file in "$directory"/*.tar.gz; do
                    [[ -f "$file" && ! -L "$file" ]] || continue
                    if [[ "$directory" == "$KEILA_CONFIG_DIR" ]]; then [[ "${file##*/}" == pre-restore-* ]] || continue; fi
                    if [[ "$directory" == "$BASE_DIR" ]]; then [[ "${file##*/}" == keila-backup-* ]] || continue; fi
                    info=$(stat -c $'%Y\t%s\t%y' -- "$file") || continue
                    printf '%s\t%s\0' "$info" "$file"
                done
            done
        ) | LC_ALL=C sort -z -t $'\t' -k1,1nr > "$worker_dir/files" || worker_status=1
        ;;
    create)
        directory="$KEILA_STATE_DIR/backups"
        mkdir -p -- "$directory" && [[ ! -L "$directory" ]] && chmod 700 "$directory" || worker_status=1
        if ((worker_status == 0)); then
            output=$(backup_next_file "$directory" "keila-backup-$(backup_timestamp)") || worker_status=1
        fi
        if ((worker_status == 0)); then
            backup_create "$output" || worker_status=1
            ((worker_status)) || printf '%s\n' "$output" > "$worker_dir/created"
        fi
        ;;
    prepare)
        backup_signature "$worker_argument" > "$worker_dir/signature" || worker_status=1
        if ((worker_status == 0)); then backup_prepare "$worker_argument" "$worker_dir" || worker_status=1; fi
        ;;
    restore)
        backup_restore_prepared "$worker_argument/tree/keila-backup" "$worker_dir" || worker_status=1
        ;;
    *) worker_status=2 ;;
esac
printf '%s\n' "$worker_status" > "$worker_dir/result.tmp"
mv -T -- "$worker_dir/result.tmp" "$worker_dir/result"
exit "$worker_status"
