#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Contenedores ICO sintéticos, sin ImageMagick ni ficheros remotos."""
from pathlib import Path
import struct
import sys

directory = Path(sys.argv[1])
png = (directory / "source.png").read_bytes()
header = struct.pack("<HHH", 0, 1, 1)
entry = struct.pack("<BBBBHHII", 80, 40, 0, 0, 1, 32, len(png), 22)
(directory / "png.ico").write_bytes(header + entry + png)
pixels = bytes((255, 0, 0, 255)) * (32 * 32)
dib = struct.pack("<IiiHHIIiiII", 40, 32, 64, 1, 32, 0, len(pixels), 0, 0, 0, 0)
bitmap = dib + pixels + bytes(4 * 32)
entry = struct.pack("<BBBBHHII", 32, 32, 0, 0, 1, 32, len(bitmap), 22)
(directory / "bmp.ico").write_bytes(header + entry + bitmap)
