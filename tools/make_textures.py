# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Generates the textures for mods/tiamot_default_world/textures.

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
OUT = Path(__file__).resolve().parent.parent / "mods" / "tiamot_default_world" / "textures"

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
    "ladys_mantle":       ( 96, 124,  70,  0),
    "ladys_mantle_bloom": (172, 176,  92,  0),
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

# Foliage: the share of pixels that are HOLES. A block face is three cells
# across; each cell's face is split into a 3x3 of pixels and each pixel is
# fully opaque or fully gone, at random, from a stream seeded by the name.
# Binary alpha on purpose — the client alpha-tests foliage at 0.5, so there
# is nothing to sort and nothing to blend. At the 16-pixel tile a cell is 5
# or 6 pixels wide, so each of the nine is about two pixels.
HOLES = {
    "bramble": 0.50,
}
CELL_EDGES = [0, 5, 11, 16]     # the three cells across a 16-pixel face

# Leaves as ROUND DOTS: one pixel-circle per sub-node face, a little smaller
# than the cell so its corners are open, with the centre nudged and the
# radius varied per cell so the pattern does not repeat across a canopy.
# Read as round leaf clusters at a distance and as a cloud of dots up close,
# in the game's crisp style rather than a painterly one. Binary alpha.
# name -> (radius in pixels, radius jitter, centre jitter)
DOTS = {
    "oak_leaves": (2.6, 0.4, 0.6),
}

# Ferns as blocky FRONDS rather than dots (dots read as leaves, 2026-09-10):
# one small feather per sub-node face — a stem with leaflets either side,
# tapering to the tip — turned a random quarter per cell so a carpet of
# them fans every way. Still crisp and blocky; binary alpha.
FROND = [
    "..#..",
    ".###.",
    "..#..",
    "#####",
    "..#..",
]
FRONDS = {"fern"}

# Grass as a SPRITE: blades, for the engine's card drawing mode (asks, item
# 8) — a few tapering strokes from the bottom edge, binary alpha. Drawn as
# cells until then, it reads as a tuft with gaps, which is fine.
BLADES = {
    "tall_grass": 7,
}

