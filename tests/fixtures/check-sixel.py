#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Decodificador de prueba independiente: raster, límites y colores del SIXEL."""
from pathlib import Path
import re
import sys

header, size, body = Path(sys.argv[1]).read_text().splitlines()
side = int(sys.argv[3])
assert header == "keila-sixel-v1" and int(size) == side
assert body.startswith(f'"1;1;{side};{side}') and "\x1b" not in body
source = Path(sys.argv[2]).read_bytes()
assert len(source) == 96 * 96 * 3
palette = {}
pixels = [None] * (side * side)
offset = len(f'"1;1;{side};{side}')
x = y = color = 0
while offset < len(body):
    ch = body[offset]
    if ch == "#":
        match = re.match(r"#(\d+)(?:;2;(\d+);(\d+);(\d+))?", body[offset:])
        assert match
        color = int(match[1])
        assert 0 <= color < 256
        if match[2] is not None:
            percentages = [int(match[i]) for i in (2, 3, 4)]
            assert all(0 <= value <= 100 for value in percentages)
            palette[color] = tuple(round(value * 255 / 100) for value in percentages)
        offset += len(match[0])
        continue
    if ch == "$":
        x = 0
        offset += 1
        continue
    if ch == "-":
        y += 6
        x = 0
        assert y < side
        offset += 1
        continue
    repeat = 1
    if ch == "!":
        match = re.match(r"!(\d+)", body[offset:])
        assert match
        repeat = int(match[1])
        assert 0 < repeat <= side
        offset += len(match[0])
        ch = body[offset]
    assert 63 <= ord(ch) <= 126 and color in palette and x + repeat <= side
    bits = ord(ch) - 63
    for dx in range(repeat):
        for dy in range(6):
            if bits & (1 << dy):
                assert y + dy < side
                pixels[(y + dy) * side + x + dx] = palette[color]
    x += repeat
    offset += 1
for y in range(side):
    for x in range(side):
        pixel = pixels[y * side + x]
        assert pixel is not None, (x, y)
        pos = (int(y * 96 / side) * 96 + int(x * 96 / side)) * 3
        assert all(abs(pixel[c] - source[pos + c]) <= (20, 20, 45)[c] for c in range(3)), (x, y)
print(f"ok   SIXEL decodificado: {side}x{side}, colores y raster dentro del espacio")
