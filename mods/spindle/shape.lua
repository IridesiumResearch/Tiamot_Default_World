-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The shape of the Spindle, as density programs.
--
-- Everything here is a DESCRIPTION handed to `game.density` once, at load.
-- Nothing samples a field in Lua (charter rule 4; AGENTS.md rule 1). The
-- numbers follow docs/spindle-mod-plan.md Part B, with the magma shell
-- thinned to the designer's later figures (50 / 25 / 50 blocks) and the
-- stack squished further so the magma is always under the abyss.
--
-- Units: fields work in KILO-BLOCKS. f32 has the same RELATIVE precision at
-- any magnitude, so squaring a world coordinate and scaling afterwards costs
-- nothing in accuracy — what matters is that the numbers being SUBTRACTED
-- (W^2 - r^2, R^2 - E^2) are a few thousand km^2, where an f32 step is two
-- ten-thousandths, and not billions of blocks^2.
--
-- Spindle frame: Y = y - Y0, so the disc's summit is at Y = +19 km.
--
-- Two limits of the density compiler shape the code below: 256 ops per
-- program, and 8 live buffers. A subtree is walked once per place it appears
-- (no sharing), and evaluation is left to right, so a big subtree goes FIRST
-- in a `min`/`add` and the small one second. `flank.dirt` sits at the op
-- limit: anything added to the terrain field has to come out of the body.

local M = {}

-- Frame ---------------------------------------------------------------------
M.SCALE = 0.001          -- blocks -> km
M.Y0 = 11000             -- world y at Spindle Y = 0
M.R_DISC = 59.0          -- km, radius of the disc
M.K = 5.0                -- ellipsoid squish: vertical semi-axis = R / K.
                         -- 3.7 in the plan; 5 keeps the magma's top pole
                         -- 5.9 km under the Crown (so the abyss is above it
                         -- everywhere) and the stack inside the underside.
M.STACK_Y = 2.0          -- km, centre of the core stack (Spindle frame)

-- Dome: H(u) = SUMMIT - DOME_DROP * u * (2 - u), u = r^2 / R^2. Flat at the
-- centre, flat at the rim, 6.5% grade at worst. Needs no sqrt.
M.SUMMIT = 19.0          -- km at the axis
M.DOME_DROP = 2.5        -- km from summit to rim (rim at +16.5)

-- Relief: 3D fBm with a vertical gradient of 1 km per km. The fractal runs to
-- roughly +/-0.42, so RELIEF_AMP = 4 is +/-1.7 km of mountain at the Crown
-- before the mask. The mask holds full relief inside the Crown (u < 0.0064)
-- and ramps to RELIEF_FLOOR by u ~ 0.034 — half, since 2026-09-08's "the
-- scale is a little small": the temperate rings now roll at +/-0.84 km.
M.RELIEF_AMP = 4.0       -- km, before the mask
M.RELIEF_FREQ = 1 / 12000
M.RELIEF_OCTAVES = 5
M.RELIEF_FLOOR = 0.5     -- share of relief left outside the Crown
M.RELIEF_RAMP = 27.0     -- mask = clamp(1 - RAMP * (u - CROWN_U), FLOOR, 1)
M.CROWN_U = 0.0064
-- Detail: doubled with the relief, and its wavelength with it so the slopes
-- stay under the overhang limit (relief < 0.42 * wavelength, plan A.3).
M.DETAIL_AMP = 0.5       -- km, ~200 blocks of hill on top of the relief
M.DETAIL_FREQ = 1 / 1200
M.DETAIL_OCTAVES = 3
-- Bluffs: a low-frequency noise clamped hard makes plateaus at +/-BLUFF_AMP
-- with a short, steep step between them wherever the noise crosses zero —
-- a terrace, or a cliff of twice BLUFF_AMP, every few hundred blocks.
M.BLUFF_AMP = 0.008      -- km: 16-block cliffs
M.BLUFF_FREQ = 1 / 350
M.BLUFF_OCTAVES = 2
M.BLUFF_STEEP = 20.0     -- how sharply the noise is clamped: bigger is steeper
-- Boulders: a high-frequency noise thresholded rare, in the shell of air just
-- above the ground, so the blobs sit on it, half buried.
M.BOULDER_FREQ = 1 / 7
M.BOULDER_THRESHOLD = 0.30   -- the noise runs +/-0.42; this keeps a few percent
M.BOULDER_SHELL = 0.006      -- km above the surface the blobs may reach