# Rosettes and sprays, for the mantle: a rosette is a few round leaves
# low in the tile, overlapping, on short stems; a spray is thin stems from
# the bottom edge ending in small dot clusters high in the tile.
ROSETTES = {
    "ladys_mantle": 5,
}
SPRAYS = {
    "ladys_mantle_bloom": 5,
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
    is the renderer's to do, not the texture's. Foliage additionally has
    holes: the colour never varies, only whether a pixel is there."""
    holes = HOLES.get(name)
    alpha = ALPHA.get(name, 255)
    rosette = ROSETTES.get(name)
    if rosette is not None:
        rng = lcg(sum(ord(c) * 31 ** i for i, c in enumerate(name)) + 3)
        discs = []
        for _ in range(rosette):
            mx = 3 + (next(rng) % 100) / 10                 # 3 .. 13
            my = 8 + (next(rng) % 60) / 10                  # 8 .. 14: the lower half
            rr = 2.4 + (next(rng) % 12) / 10                # 2.4 .. 3.6
            discs.append((mx, my, rr * rr))
        rows = []
        for y in range(SIZE):
            row = []
            for x in range(SIZE):
                px, py = x + 0.5, y + 0.5
                on = any((px - mx) ** 2 + (py - my) ** 2 <= r2 for mx, my, r2 in discs)
                # A scallop: the very edge of a disc is nibbled every other pixel.
                edge = any(r2 - 1.4 <= (px - mx) ** 2 + (py - my) ** 2 <= r2 for mx, my, r2 in discs)
                if edge and (x + y) % 2 == 0:
                    on = False
                row += [r, g, b, 255 if on else 0]
            rows.append(row)
        return png(SIZE, SIZE, rows)
    spray = SPRAYS.get(name)
    if spray is not None:
        rng = lcg(sum(ord(c) * 31 ** i for i, c in enumerate(name)) + 9)
        on = [[False] * SIZE for _ in range(SIZE)]
        for _ in range(spray):
            x = 4 + (next(rng) % 90) / 10                   # a stem from the bottom
            lean = ((next(rng) % 1000) / 1000 - 0.5) * 0.6
            top = 6 + next(rng) % 6                         # stem height 6 .. 11
            for i in range(top):
                bx = int(x + lean * i)
                if 0 <= bx < SIZE:
                    on[SIZE - 1 - i][bx] = True
            # The head: a small cluster of dots round the stem's top.
            hx, hy = x + lean * top, SIZE - 1 - top
            for _ in range(4 + next(rng) % 4):
                dx = ((next(rng) % 1000) / 1000 - 0.5) * 4
                dy = ((next(rng) % 1000) / 1000 - 0.5) * 3
                px, py = int(hx + dx), int(hy + dy)
                for ox in (0, 1):
                    for oy in (0, 1):
                        if 0 <= px + ox < SIZE and 0 <= py + oy < SIZE:
                            on[py + oy][px + ox] = True
        rows = [[v for x in range(SIZE) for v in (r, g, b, 255 if on[y][x] else 0)] for y in range(SIZE)]
        return png(SIZE, SIZE, rows)
    if name in FRONDS:
        rng = lcg(sum(ord(c) * 31 ** i for i, c in enumerate(name)) + 13)
        on = [[False] * SIZE for _ in range(SIZE)]
        for cy in range(3):
            for cx in range(3):
                turns = next(rng) % 4
                pattern = [list(row) for row in FROND]
                for _ in range(turns):
                    pattern = [list(row) for row in zip(*pattern[::-1])]
                x0, y0 = CELL_EDGES[cx], CELL_EDGES[cy]
                for py, row in enumerate(pattern):
                    for px, v in enumerate(row):
                        if v == "#" and x0 + px < SIZE and y0 + py < SIZE:
                            on[y0 + py][x0 + px] = True
        rows = [[v for x in range(SIZE) for v in (r, g, b, 255 if on[y][x] else 0)] for y in range(SIZE)]
        return png(SIZE, SIZE, rows)
    blades = BLADES.get(name)
    if blades is not None:
        rng = lcg(sum(ord(c) * 31 ** i for i, c in enumerate(name)) + 5)
        on = [[False] * SIZE for _ in range(SIZE)]
        for _ in range(blades):
            x = (next(rng) % (SIZE * 10)) / 10
            top = 3 + next(rng) % 9                     # blade height in pixels, 3..11
            lean = ((next(rng) % 1000) / 1000 - 0.5) * 0.5
            for i in range(top):
                y = SIZE - 1 - i
                bx = int(x + lean * i)
                width = 2 if i < top // 2 else 1        # tapering
                for w in range(width):
                    if 0 <= bx + w < SIZE:
                        on[y][bx + w] = True
        rows = [[v for x in range(SIZE) for v in (r, g, b, 255 if on[y][x] else 0)] for y in range(SIZE)]
        return png(SIZE, SIZE, rows)
    dots = DOTS.get(name)
    if dots is not None:
        radius, r_jit, c_jit = dots
        rng = lcg(sum(ord(c) * 31 ** i for i, c in enumerate(name)) + 11)
        discs = []
        for cy in range(3):
            for cx in range(3):
                x0, x1 = CELL_EDGES[cx], CELL_EDGES[cx + 1]
                y0, y1 = CELL_EDGES[cy], CELL_EDGES[cy + 1]
                mx = (x0 + x1) / 2 + ((next(rng) % 1000) / 1000 - 0.5) * 2 * c_jit
                my = (y0 + y1) / 2 + ((next(rng) % 1000) / 1000 - 0.5) * 2 * c_jit
                rr = radius + ((next(rng) % 1000) / 1000 - 0.5) * 2 * r_jit
                discs.append((mx, my, rr * rr))
        rows = []
        for y in range(SIZE):
            row = []
            for x in range(SIZE):
                px, py = x + 0.5, y + 0.5
                on = any((px - mx) ** 2 + (py - my) ** 2 <= r2 for mx, my, r2 in discs)
                row += [r, g, b, 255 if on else 0]
            rows.append(row)
        return png(SIZE, SIZE, rows)
    if holes is None:
        rows = [[v for _ in range(SIZE) for v in (r, g, b, alpha)] for _ in range(SIZE)]
        return png(SIZE, SIZE, rows)
    rng = lcg(sum(ord(c) * 31 ** i for i, c in enumerate(name)) + 7)
    # One decision per sub-pixel of each cell: a 9x9 grid of decisions over
    # the face, each covering about two texture pixels.
    keep = {}
    for cy in range(3):
        for cx in range(3):
            for sy in range(3):
                for sx in range(3):
                    keep[(cx, sx, cy, sy)] = (next(rng) % 1000) >= holes * 1000
    rows = []
    for y in range(SIZE):
        cy = next(i for i in range(3) if CELL_EDGES[i] <= y < CELL_EDGES[i + 1])
        sy = min(2, (y - CELL_EDGES[cy]) * 3 // (CELL_EDGES[cy + 1] - CELL_EDGES[cy]))
        row = []
        for x in range(SIZE):
            cx = next(i for i in range(3) if CELL_EDGES[i] <= x < CELL_EDGES[i + 1])
            sx = min(2, (x - CELL_EDGES[cx]) * 3 // (CELL_EDGES[cx + 1] - CELL_EDGES[cx]))
            row += [r, g, b, 255 if keep[(cx, sx, cy, sy)] else 0]
        rows.append(row)
    return png(SIZE, SIZE, rows)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (r, g, b, grain) in BLOCKS.items():
        (OUT / f"{name}.png").write_bytes(texture(name, r, g, b, grain))
        print(f"wrote {name}.png")


if __name__ == "__main__":
    main()
