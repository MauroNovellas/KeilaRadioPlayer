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

make_release() {
    local parent="$1" version="$2" launcher_version="$3"
    local root="$parent/KeilaRadioPlayer-$version"
    mkdir -p "$root/lib" "$root/defaults"
    cat > "$root/keila-radio" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
    --version) printf 'Keila Radio Player %s\\n' '$launcher_version' ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$root/keila-radio"
    printf 'KEILA_VERSION="%s"\n' "$version" > "$root/lib/version.sh"
    printf ':\n' > "$root/lib/update.sh"
    printf ':\n' > "$root/lib/player.sh"
    printf ':\n' > "$root/lib/ui.sh"
    printf 'Radio Test|https://example.invalid/test\n' > "$root/defaults/favorites"
    printf '# README\n' > "$root/README.md"
    printf '# CHANGELOG\n' > "$root/CHANGELOG.md"
}

make_install() {
    local install="$1" version="$2"
    mkdir -p "$install/lib" "$install/defaults" "$install/grabaciones"
    cat > "$install/keila-radio" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
    --version) printf 'Keila Radio Player %s\\n' '$version' ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$install/keila-radio"
    printf 'KEILA_VERSION="%s"\n' "$version" > "$install/lib/version.sh"
    printf 'contenido anterior\n' > "$install/lib/update.sh"
    printf 'favoritos anteriores\n' > "$install/defaults/favorites"
    printf 'grabación que debe sobrevivir\n' > "$install/grabaciones/conservar.txt"
}

tmp=$(mktemp -d) || fail 'no se pudo crear temporal'
trap 'rm -rf "$tmp"' EXIT

# Actualización válida: instala código nuevo y conserva datos ajenos al programa.
release_parent="$tmp/good-release"
mkdir -p "$release_parent"
make_release "$release_parent" '2.0.1' '2.0.1'
tar -czf "$tmp/good.tar.gz" -C "$release_parent" 'KeilaRadioPlayer-2.0.1'

install_good="$tmp/install-good"
make_install "$install_good" '2.0.0'
KEILA_VERSION='2.0.0'
KEILA_UPDATE_TAGS=$'v2.0.1'
KEILA_UPDATE_ARCHIVE_FILE="$tmp/good.tar.gz"
update_install "$install_good" >/dev/null || fail 'la actualización válida falló'
assert_eq 'Keila Radio Player 2.0.1' "$(bash "$install_good/keila-radio" --version)" 'versión instalada'
[[ -f "$install_good/grabaciones/conservar.txt" ]] || fail 'la actualización borró grabaciones'
[[ ! -d "$install_good/.keila-update.test" ]] || fail 'quedó un temporal inesperado'

# Actualización defectuosa: el árbol declara 2.0.1 pero el launcher no la confirma.
# Debe fallar el postcheck y restaurar automáticamente la instalación anterior.
bad_parent="$tmp/bad-release"
mkdir -p "$bad_parent"
make_release "$bad_parent" '2.0.1' '9.9.9'
tar -czf "$tmp/bad.tar.gz" -C "$bad_parent" 'KeilaRadioPlayer-2.0.1'

install_bad="$tmp/install-bad"
make_install "$install_bad" '2.0.0'
KEILA_VERSION='2.0.0'
KEILA_UPDATE_TAGS=$'v2.0.1'
KEILA_UPDATE_ARCHIVE_FILE="$tmp/bad.tar.gz"
if update_install "$install_bad" >/dev/null 2>&1; then
    fail 'una actualización defectuosa fue aceptada'
fi
assert_eq 'Keila Radio Player 2.0.0' "$(bash "$install_bad/keila-radio" --version)" 'rollback restauró versión anterior'
[[ -f "$install_bad/grabaciones/conservar.txt" ]] || fail 'rollback perdió grabaciones'

printf 'ok   comprobación, instalación y rollback de actualizaciones\n'