-- Body: W(Y) is the half-width in km at Spindle height Y, piecewise linear
-- through these knots, top to bottom. Above the first knot W is flat; the dome
-- caps it anyway. The plan's (-63, 0.9) knot is left out: each segment is
-- seven ops, twice, and `flank.dirt` needs them. The needle tapers straight
-- from 2 km wide at -37 to the point at -70.
M.KNOTS = {
    { 16.5, 59.0 }, { 3.1, 58.5 }, { -8.0, 46.0 }, { -12.0, 30.0 }, { -16.0, 16.0 },
    { -25.0, 6.0 }, { -37.0, 2.0 }, { -70.0, 0.0 },
}
M.FLANK_WARP = 0.15      -- W' = W * (1 + FLANK_WARP * n), n in +/-0.42
M.FLANK_FREQ = 1 / 4000

-- The core stack, as horizontal radii in km on the squished ellipsoid. A
-- thickness of t km in these units is t/K km vertically at the poles, which
-- is the direction a player digs into it from, so the magma's 25-block lava
-- layer is 25 * K blocks in E.
local MAGMA_R = 55.0
local function blocks_in_e(n) return n * M.K * M.SCALE end
M.SHELLS = {
    -- id,            outer R (km),                       inner R (km)
    { "magma_above",  MAGMA_R + blocks_in_e(12.5 + 50),   MAGMA_R + blocks_in_e(12.5) },
    { "magma",        MAGMA_R + blocks_in_e(12.5),        MAGMA_R - blocks_in_e(12.5) },
    { "magma_below",  MAGMA_R - blocks_in_e(12.5),        MAGMA_R - blocks_in_e(12.5 + 50) },
    { "hot_magical",  MAGMA_R - blocks_in_e(12.5 + 50),   50.3 },
    { "slime_border", 50.3,                               49.7 },
    { "cold_magical", 49.7,                               46.0 },
    { "hollow_ring",  46.0,                               37.0 },
}
M.HOLLOW_R = 37.0

-- Depth bands. The SKIN follows the real surface (the noisy terrain field);
-- the deeper bands follow the SMOOTH dome depth, which needs no noise and
-- lets the generator place them exactly. Under a mountain the gloam begins
-- deeper than 1.6 km below the peak, under a valley shallower — the proxy
-- error the plan accepts until there is an exact depth (B.5).
M.SKIN_TOP = 0.0015      -- km: the biome's own block, one to two blocks
M.SKIN_DIRT = 0.005      -- km: dirt under it
M.GLOAM_D = 1.6          -- km below the base dome
M.ABYSS_D = 4.0

-- The tail, Spindle Y in km.
M.TAIL_Y = -37.0
M.APEX_Y = -63.0

-- Sub-node detail for every fill a player can stand on or look at. `smooth`
-- interpolates the block samples down to the cells (1.5x the block cost);
-- `sampled` asks the field about all 27 cells (5.5x) and only pays off when
-- a term finer than a block is added. `nil` is block resolution, staircases
-- and all. The shells and the Hollow's ceiling use it too: they have no
-- noise, so it is nearly free there.
M.SURFACE_DETAIL = { detail = "smooth" }

-- Node builders ---------------------------------------------------------------
local function const(v) return { op = "const", value = v } end
local function X() return { op = "x" } end
local function Y() return { op = "y" } end
local function Z() return { op = "z" } end
local function add(a, b) return { op = "add", a = a, b = b } end
local function sub(a, b) return { op = "sub", a = a, b = b } end
local function mul(a, b) return { op = "mul", a = a, b = b } end
local function min(a, b) return { op = "min", a = a, b = b } end
local function clamp(a, lo, hi) return { op = "clamp", a = a, low = lo, high = hi } end
local function noise(stream, frequency, octaves, amplitude)
    return { op = "noise", stream = stream, frequency = frequency, octaves = octaves, amplitude = amplitude }
