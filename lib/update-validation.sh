#!/usr/bin/env bash

# Validación completa del árbol que se instalará mediante --update.
# Se carga después de lib/update.sh y redefine únicamente update_validate_tree
# para exigir todos los módulos que el launcher/TUI actual necesitan antes de
# modificar una instalación existente.

update_validate_tree() {
    local tree="$1" expected_version="$2"
    local file version
    local -a required_files=(
        keila-radio
        defaults/favorites
        README.md
        CHANGELOG.md
        lib/version.sh
        lib/update.sh
        lib/update-validation.sh
        lib/deps.sh
        lib/config.sh
        lib/lock.sh
        lib/state.sh
        lib/favorites.sh
        lib/stations.sh
        lib/search.sh
        lib/player.sh
        lib/recording.sh
        lib/input.sh
        lib/ui.sh
        lib/ui-responsive.sh
        lib/ui-safe-width.sh
        lib/ui-desktop.sh
        lib/ui-desktop-primary.sh
        lib/ui-desktop-balance.sh
        lib/ui-update-status.sh
        lib/ui-search.sh
        lib/app-search.sh
        lib/ui-desktop-search-pane.sh
    )

    for file in "${required_files[@]}"; do
        [[ -f "$tree/$file" ]] || {
            printf 'La actualización no contiene %s.\n' "$file" >&2
            return 1
        }
    done

    version=$(update_tree_version "$tree")
    [[ "$version" == "$expected_version" ]] || {
        printf 'La actualización declara la versión %s, esperaba %s.\n' \
            "${version:-desconocida}" "$expected_version" >&2
        return 1
    }

    bash -n "$tree/keila-radio" || return 1
    while IFS= read -r -d '' file; do
        bash -n "$file" || return 1
    done < <(find "$tree/lib" -maxdepth 1 -type f -name '*.sh' -print0)
}
