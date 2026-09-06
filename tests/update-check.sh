#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/version.sh"
SOURCE_VERSION="$KEILA_VERSION"
source "$ROOT_DIR/lib/update.sh"
source "$ROOT_DIR/lib/update-validation.sh"

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

launcher_result=$(KEILA_UPDATE_TAGS="v$SOURCE_VERSION" bash "$ROOT_DIR/keila-radio" --update) || fail '--update no se despacha desde el launcher'
[[ "$launcher_result" == *'versión más reciente'* ]] || fail '--update no llegó al motor de actualización'
[[ "$launcher_result" != *'todavía no está habilitada'* ]] || fail 'sigue activo el placeholder antiguo de --update'

make_release() {
    local parent="$1" version="$2" launcher_version="$3"
    local root="$parent/KeilaRadioPlayer-$version"
    local module
    local -a runtime_modules=(
        update.sh
        update-validation.sh
        deps.sh
        config.sh
        lock.sh
        state.sh
        personal.sh
        navigation.sh
        catalog-startup.sh
        label-editor.sh
        equalizer.sh
        equalizer-editor.sh
        spectrum.sh
        favorites.sh
        stations.sh
        search.sh
        player.sh
        player-failure.sh
        player-events.sh
        recording.sh
        diagnostics.sh
        input.sh
        ui.sh
        ui-responsive.sh
        ui-safe-width.sh
        ui-desktop.sh
        ui-desktop-primary.sh
        ui-desktop-balance.sh
        ui-update-status.sh
        ui-search.sh
        app-search.sh
        app-reconnect.sh
        app-reconnect-failure.sh
        ui-desktop-search-pane.sh
        ui-terminal-guard.sh
    )

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
    for module in "${runtime_modules[@]}"; do
        printf ':\n' > "$root/lib/$module"
    done
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

# Paquete incompleto: debe rechazarse durante la validación, antes de mover
# ningún componente de la instalación actual. El cliente persistente de eventos
# forma ya parte obligatoria del runtime de 2.1.
incomplete_parent="$tmp/incomplete-release"
mkdir -p "$incomplete_parent"
make_release "$incomplete_parent" '2.0.1' '2.0.1'
rm -f "$incomplete_parent/KeilaRadioPlayer-2.0.1/lib/player-events.sh"
tar -czf "$tmp/incomplete.tar.gz" -C "$incomplete_parent" 'KeilaRadioPlayer-2.0.1'

install_incomplete="$tmp/install-incomplete"
make_install "$install_incomplete" '2.0.0'
KEILA_VERSION='2.0.0'
KEILA_UPDATE_TAGS=$'v2.0.1'
KEILA_UPDATE_ARCHIVE_FILE="$tmp/incomplete.tar.gz"
if update_install "$install_incomplete" >/dev/null 2>&1; then
    fail 'un paquete incompleto fue aceptado'
fi
assert_eq 'Keila Radio Player 2.0.0' "$(bash "$install_incomplete/keila-radio" --version)" 'validación previa conservó versión anterior'
[[ -f "$install_incomplete/grabaciones/conservar.txt" ]] || fail 'validación previa perdió grabaciones'

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

printf 'ok   comprobación, validación completa, instalación y rollback de actualizaciones\n'
