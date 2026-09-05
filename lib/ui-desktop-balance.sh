#!/usr/bin/env bash

# Ajuste final de proporciones para la vista desktop.
# "Ahora suena" permanece a la izquierda, pero más contenido; Favoritos ocupa
# la mayor parte del ancho disponible a la derecha.

ui_desktop_pane_widths() {
    local width="$1"
    local usable now_playing favorites

    # Una fila de paneles ocupa:
    # │ + espacio + izquierda + espacio + │ + espacio + derecha + espacio + │
    usable=$((width - 7))
    ((usable < 86)) && usable=86

    # Ahora suena necesita espacio suficiente para emisora, metadatos y volumen,
    # pero deja de crecer pronto para que Favoritos sea el panel dominante.
    now_playing=$((usable * 42 / 100))
    ((now_playing < 42)) && now_playing=42
    ((now_playing > 52)) && now_playing=52

    favorites=$((usable - now_playing))
    if ((favorites <= now_playing)); then
        favorites=$((now_playing + 1))
        now_playing=$((usable - favorites))
    fi

    UI_DESKTOP_LEFT_WIDTH=$now_playing
    UI_DESKTOP_RIGHT_WIDTH=$favorites
}
