#!/bin/bash

##############################################################################
# BÚSQUEDA DE EMISORAS (Integración con fzf)
#
# Dependencia: fzf (https://github.com/junegunn/fzf)
# Ventajas: Búsqueda difusa, navegación nativa, menos uso de CPU.
##############################################################################

buscar_emisora() {
    # 1. COMPROBACIÓN DE SEGURIDAD
    # hecho en deps.sh

    # 2. LANZAMIENTO DE FZF
    # Explicación de flags:
    # --delimiter='|' : Entiende que tu BD usa '|' para separar columnas.
    # --with-nth=1    : Solo muestra la 1ª columna (Nombre) al usuario (oculta la URL).
    # --layout=reverse: La búsqueda sale arriba, más natural para menús.
    # --height=100%   : Usa toda la pantalla disponible.
    
    local seleccion
    seleccion=$(fzf --prompt="Buscar Emisora > " \
                    --delimiter='\|' \
                    --with-nth=1 \
                    --header="[↑/↓] Navegar | [Escribe] Filtrar | [Enter] Reproducir | [ESC] Salir" \
                    --color="fg:white,bg:-1,hl:blue,fg+:cyan,bg+:-1,hl+:blue" \
                    --layout=reverse \
                    --border \
                    --cycle \
                    < "$EMISORAS")

    # 3. PROCESAMIENTO
    # Si la variable $seleccion no está vacía (el usuario no pulsó ESC)
    if [ -n "$seleccion" ]; then
        # Separamos el string basándonos en el pipe '|'
        IFS="|" read -r nombre url <<< "$seleccion"
        
        # Invocamos a tu función de reproducción existente
        # Limpiamos pantalla antes para que se vea bien el player
        clear 
        reproducir "$nombre" "$url"
    else
        # Si canceló, limpiamos para volver al menú principal
        clear
    fi

    # Forzar reinicialización de la UI al volver
    UI_INIT=0
    SHOW_CONTROLS=0
    NECESITA_REDIBUJAR=1
}
