# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Generates the placeholder textures for mods/spindle/textures.

One flat colour per block with a little deterministic grain and a darker
one-pixel border, so a wall of one material still shows its blocks. No
dependencies beyond the standard library; run it from the repository root:

    python tools/make_textures.py
"""
import struct
import zlib
from pathlib import Path

SIZE = 16
OUT = Path(__file__).resolve().parent.parent / "mods" / "spindle" / "textures"

# id -> (r, g, b, grain)
BLOCKS = {
    "stone":          (128, 128, 128, 10),
    "dirt":           (121,  85,  58, 10),
    "grass":          ( 86, 140,  52, 12),
    "oak_log":        ( 94,  66,  38,  8),
    "oak_leaves":     ( 44, 105,  38, 14),
    "gloam_stone":    ( 72,  78,  96,  8),
    "abyss_stone":    ( 38,  36,  44,  6),
    "magma_crust":    (110,  40,  25, 10),
    "magma":          (255, 120,  20, 20),
    "lantern_stone":  (220, 180, 110, 12),
    "caul":           (120, 230, 110, 16),
    "dream_stone":    (150, 200, 235, 10),
    "scorch":         ( 70,  45,  30,  8),
    "marrow":         (235, 228, 210,  8),
    "apex_stone":     ( 55,  30,  70,  8),
}


def lcg(seed):
    state = seed & 0xFFFFFFFF
    while True:
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        yield state >> 16


def png(width, height, rows):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def texture(name, r, g, b, grain):
    rng = lcg(sum(ord(c) * 31 ** i for i, c in enumerate(name)))
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            n = (next(rng) % (2 * grain + 1)) - grain
            edge = x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1
            shade = -18 if edge else 0
            row += [max(0, min(255, v + n + shade)) for v in (r, g, b)] + [255]
        rows.append(row)
    return png(SIZE, SIZE, rows)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (r, g, b, grain) in BLOCKS.items():
        (OUT / f"{name}.png").write_bytes(texture(name, r, g, b, grain))
        print(f"wrote {name}.png")


if __name__ == "__main__":
    main()
