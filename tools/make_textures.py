# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Generates the textures for mods/spindle/textures.

One flat colour per block — nothing else, by design: any variation across a
surface is the renderer's (tint, and per-cell value jitter once the engine
has it), never baked into a picture. No dependencies beyond the standard
library; run it from the repository root:

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
    "water":          ( 50, 110, 170,  6),
    "loam":           ( 62,  44,  30, 10),
    "leaf_litter":    (118,  82,  44, 16),
    "creek_bed":      ( 96,  92,  84, 14),
    "limestone":      (188, 178, 150, 10),
    "granite":        (140, 132, 130, 18),
    "birch_log":      (214, 208, 196, 14),
    "dead_wood":      (112, 104,  92, 12),
}

# Alpha per texture; everything not listed is opaque.
ALPHA = {
    "water": 150,
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
    """A single flat colour. The grain and the border are gone (2026-09-10):
    the designer wants one colour per material, and the per-cell variation
    is the renderer's to do, not the texture's."""
    rows = [[v for _ in range(SIZE) for v in (r, g, b, ALPHA.get(name, 255))] for _ in range(SIZE)]
    return png(SIZE, SIZE, rows)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (r, g, b, grain) in BLOCKS.items():
        (OUT / f"{name}.png").write_bytes(texture(name, r, g, b, grain))
        print(f"wrote {name}.png")


if __name__ == "__main__":
    main()