end
M.node = { const = const, X = X, Y = Y, Z = Z, add = add, sub = sub, mul = mul, min = min, clamp = clamp, noise = noise }

-- Shared subexpressions (each call builds a fresh tree) ----------------------
-- r^2 in km^2: seven ops and three buffers.
local function r2() return mul(add(mul(X(), X()), mul(Z(), Z())), const(M.SCALE * M.SCALE)) end
local function u() return mul(r2(), const(1 / (M.R_DISC * M.R_DISC))) end
local function ys() return mul(sub(Y(), const(M.Y0)), const(M.SCALE)) end
M.sub = { r2 = r2, u = u, ys = ys }

-- H(u) = SUMMIT - u * (2*DROP - DROP*u), with u evaluated second in the
-- product so the peak stays at six buffers.
local function dome()
    local inner = sub(const(2.0 * M.DOME_DROP), mul(const(M.DOME_DROP), u()))
    return sub(const(M.SUMMIT), mul(inner, u()))
end

-- D: km below the base dome, smooth. The proxy for the deep bands.
function M.depth()
    return sub(dome(), ys())
end

-- mask(u) = clamp(1 + RAMP*CROWN_U - RAMP*u, FLOOR, 1)
local function relief_mask()
    return clamp(sub(const(1.0 + M.RELIEF_RAMP * M.CROWN_U), mul(const(M.RELIEF_RAMP), u())),
        M.RELIEF_FLOOR, 1.0)
end

-- The terraces: BLUFF_AMP * clamp(STEEP * n, -1, 1).
local function bluffs()
    return mul(const(M.BLUFF_AMP),
        clamp(mul(noise("bluff", M.BLUFF_FREQ, M.BLUFF_OCTAVES, 1.0), const(M.BLUFF_STEEP)), -1.0, 1.0))
end

-- T: km below the real surface, positive underground. D plus the relief,
-- the detail and the bluffs — three noise nodes, every time it is evaluated.
function M.terrain()
    local relief = mul(relief_mask(), noise("relief", M.RELIEF_FREQ, M.RELIEF_OCTAVES, M.RELIEF_AMP))
    local detail = noise("detail", M.DETAIL_FREQ, M.DETAIL_OCTAVES, M.DETAIL_AMP)
    return add(add(add(M.depth(), relief), detail), bluffs())
end

-- A band of T between two depths: min(T - lo, -(T - hi)). The negation is a
-- multiply rather than `sub(hi, T)` so T is never evaluated with a constant
-- already waiting on the stack. Negative depths are ABOVE the ground.
function M.terrain_band(lo, hi)
    return min(sub(M.terrain(), const(lo)), mul(sub(M.terrain(), const(hi)), const(-1.0)))
end

-- Boulders: in the shell of air just above the surface, where a fine noise
-- is rare enough to make separate blobs.
function M.boulders()
    return min(M.terrain_band(-M.BOULDER_SHELL, 0.0),
        sub(noise("boulder", M.BOULDER_FREQ, 2, 1.0), const(M.BOULDER_THRESHOLD)))
end

-- W(Y) as a sum of clamped ramps on RAW y, so each segment is seven ops.
-- W = W_top + sum_i s_i * clamp(y - y_i, dy_i, 0), s_i in km per block.
local function half_width()
    local acc = const(M.KNOTS[1][2])
    for i = 1, #M.KNOTS - 1 do
        local y_i = M.KNOTS[i][1] * 1000 + M.Y0
        local dy = (M.KNOTS[i + 1][1] - M.KNOTS[i][1]) * 1000        -- negative
        local slope = (M.KNOTS[i + 1][2] - M.KNOTS[i][2]) / dy         -- positive
        acc = add(acc, mul(const(slope), clamp(sub(Y(), const(y_i)), dy, 0.0)))
    end
    return acc
end

