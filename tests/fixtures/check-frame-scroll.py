#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Comprobar ancho físico y scroll de frames ANSI, no solo caracteres/líneas."""
from pathlib import Path
import re
import sys
import unicodedata


def check(path, columns, lines):
    data = Path(path).read_text()
    row = column = offset = 0
    while offset < len(data):
        char = data[offset]
        if char == "\x1b":
            match = re.match(r"\x1b\[([0-9;?]*)([A-Za-z])", data[offset:])
            assert match, f"escape inesperado {data[offset:offset+30]!r}"
            args = [int(value or 0) for value in match[1].lstrip("?").split(";")]
            command = match[2]
            if command in ("H", "f"):
                row = (args[0] or 1)-1
                column = (args[1] if len(args)>1 else 1)-1
            elif command == "C":
                column += args[0] or 1
            elif command == "D":
                column = max(0, column-(args[0] or 1))
            elif command not in ("m", "J", "K", "h", "l"):
                raise AssertionError(f"CSI no contemplado: {command}")
            offset += len(match[0])
            continue
        if char == "\n":
            row += 1
            column = 0
            assert row < lines, f"scroll en fila {row+1} (alto {lines})"
        elif char == "\r":
            column = 0
        else:
            assert ord(char) >= 32, f"control fuera del renderer: {char!r}"
            width = 0 if unicodedata.category(char) in ("Mn", "Me", "Cf") else (
                2 if unicodedata.east_asian_width(char) in ("W", "F") else 1
            )
            column += width
            assert column < columns, f"autowrap fila {row+1}, columna {column} (ancho {columns}), cerca de {data[max(0,offset-60):offset+15]!r}"
        offset += 1


if __name__ == "__main__":
    try:
        check(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]))
    except (AssertionError, ValueError, OSError) as error:
        print(f"FAIL frame: {error}", file=sys.stderr)
        sys.exit(1)
