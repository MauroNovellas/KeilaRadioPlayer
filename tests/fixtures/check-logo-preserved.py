#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verifica movimientos de cursor y escrituras alrededor de un logo visible."""
from pathlib import Path
import re
import sys
import unicodedata


def check():
    data = Path(sys.argv[1]).read_text()
    left = int(sys.argv[2]) - 1
    columns, lines = map(int, sys.argv[3:5])
    top, bottom, right = 3, 8, left + 11
    row = column = offset = 0
    skipped = set()
    while offset < len(data):
        char = data[offset]
        if char == "\x1b":
            match = re.match(r"\x1b\[([0-9;]*)([A-Za-z])", data[offset:])
            assert match, f"escape no permitido: {data[offset:offset + 24]!r}"
            parameters = [int(value or 0) for value in match[1].split(";")]
            command = match[2]
            if command == "H":
                row = (parameters[0] or 1) - 1
                column = (parameters[1] if len(parameters) > 1 else 1) - 1
            elif command == "C":
                count = parameters[0] or 1
                assert count == 12 and top <= row <= bottom and column == left
                assert row not in skipped, "reserva saltada dos veces en una fila"
                skipped.add(row)
                column += count
            elif command == "m":
                pass
            elif command == "J":
                assert parameters[0] == 0 and row > bottom, "ED alcanza el logo"
            else:
                raise AssertionError(f"operación no permitida durante preservación: {command}")
            offset += len(match[0])
            assert 0 <= row < lines and 0 <= column < columns
            continue
        if char == "\n":
            row += 1
            column = 0  # ONLCR del terminal, como en el renderer normal.
        elif char == "\r":
            column = 0
        else:
            assert ord(char) >= 32
            width = 0 if unicodedata.combining(char) else (
                2 if unicodedata.east_asian_width(char) in ("W", "F") else 1
            )
            assert not (top <= row <= bottom and column <= right and column + width > left), (
                f"texto {char!r} sobre el logo en fila {row + 1}, columna {column + 1}"
            )
            column += width
        assert 0 <= row < lines and 0 <= column < columns, "autowrap/scroll en el frame"
        offset += 1
    assert skipped == set(range(top, bottom + 1)), "faltan filas de la reserva"


if __name__ == "__main__":
    try:
        check()
    except (AssertionError, OSError, ValueError) as error:
        print(f"FAIL logo preservado: {error}", file=sys.stderr)
        sys.exit(1)