-- W'(Y) with the flank warp, and B = W'^2 - r^2 (positive inside the body).
local function warped_half_width()
    return mul(half_width(), add(const(1.0), noise("flank", M.FLANK_FREQ, 2, M.FLANK_WARP)))
end
function M.body()
    return sub(mul(warped_half_width(), warped_half_width()), r2())
end

-- E2: squared ellipsoidal distance from the stack centre, km^2.
local function e2()
    local dy = mul(sub(Y(), const(M.STACK_Y * 1000 + M.Y0)), const(M.K * M.SCALE))
    return add(r2(), mul(dy, dy))
end
-- A shell between two radii: positive inside outer and outside inner.
function M.shell(outer, inner)
    return min(sub(const(outer * outer), e2()), sub(e2(), const(inner * inner)))
end
function M.inside(radius)
    return sub(const(radius * radius), e2())
end

-- Ring mask on u: positive between two thresholds.
function M.ring(u_lo, u_hi)
    return min(sub(u(), const(u_lo)), sub(const(u_hi), u()))
end

-- Compiled programs -----------------------------------------------------------
-- Compiled ONCE here and captured. `top` programs assume the chunk is inside
-- the body wall (the generator's gate guarantees it); `flank` programs also
-- test the body, at a noise node more, for chunks near the rim, the underside
-- or the needle.
local function compile(name, spec)
    local ok, field = pcall(game.density, spec)
    if not ok then
        -- The host reports only "errored in init.lua"; say which program and why.
        game.log(string.format("spindle density %s REFUSED: %s", name, tostring(field)))
        error(field, 0)
    end
    game.log(string.format("spindle density %-18s %3d ops", name, field:len()))
    return field
end
M.compile = compile

M.programs = {}
local P = M.programs
P.top = {
    solid = compile("top.solid", M.terrain()),
    dirt = compile("top.dirt", M.terrain_band(0.0, M.SKIN_DIRT)),
    gloam = compile("top.gloam", sub(M.depth(), const(M.GLOAM_D))),
    abyss = compile("top.abyss", sub(M.depth(), const(M.ABYSS_D))),
    boulders = compile("top.boulders", M.boulders()),
}
P.flank = {
    solid = compile("flank.solid", min(M.terrain(), M.body())),
    dirt = compile("flank.dirt", min(M.terrain_band(0.0, M.SKIN_DIRT), M.body())),
    gloam = compile("flank.gloam", min(sub(M.depth(), const(M.GLOAM_D)), M.body())),
    abyss = compile("flank.abyss", min(sub(M.depth(), const(M.ABYSS_D)), M.body())),
}
P.shells = {}
for _, shell in ipairs(M.SHELLS) do
    P.shells[shell[1]] = compile("shell." .. shell[1], M.shell(shell[2], shell[3]))
end
P.hollow = compile("hollow", M.inside(M.HOLLOW_R))

-- Plain-Lua evaluations of the same curves, for the generator's gate. These
-- are BOUNDS on a chunk, not samples of the field: the fields are the density
-- programs above, and these only decide which programs are worth running.
-- Ordinary + - * / on doubles is IEEE-exact everywhere; no libm here.
function M.dome_at(u_value)
    return M.SUMMIT - M.DOME_DROP * u_value * (2.0 - u_value)
end
function M.mask_at(u_value)
    local m = 1.0 + M.RELIEF_RAMP * M.CROWN_U - M.RELIEF_RAMP * u_value
    if m < M.RELIEF_FLOOR then return M.RELIEF_FLOOR end
    if m > 1.0 then return 1.0 end
    return m
end
-- W(Y) in km for a Spindle Y in km, from the knots.
function M.half_width_at(Y_km)
    local knots = M.KNOTS
    if Y_km >= knots[1][1] then return knots[1][2] end
    for i = 1, #knots - 1 do
        local y_hi, w_hi = knots[i][1], knots[i][2]
        local y_lo, w_lo = knots[i + 1][1], knots[i + 1][2]
        if Y_km >= y_lo then
            return w_lo + (w_hi - w_lo) * (Y_km - y_lo) / (y_hi - y_lo)
        end
    end
    return 0.0
end

return M
