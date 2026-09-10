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

# id -> (r, g, b, grain). The grain is unused since 2026-09-10 (every texture
# is one flat colour); the column stays so old entries still parse.
#
# **The palette is Lord of the Rings.** Muted, earthy, a little grey in
# everything: moss greens rather than lime, umber soils, stone the colour of
# a Rohan hillside rock, water the dark green-blue of a Bree stream. Nothing
# saturated; the brightest thing in a scene should be light on a birch.
BLOCKS = {
    "stone":          (112, 110, 104,  0),
    "dirt":           ( 98,  78,  58,  0),
    "grass":          ( 92, 118,  58,  0),
    "loam":           ( 58,  44,  32,  0),
    "leaf_litter":    (108,  82,  52,  0),
    "creek_bed":      ( 96,  94,  88,  0),
    "limestone":      (176, 168, 146,  0),
    "granite":        (128, 124, 120,  0),
    "oak_log":        ( 84,  64,  44,  0),
    "oak_leaves":     ( 68,  96,  46,  0),
    "birch_log":      (206, 200, 186,  0),
    "dead_wood":      (110, 102,  90,  0),
    "fern":           ( 56,  92,  58,  0),
    "tall_grass":     (118, 132,  66,  0),
    "bramble":        ( 72,  60,  44,  0),
    "water":          ( 58,  92, 110,  0),
    "gloam_stone":    ( 74,  78,  90,  0),
    "abyss_stone":    ( 40,  38,  44,  0),
    "magma_crust":    ( 96,  44,  30,  0),
    "magma":          (222, 112,  28,  0),
    "lantern_stone":  (196, 168, 112,  0),
    "caul":           (112, 176, 104,  0),
    "dream_stone":    (140, 176, 200,  0),
    "scorch":         ( 66,  48,  36,  0),
    "marrow":         (214, 206, 190,  0),
    "apex_stone":     ( 54,  36,  62,  0),
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
