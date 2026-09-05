#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/update.sh"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: esperado '$expected', obtenido '$actual'"
}

assert_eq '-1' "$(update_compare_versions 2.0.0-rc1 2.0.0)" 'rc es anterior a estable'
assert_eq '1' "$(update_compare_versions 2.0.1 2.0.0)" 'patch superior'
assert_eq '-1' "$(update_compare_versions 2.1.0-beta2 2.1.0-rc1)" 'beta es anterior a rc'
assert_eq '1' "$(update_compare_versions 3.0.0-alpha1 2.9.9)" 'major superior prevalece'
assert_eq '0' "$(update_compare_versions v2.0.0-rc1 2.0.0-rc1)" 'prefijo v no cambia la versión'

stable_tags=$'v2.0.0-rc1\nv2.0.0\nv2.1.0-beta1\nv2.0.1'
assert_eq '2.0.1' "$(printf '%s\n' "$stable_tags" | update_select_latest 2.0.0)" 'canal estable ignora prereleases'

prerelease_tags=$'v2.0.0-rc1\nv2.0.0\nv2.1.0-beta1\nv2.1.0-rc2'
assert_eq '2.1.0-rc2' "$(printf '%s\n' "$prerelease_tags" | update_select_latest 2.0.0-rc1)" 'una rc puede seguir prereleases nuevas'

KEILA_VERSION='2.0.0-rc1'
KEILA_UPDATE_TAGS=$'v2.0.0-rc1'
result=$(update_check) || fail '--check-update falló con tags locales'
[[ "$result" == *'versión más reciente'* ]] || fail '--check-update no detectó versión actual'

printf 'ok   comprobación de actualizaciones\n'
