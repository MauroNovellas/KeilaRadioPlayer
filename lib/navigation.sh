#!/usr/bin/env bash

# Selección conjunta; los presets y las acciones de borrado siguen siendo favoritos.
RECENT_NAMES=()
RECENT_URLS=()
UI_RECENT_SCROLL=0
UI_NAV_FAVORITES_HEIGHT=0
UI_NAV_RECENTS_HEIGHT=0

ui_navigation_refresh() {
    if declare -F history_recent_refresh >/dev/null; then history_recent_refresh; fi
    UI_NAV_COUNT=$((${#FAVORITE_NAMES[@]} + ${#RECENT_NAMES[@]}))
}

ui_navigation_sync() {
    local height="$1" count favorite_count=${#FAVORITE_NAMES[@]} recent_count=${#RECENT_NAMES[@]}
    count=$((favorite_count + recent_count))
    ((UI_SELECTED_INDEX < 0)) && UI_SELECTED_INDEX=0
    ((UI_SELECTED_INDEX >= count)) && UI_SELECTED_INDEX=$((count > 0 ? count - 1 : 0))
    UI_NAV_FAVORITES_HEIGHT=$height
    UI_NAV_RECENTS_HEIGHT=0
    UI_NAV_RECENT_HEADER=0
    if ((recent_count > 0 && height >= 3)); then
        UI_NAV_RECENT_HEADER=1
        UI_NAV_RECENTS_HEIGHT=$((height / 3))
        ((UI_NAV_RECENTS_HEIGHT > recent_count)) && UI_NAV_RECENTS_HEIGHT=$recent_count
        ((favorite_count == 0)) && UI_NAV_RECENTS_HEIGHT=$((height - 1))
        UI_NAV_FAVORITES_HEIGHT=$((height - UI_NAV_RECENTS_HEIGHT - 1))
    elif ((recent_count > 0 && UI_SELECTED_INDEX >= favorite_count)); then
        # En una o dos filas, mostrar la sección que tiene el foco.
        UI_NAV_FAVORITES_HEIGHT=0
        UI_NAV_RECENT_HEADER=$((height > 1 ? 1 : 0))
        UI_NAV_RECENTS_HEIGHT=$((height - UI_NAV_RECENT_HEADER))
    fi
    local selected=$UI_SELECTED_INDEX max_scroll
    if ((selected < favorite_count)); then
        ((selected < UI_SCROLL_OFFSET)) && UI_SCROLL_OFFSET=$selected
        ((selected >= UI_SCROLL_OFFSET + UI_NAV_FAVORITES_HEIGHT)) && UI_SCROLL_OFFSET=$((selected - UI_NAV_FAVORITES_HEIGHT + 1))
    elif ((UI_NAV_RECENTS_HEIGHT > 0)); then
        selected=$((selected - favorite_count))
        ((selected < UI_RECENT_SCROLL)) && UI_RECENT_SCROLL=$selected
        ((selected >= UI_RECENT_SCROLL + UI_NAV_RECENTS_HEIGHT)) && UI_RECENT_SCROLL=$((selected - UI_NAV_RECENTS_HEIGHT + 1))
    fi
    max_scroll=$((favorite_count - UI_NAV_FAVORITES_HEIGHT))
    ((max_scroll < 0)) && max_scroll=0
    ((UI_SCROLL_OFFSET > max_scroll)) && UI_SCROLL_OFFSET=$max_scroll
    ((UI_SCROLL_OFFSET < 0)) && UI_SCROLL_OFFSET=0
    max_scroll=$((recent_count - UI_NAV_RECENTS_HEIGHT))
    ((max_scroll < 0)) && max_scroll=0
    ((UI_RECENT_SCROLL > max_scroll)) && UI_RECENT_SCROLL=$max_scroll
    ((UI_RECENT_SCROLL < 0)) && UI_RECENT_SCROLL=0
    return 0
}

ui_navigation_row() {
    local row="$1" index url name label='' preset='' marker='  '
    UI_NAV_TEXT='' UI_NAV_BADGE='' UI_NAV_STYLE='' UI_NAV_BADGE_STYLE='' UI_NAV_SELECTED=0
    if ((UI_NAV_RECENT_HEADER > 0 && row == UI_NAV_FAVORITES_HEIGHT)); then
        UI_NAV_TEXT="RECIENTES (${#RECENT_NAMES[@]})"
        UI_NAV_STYLE=accent
        return 0
    elif ((row < UI_NAV_FAVORITES_HEIGHT)); then
        index=$((UI_SCROLL_OFFSET + row))
        ((index < ${#FAVORITE_NAMES[@]})) || return 0
        name="${FAVORITE_NAMES[index]}" url="${FAVORITE_URLS[index]}"
        if declare -p FAVORITE_LABELS >/dev/null 2>&1; then label="${FAVORITE_LABELS[$url]:-}"; fi
        case "$index" in
            [0-8]) preset="$((index + 1)). " ;;
            9) preset='0. ' ;;
            *) preset='   ' ;;
        esac
    else
        index=$((UI_RECENT_SCROLL + row - UI_NAV_FAVORITES_HEIGHT - UI_NAV_RECENT_HEADER))
        ((index >= 0 && index < ${#RECENT_NAMES[@]})) || return 0
        name="${RECENT_NAMES[index]}" url="${RECENT_URLS[index]}"
        index=$((index + ${#FAVORITE_NAMES[@]}))
    fi
    if ((index == UI_SELECTED_INDEX && !${SEARCH_ACTIVE:-0})); then
        marker="$UI_SELECT " UI_NAV_SELECTED=1
    fi
    if player_is_running && [[ "$url" == "$PLAYER_URL" ]]; then
        UI_NAV_STYLE=playing UI_NAV_BADGE_STYLE=playing UI_NAV_BADGE='[PLAY]'
        [[ "$marker" == '  ' ]] && marker="$UI_PLAY "
    elif [[ "$url" == "${STATE_LAST_URL:-}" ]]; then
        UI_NAV_BADGE='[ÚLTIMA]' UI_NAV_BADGE_STYLE=muted
    fi
    if [[ -n "$label" ]]; then
        UI_NAV_BADGE="$label ${UI_NAV_BADGE}"
        [[ -n "$UI_NAV_BADGE_STYLE" ]] || UI_NAV_BADGE_STYLE=muted
    fi
    UI_NAV_TEXT="$marker$preset$name"
}
