# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""A faithful port of generate.lua's chunk gate, to check its arithmetic.

It does NOT evaluate any field — the fields are the engine's density
programs. It reproduces the BOUNDS the generator computes per chunk and
prints (a) the layer sequence down chosen columns and (b) the class mix
over a cube, so a mistake in a bound shows up as a wrong layer or as too
many chunks paying for noise. Run from the repository root:

    python tools/gate_check.py
"""
from collections import Counter

# --- constants, copied from shape.lua -----------------------------------
SCALE = 0.001
Y0 = 11000
R_DISC = 59.0
K = 5.0
STACK_Y = 2.0
SUMMIT, DOME_DROP = 19.0, 2.5
RELIEF_AMP, RELIEF_FLOOR, RELIEF_RAMP, CROWN_U = 4.0, 0.5, 27.0, 0.0064
DETAIL_AMP = 0.5
BLUFF_AMP = 0.008
KNOTS = [(16.5, 59.0), (3.1, 58.5), (-8.0, 46.0), (-12.0, 30.0), (-16.0, 16.0),
         (-25.0, 6.0), (-37.0, 2.0), (-70.0, 0.0)]
FLANK_WARP = 0.15
MAGMA_R = 55.0
def blocks_in_e(n): return n * K * SCALE
SHELLS = [
    ("magma_above", MAGMA_R + blocks_in_e(62.5), MAGMA_R + blocks_in_e(12.5)),
    ("magma",       MAGMA_R + blocks_in_e(12.5), MAGMA_R - blocks_in_e(12.5)),
    ("magma_below", MAGMA_R - blocks_in_e(12.5), MAGMA_R - blocks_in_e(62.5)),
    ("hot_magical", MAGMA_R - blocks_in_e(62.5), 50.3),
    ("slime_border", 50.3, 49.7),
    ("cold_magical", 49.7, 46.0),
    ("hollow_ring", 46.0, 37.0),
]
HOLLOW_R = 37.0
SKIN_TOP, SKIN_DIRT, GLOAM_D, ABYSS_D = 0.0015, 0.005, 1.6, 4.0
TAIL_Y, APEX_Y = -37.0, -63.0

# --- generate.lua ---------------------------------------------------------
R2_DISC = R_DISC * R_DISC
NOISE_BOUND, SAFETY = 0.5, 0.05
WARP_HI, WARP_LO = 1 + FLANK_WARP * NOISE_BOUND, 1 - FLANK_WARP * NOISE_BOUND
STACK_Y_BLOCKS = STACK_Y * 1000 + Y0
HOLLOW_IN = (HOLLOW_R - SAFETY) ** 2

def dome_at(u): return SUMMIT - DOME_DROP * u * (2.0 - u)
def mask_at(u):
    m = 1.0 + RELIEF_RAMP * CROWN_U - RELIEF_RAMP * u
    return max(RELIEF_FLOOR, min(1.0, m))
def half_width_at(Y):
    if Y >= KNOTS[0][0]: return KNOTS[0][1]
    for i in range(len(KNOTS) - 1):
        y_hi, w_hi = KNOTS[i]; y_lo, w_lo = KNOTS[i + 1]
        if Y >= y_lo:
            return w_lo + (w_hi - w_lo) * (Y - y_lo) / (y_hi - y_lo)
    return 0.0
def axis_bounds(a0, a1):
    lo = 0 if a0 <= 0 <= a1 else min(abs(a0), abs(a1))
    return lo, max(abs(a0), abs(a1))
def band_for(dmin):
    if dmin > ABYSS_D + SAFETY: return "abyss_stone", 2
    if dmin > GLOAM_D + SAFETY: return "gloam_stone", 1
    return "stone", 0

def classify(cx, cy, cz):
    """Returns (class, base, fills) exactly as generate.lua would decide."""
    x0, z0, y0 = cx * 16, cz * 16, cy * 16
    x1, z1, y1 = x0 + 15, z0 + 15, y0 + 15
    xlo, xhi = axis_bounds(x0, x1); zlo, zhi = axis_bounds(z0, z1)
    r2lo = (xlo * xlo + zlo * zlo) * 1e-6; r2hi = (xhi * xhi + zhi * zhi) * 1e-6
    ulo, uhi = r2lo / R2_DISC, r2hi / R2_DISC
    Ylo, Yhi = (y0 - Y0) * SCALE, (y1 - Y0) * SCALE
    dmax = dome_at(ulo) - Ylo; dmin = dome_at(uhi) - Yhi
    relief = NOISE_BOUND * (RELIEF_AMP * mask_at(ulo) + DETAIL_AMP) + BLUFF_AMP + SAFETY
    tmax, tmin = dmax + relief, dmin - relief
    w_hi = half_width_at(Yhi) * WARP_HI + SAFETY
    w_lo = half_width_at(Ylo) * WARP_LO - SAFETY
    outside_body = r2lo > w_hi * w_hi
    inside_body = w_lo > 0 and r2hi < w_lo * w_lo
    dylo, dyhi = axis_bounds(y0 - STACK_Y_BLOCKS, y1 - STACK_Y_BLOCKS)
    ks = K * SCALE
    e2lo = r2lo + (dylo * ks) ** 2; e2hi = r2hi + (dyhi * ks) ** 2
    if tmax < 0 or outside_body: return "air", None, []
    if e2hi < HOLLOW_IN: return "hollow", None, []
    V = "top" if inside_body else "flank"
    base, level = band_for(dmin)
    tail = False
    if Yhi < APEX_Y: base, tail = "apex_stone", True
    elif Yhi < TAIL_Y: base, tail = "marrow", True
    skin = (not tail) and tmin < SKIN_DIRT
    if skin: base = "dirt"
    fills = []
    if inside_body and tmin > 0: cls = "filled"; fills.append(f"fill_all({base})")
    else: cls = "carved"; fills.append(f"{V}.solid->{base}")
    if not tail:
        if skin:
            cls = "surface"
            if tmax > SKIN_DIRT: fills.append(f"{V}.stone")
        if level < 1 and dmax > GLOAM_D - SAFETY: fills.append(f"{V}.gloam")
        if level < 2 and dmax > ABYSS_D - SAFETY: fills.append(f"{V}.abyss")
        if skin and inside_body:
            if tmin < SKIN_TOP: fills.append("biomes")
            fills.append("boulders?")
    for sid, outer, inner in SHELLS:
        if e2lo < outer * outer and e2hi > inner * inner: fills.append(f"shell.{sid}")
    if e2lo < HOLLOW_R * HOLLOW_R: fills.append("hollow")
    return cls, base, fills

def column(x, z, y_top=32000, y_bottom=-60000, label=""):
    print(f"\n== column at x={x} z={z} {label} ==")
    prev = None
    cx, cz = x // 16, z // 16
    for cy in range(y_top // 16, y_bottom // 16 - 1, -1):
        cls, base, fills = classify(cx, cy, cz)
        key = (cls, base, tuple(fills))
        if key != prev:
            print(f"  y={cy*16:>7}  {cls:8s} {str(base):12s} {' '.join(fills)}")
            prev = key

def cube(x, y, z, half):
    counts = Counter(); noisy = 0; total = 0
    for cx in range((x - half) // 16, (x + half) // 16):
        for cy in range((y - half) // 16, (y + half) // 16):
            for cz in range((z - half) // 16, (z + half) // 16):
                cls, _, fills = classify(cx, cy, cz)
                counts[cls] += 1; total += 1
                if any(f.startswith(("top.solid", "top.stone", "flank.", "biomes")) for f in fills): noisy += 1
    print(f"\n== cube {2*half} blocks around ({x},{y},{z}): {total} chunks ==")
    for cls, n in counts.most_common(): print(f"  {cls:8s} {n:6d}  {100*n/total:5.1f}%")
    print(f"  chunks that run noise: {noisy} ({100*noisy/total:.1f}%)")

if __name__ == "__main__":
    column(0, 0, label="(the axis)")
    column(15300, 0, y_top=31000, y_bottom=24000, label="(spawn, temperate ring)")
    column(40000, 0, y_top=32000, y_bottom=-30000, label="(r = 40 km)")
    column(58000, 0, y_top=32000, y_bottom=-10000, label="(r = 58 km, near the rim)")
    cube(30000, 27000, 0, 1600)
    cube(15300, 29700, 0, 800)
