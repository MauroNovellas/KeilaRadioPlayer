#!/bin/bash

# ─── CONFIGURACIÓN ───────────────────────────────────────────
CARPETA_SCRIPT="$(dirname "$0")"
RADIO_MD="$CARPETA_SCRIPT/RADIO.md"
EMISORAS="$CARPETA_SCRIPT/emisoras.txt"
URL_GITHUB="https://raw.githubusercontent.com/LaQuay/TDTChannels/master/RADIO.md"

# ─── DESCARGAR O ACTUALIZAR RADIO.md ─────────────────────────
echo "Descargando/actualizando RADIO.md..."
curl -s -L "$URL_GITHUB" -o "$RADIO_MD"
echo "Archivo RADIO.md actualizado."

# ─── EXTRAER NOMBRE Y PRIMERA URL STREAM ────────────────────
> "$EMISORAS"
i=1
while read -r linea; do
    [[ "$linea" =~ ^# ]] && continue                     # comentarios/encabezados
    [[ "$linea" =~ ^\|[[:space:]-]*\| ]] && continue    # separadores de tabla
    [[ "$linea" =~ ^$ ]] && continue                    # líneas vacías
    if [[ "$linea" =~ ^\| ]]; then
        # separar columnas
        cols=()
        temp_line="$linea"
        while [[ $temp_line =~ \|([^|]*) ]]; do
            cols+=("${BASH_REMATCH[1]}")
            temp_line=${temp_line#*"|${BASH_REMATCH[1]}"}
        done
        nombre=$(echo "${cols[0]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        stream_col=$(echo "${cols[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # extraer primera URL usando grep
        url=$(echo "$stream_col" | grep -oE '\(https?://[^)]*\)' | head -n1)
        if [ -n "$url" ]; then
            url="${url#\(}"   # quitar paréntesis de inicio
            url="${url%\)}"   # quitar paréntesis de fin
            echo "$nombre|$url" >> "$EMISORAS"
            ((i++))
        fi
    fi
done < "$RADIO_MD"

echo "Archivo emisoras.txt generado con $((i-1)) emisoras."
