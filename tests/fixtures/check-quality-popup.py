#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Comprueba escrituras/cursor de la ventana sin reutilizar su renderer."""
import re
import sys
import unicodedata

cols, lines = map(int, sys.argv[1:])
frame = sys.stdin.read()
parts = re.split(r"\x1b\[(\d+);(\d+)H", frame)
assert parts[0] == "" and len(parts) == 37, "no hay doce filas locales"
top, left = (lines - 12) // 2 + 1, (cols - 72) // 2 + 1
for i in range(12):
    row, col, text = parts[1 + 3 * i:4 + 3 * i]
    assert (int(row), int(col)) == (top + i, left), "cursor fuera del rectángulo"
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    assert not any(ord(char) < 32 for char in text), "borrado global/control inesperado"
    width = sum(0 if unicodedata.combining(char) else
                2 if unicodedata.east_asian_width(char) in ("W", "F") else 1
                for char in text)
    assert width == 72 and int(col) + width - 1 < cols, "ancho o margen incorrecto"
assert top + 11 <= lines, "ventana desborda por debajo"
