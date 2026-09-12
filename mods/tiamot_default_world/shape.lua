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
-- in a `min`/`add` and the small one second.
--
-- Sub-node fills ADD: a smooth fill writes its material into the cells where
-- its field is positive and leaves every other cell as it was (engine
-- `fill_density_detail`, since 2026-09-09). That is what lets the layers
-- below be painted one on top of another; the first fill at a surface is the
-- one that gives it its shape, so it must be the smooth one.

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
-- and ramps to RELIEF_FLOOR by u ~ 0.034, so the rings roll at +/-0.42 km on
-- a 12 km wavelength. Doubling this (tried 2026-09-08) made the rings a tilt
-- into kilometre walls; what reads as "bigger" at a player's scale is the
-- DETAIL term below — shorter hills, not taller tilts.
M.RELIEF_AMP = 4.0       -- km, before the mask
M.RELIEF_FREQ = 1 / 12000
M.RELIEF_OCTAVES = 2     -- 12 and 6 km; the hills carry on from 150 m. Each octave
                         -- here is paid five times per surface chunk.
M.RELIEF_FLOOR = 0.09    -- share of relief left outside the Crown (0.25, then 60%, then 60% again)
M.RELIEF_RAMP = 27.0     -- mask = clamp(1 - RAMP * (u - CROWN_U), FLOOR, 1)
M.CROWN_U = 0.0064
-- Detail: the hills you walk over. Low and rolling, with soft crests: +/-15
-- blocks on a 290 m wavelength is a 17% grade at the steepest, and two
-- octaves rather than three is what keeps the crests soft. (The woodland
-- brief, 2026-09-09, then "60% of that" twice the same day — both the
-- height and the width. Other rings will want their own terms, masked.)
M.DETAIL_AMP = 0.0067    -- km, x0.42 = +/-3 blocks (a third of +/-8, 2026-09-09)
M.DETAIL_FREQ = 1 / 150
M.DETAIL_OCTAVES = 2     -- 150 and 75 m. Noise cost is per octave, and the
                         -- terrain is evaluated once per skin fill.
-- Gullies: a V-shaped groove cut along the zero crossings of a slow noise.
-- Those crossings are meandering, connected lines, which is what a creek
-- bed looks like from above. Depth GULLY_DEPTH at the line, sloping up to
-- nothing where |noise| reaches GULLY_WIDTH — about seven blocks across.
M.GULLY_DEPTH = 0.0025   -- km: two and a half blocks
M.GULLY_WIDTH = 0.04     -- in the noise's own units (it runs +/-0.42): ~9 blocks across
M.GULLY_FREQ = 1 / 260
M.GULLY_OCTAVES = 2
-- Roughness: a fine noise that moves each bank in and out by a block or so
-- and, the same noise, makes the floor uneven — one node doing both, since
-- the field is evaluated five times a surface chunk and every noise node in
-- it is paid five times. The groove is not a perfect V along a perfect line.
M.GULLY_ROUGH = 0.4
M.GULLY_ROUGH_FREQ = 1 / 9
M.GULLY_BANK_WOBBLE = 0.012   -- in the noise's units: about +/-1 block of bank
-- Bluffs: a low-frequency noise clamped hard makes plateaus at +/-BLUFF_AMP
-- with a short, steep step between them wherever the noise crosses zero.
-- Clamped that hard the steps run along EVERY zero crossing, which as a
-- constant was a wall every two hundred blocks in a random direction — so
-- the term is masked by a second, slower noise, and shows only in patches
-- that cover about a fifth of the ground.
-- Small and soft for the woodland — two-block steps with rounded edges,
-- in patches — "clamped hill detail here and there" on hills that were
-- otherwise too smooth. The Ember Ridge will want 0.008 and STEEP 20.
M.BLUFF_AMP = 0.0012     -- km: steps of about two blocks
M.BLUFF_FREQ = 1 / 140
M.BLUFF_OCTAVES = 1
M.BLUFF_STEEP = 10.0     -- how sharply the noise is clamped: bigger is steeper
M.BLUFF_PATCH_FREQ = 1 / 900
M.BLUFF_PATCH_MIN = 0.08 -- the patch noise (+/-0.42) must exceed this: a third of the ground
M.BLUFF_PATCH_RAMP = 15.0 -- how quickly a patch fades in past that
-- The biome blend. One slow "humidity" noise splits a ring into a wet half
-- and a dry half at HUMIDITY_SPLIT (the temperate ring: woodlands wet,
-- grasslands dry). The two halves' own terrain terms CROSS-FADE over
-- HUMIDITY_BLEND of the noise either side of the split, so the ground never
-- steps at a border; their materials meet on the same contour, dithered at
-- the cell by a fine noise so the edge is a speckled band rather than a
-- line. The relief and the detail are the whole world's and need no blend.
M.HUMIDITY_FREQ = 1 / 9000
M.HUMIDITY_OCTAVES = 2
M.HUMIDITY_SPLIT = -0.05  -- the noise runs +/-0.5 after the clamp: the dry half is the smaller
M.HUMIDITY_BLEND = 0.04   -- in the noise's units: a few hundred blocks of cross-fade
M.HUMIDITY_DITHER = 0.03  -- +/-, at DITHER_FREQ: the speckle of the material edge
M.HUMIDITY_DITHER_FREQ = 1 / 10
-- Rolling grasslands (1.2): broad swells and long ridges. A ridge follows
-- the zero contour of a noise — a long continuous meandering line — as
-- RIDGE_AMP * (1 - |n| / RIDGE_WIDTH), clamped: a crest with gentle sides.
M.SWELL_AMP = 0.008       -- km, x0.5 = +/-4 blocks over SWELL_FREQ
M.SWELL_FREQ = 1 / 420
M.SWELL_OCTAVES = 2
M.RIDGE_AMP = 0.0045      -- km: a ridge stands four or five blocks over the swell
M.HOLLOW_DEEPEN = 0.35    -- the swell's low side is this much deeper than its high side is high
-- Alpine highlands (1.3): the range is a MAP (biomes/alpine_highlands.lua
-- builds it in the world pre-pass and defines `M.alpine_terms`, which the
-- terrain reads through a map node); nothing of its shape lives here.
-- Where the alpine terms apply: the frost ring, fading over ALPINE_BLEND_U
-- of u at its outer edge into the temperate ring's terms. (Its inner edge,
-- the Crown, is left to the Crown's biomes when they are built.)
-- ALPINE_EDGE_U is the frost ring's outer edge from layers.lua, repeated
-- here because shape.lua loads first; layers.lua asserts they agree.
M.ALPINE_EDGE_U = 0.18 * 0.18
M.ALPINE_BLEND_U = 0.003
M.RIDGE_FREQ = 1 / 650
M.RIDGE_WIDTH = 0.16      -- noise units: about fifty blocks from crest to foot
-- The plain. Nothing in Lua can evaluate the relief, so the one place a
-- player has to be put down blind is where the relief is SMALL by
-- construction: a ring of the disc, centred on the spawn radius and about
-- three kilometres wide, where the RING relief — the 12 km term, the one
-- that puts the surface hundreds of blocks from the base dome — is scaled
-- down to PLAIN_FLOOR of itself. The hills, the steps and the gullies run
-- through it at full strength: they are a few blocks, and a first visit can
-- see that far down. (Damping them too made the spawn read as plains.)
M.SPAWN_X = 15300        -- blocks; in the temperate ring, u ~ 0.067
M.SPAWN_Z = 0
M.PLAIN_HALF_WIDTH_U = 0.0125   -- in u: about 1.4 km of radius either side
M.PLAIN_FLOOR = 0.05            -- share of the relief left at the plain's centre

-- Body: W(Y) is the half-width in km at Spindle height Y, piecewise linear
-- through these knots, top to bottom. Above the first knot W is flat; the dome
-- caps it anyway. The plan's (-63, 0.9) knot is left out: each segment is
-- seven ops, twice. The needle tapers straight from 2 km wide at -37 to the
-- point at -70.
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
-- **The turf is three blocks thick for a reason that is not the look.** A
-- band is `half - |T - mid|`, which has a kink at `mid`; a block whose eight
-- corner samples straddle the kink interpolates its cells low, so the
-- band's upper edge lands a hair below the soil's and shows as a thin band
-- of soil on any slope. With `mid` at 1.5 blocks the kink is more than a
-- block from every surface block, and the two edges coincide exactly.
M.SKIN_TOP = 0.003       -- km: the biome's own material, three blocks
M.SKIN_DIRT = 0.005      -- km: soil under it, stone below that
M.GLOAM_D = 1.6          -- km below the base dome
M.ABYSS_D = 4.0

-- The tail, Spindle Y in km.
M.TAIL_Y = -37.0
M.APEX_Y = -63.0

-- Sub-node detail for every fill a player can stand on or look at. `smooth`
-- interpolates the block samples down to the cells (1.5x the block cost);
-- `sampled` asks the field about all 27 cells (5.5x) and only pays off when
-- a term finer than a block is added. `nil` is block resolution, staircases
-- and all.
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
local function max(a, b) return { op = "max", a = a, b = b } end
local function clamp(a, lo, hi) return { op = "clamp", a = a, low = lo, high = hi } end
local function abs(a) return { op = "abs", a = a } end
-- Every noise node is CLAMPED to +/-NOISE_RANGE of its amplitude. The
-- fractal never leaves that range (it runs to about +/-0.42), so the clamp
-- changes no terrain; what it changes is what the engine can PROVE about
-- the field. `Density:bounds` is an interval extension, and its bound on a
-- bare noise node is 3.78x the amplitude — safe, and so wide that no chunk
-- under a relief term is ever decided. A clamp's interval is the clamp, so
-- with it the engine skips a chunk the surface cannot reach before any
-- evaluation, for every fill, and the generator's gate reads the same bound.
M.NOISE_RANGE = 0.5
local function noise(stream, frequency, octaves, amplitude)
    local raw = { op = "noise", stream = stream, frequency = frequency, octaves = octaves, amplitude = amplitude }
    return { op = "clamp", a = raw, low = -M.NOISE_RANGE * amplitude, high = M.NOISE_RANGE * amplitude }
end
M.node = { const = const, X = X, Y = Y, Z = Z, add = add, sub = sub, mul = mul, min = min, max = max, clamp = clamp, abs = abs, noise = noise }

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

-- The terraces: BLUFF_AMP * clamp(STEEP * n, -1, 1) * patch, where patch
-- is clamp(RAMP * (n2 - MIN), 0, 1) on a much slower noise.
local function bluffs()
    local step = clamp(mul(noise("bluff", M.BLUFF_FREQ, M.BLUFF_OCTAVES, 1.0), const(M.BLUFF_STEEP)), -1.0, 1.0)
    local patch = clamp(mul(sub(noise("bluff_patch", M.BLUFF_PATCH_FREQ, 1, 1.0), const(M.BLUFF_PATCH_MIN)),
        const(M.BLUFF_PATCH_RAMP)), 0.0, 1.0)
    return mul(mul(step, patch), const(M.BLUFF_AMP))
end

-- PLAIN_FLOOR at the plain's centre radius, 1 from PLAIN_HALF_WIDTH_U out:
-- FLOOR + (1 - FLOOR) * clamp((u - u_plain)^2 / w^2, 0, 1).
M.PLAIN_U = (M.SPAWN_X * M.SPAWN_X + M.SPAWN_Z * M.SPAWN_Z) * 1e-6 / (M.R_DISC * M.R_DISC)
local function plain_mask()
    local function du() return sub(u(), const(M.PLAIN_U)) end
    local ramp = clamp(mul(mul(du(), du()), const(1 / (M.PLAIN_HALF_WIDTH_U * M.PLAIN_HALF_WIDTH_U))), 0.0, 1.0)
    return add(const(M.PLAIN_FLOOR), mul(ramp, const(1.0 - M.PLAIN_FLOOR)))
end

-- How deep in a gully a point is, 0..1: 1 on the creek line, 0 at the
-- gully's edge. The same noise node in two programs is the same field. A
-- fine noise wobbles the banks (added to |n| before the clamp) and roughens
-- the floor (scaling the result), so the profile is not a perfect V.
-- One roughness node serves both: the bank wobble is `|n| + w*r` and the
-- floor is scaled by `1 + k*r` — but rather than evaluate r twice, the floor
-- roughness rides on the SAME term: the profile is clamp(1 - (|n| + w*r)/W)
-- and a rougher floor comes from r moving the whole profile, which is what a
-- bank that wanders does to the floor under it anyway.
local function gully_depth()
    local groove = add(abs(noise("gully", M.GULLY_FREQ, M.GULLY_OCTAVES, 1.0)),
        mul(noise("gully_rough", M.GULLY_ROUGH_FREQ, 1, 1.0), const(M.GULLY_BANK_WOBBLE * (1.0 + M.GULLY_ROUGH))))
    return clamp(sub(const(1.0), mul(groove, const(1.0 / M.GULLY_WIDTH))), 0.0, 1.0)
end
-- Positive on the floor of a gully — the inner two fifths of its width —
-- for the creek-bed material. Multiplied by the plain mask's complement is
-- not needed: gullies run through the plain too.
function M.gully_floor()
    return sub(gully_depth(), const(0.6))
end

-- The humidity noise, +/-0.5.
function M.humidity()
    return noise("humidity", M.HUMIDITY_FREQ, M.HUMIDITY_OCTAVES, 1.0)
end

-- Which half of the split a biome takes, as a mask positive on its side:
-- the humidity plus the dither against the split, so the two sides are
-- exact complements and the edge is speckled rather than drawn.
function M.humidity_mask(wet)
    local h = add(M.humidity(), noise("biome_dither", M.HUMIDITY_DITHER_FREQ, 1, 2.0 * M.HUMIDITY_DITHER))
    if wet then
        return sub(h, const(M.HUMIDITY_SPLIT))
    end
    return mul(sub(h, const(M.HUMIDITY_SPLIT)), const(-1.0))
end

-- The dry side's weight, 0 in the wet half to 1 in the dry, crossing over
-- HUMIDITY_BLEND either side of the split.
-- (Noise first, constants after: a constant evaluated first holds a buffer
-- for everything after it, and the programs run close to the eight.)
local function dry_weight()
    return clamp(add(mul(sub(M.humidity(), const(M.HUMIDITY_SPLIT)), const(-0.5 / M.HUMIDITY_BLEND)), const(0.5)),
        0.0, 1.0)
end

-- Terrain MODES: which biome terms a program carries. A density program
-- cannot ask where it is, so the world's rings each get their own programs
-- and the generator picks by the chunk's radius (`terrain_mode_for`):
--   "wet"       the temperate ring's wet half alone (dev switch: woodlands)
--   "dry"       its dry half alone (dev switch: grasslands)
--   "temperate" both halves cross-faded by humidity — the temperate ring
--   "alpine"    the frost ring's terms alone
--   "all"       temperate and alpine cross-faded by the alpine weight: the
--               band a few hundred metres wide at the frost ring's edge,
--               and the only programs that carry every ring's noise.
-- `M.terrain_mode` is what `terrain()` reads while a program is being
-- built; whoever compiles a program sets it and puts it back.
M.terrain_mode = nil
function M.default_mode()
    local only = tdw.config.everywhere
    if only == nil then
        return "all"
    elseif only == "rolling_grasslands" then
        return "dry"
    elseif only == "alpine_highlands" then
        return "alpine"
    end
    return "wet"
end
-- The mode for a chunk spanning [u_lo, u_hi]: one ring's own programs
-- wherever the alpine weight is exactly 0 or 1 over the whole chunk, the
-- cross-faded ones in the band between.
function M.terrain_mode_for(u_lo, u_hi)
    if tdw.config.everywhere then
        return M.default_mode()
    end
    local edge, half = M.ALPINE_EDGE_U, M.ALPINE_BLEND_U / 2
    if u_hi <= edge - half then
        return "alpine"
    elseif u_lo >= edge + half then
        return "temperate"
    end
    return "all"
end

-- The alpine weight: 1 through the frost ring, fading to 0 over
-- ALPINE_BLEND_U past its outer edge.
local function alpine_weight()
    return clamp(add(mul(sub(u(), const(M.ALPINE_EDGE_U)), const(-1.0 / M.ALPINE_BLEND_U)), const(0.5)), 0.0, 1.0)
end

-- A grassland ridge: positive along the zero contour of its noise.
function M.ridge()
    return mul(clamp(add(mul(abs(noise("ridge", M.RIDGE_FREQ, 1, 1.0)), const(-1.0 / M.RIDGE_WIDTH)), const(1.0)), 0.0, 1.0),
        const(M.RIDGE_AMP))
end

-- The hollows more pronounced than the swells (2026-09-11): the noise's
-- low side is deepened by HOLLOW_DEEPEN, as n + k * min(n, 0), which is
-- (1 + k/2) n - (k/2) |n| — the noise evaluated twice, since the stack
-- machine has no dup and the same stream gives the same values.
local function swells()
    local k = M.HOLLOW_DEEPEN
    local swell = add(mul(noise("swell", M.SWELL_FREQ, M.SWELL_OCTAVES, M.SWELL_AMP), const(1.0 + k / 2)),
        mul(abs(noise("swell", M.SWELL_FREQ, M.SWELL_OCTAVES, M.SWELL_AMP)), const(-k / 2)))
    return add(swell, M.ridge())
end

-- The wet half's own terms: the bluffs (when on) and the gullies. A gully
-- lowers the surface, which is LESS depth at a given height.
local function wet_terms()
    local gully = mul(gully_depth(), const(M.GULLY_DEPTH))
    if M.BLUFF_AMP > 0 then
        return sub(bluffs(), gully)
    end
    return mul(gully, const(-1.0))
end

-- T: km below the real surface, positive underground. D plus the relief,
-- the detail and the biome terms — the wet half's gullies and bluffs, the
-- dry half's swells and ridges, cross-faded by the dry weight where both
-- are in play — a noise node each, every time it is evaluated. `flank`
-- programs run only near the rim and the underside, far from the plain, so
-- they leave the plain and the blend out and keep the ops for the body.
function M.terrain(flank)
    local relief = mul(relief_mask(), noise("relief", M.RELIEF_FREQ, M.RELIEF_OCTAVES, M.RELIEF_AMP))
    -- The world's own hills: two octaves every surface program pays. The
    -- alpine map and its ledges carry that scale themselves, so the alpine
    -- mode leaves them out — a third of the noise in every alpine fill.
    local mode = flank and "wet" or M.terrain_mode or M.default_mode()
    local detail = mode == "alpine" and const(0.0) or noise("detail", M.DETAIL_FREQ, M.DETAIL_OCTAVES, M.DETAIL_AMP)
    if not flank then
        relief = mul(relief, plain_mask())
    end
    local shape = add(relief, detail)
    if mode == "wet" then
        shape = add(shape, wet_terms())
    elseif mode == "dry" then
        shape = add(shape, swells())
    elseif mode == "alpine" then
        shape = add(shape, M.alpine_terms())
    elseif mode == "temperate" then
        shape = add(shape, add(mul(wet_terms(), add(mul(dry_weight(), const(-1.0)), const(1.0))), mul(swells(), dry_weight())))
    else
        -- The temperate pair cross-faded by humidity, and that whole
        -- cross-faded by the alpine weight against the alpine terms at the
        -- frost ring's edge, so neither ring steps at the border.
        local temperate = add(mul(wet_terms(), add(mul(dry_weight(), const(-1.0)), const(1.0))), mul(swells(), dry_weight()))
        shape = add(shape, add(mul(temperate, add(mul(alpine_weight(), const(-1.0)), const(1.0))),
            mul(M.alpine_terms(), alpine_weight())))
    end
    return add(M.depth(), shape)
end

-- A band of T between two depths, at ONE evaluation of the terrain:
-- half - |T - mid| is positive exactly where lo < T < hi. Negative depths
-- are ABOVE the ground.
function M.terrain_band(lo, hi, flank)
    local mid, half = (lo + hi) / 2, (hi - lo) / 2
    -- Written terrain-first: `half - |T - mid|` as `(|T - mid| - half) * -1`,
    -- one op more and one buffer fewer for the whole of T's evaluation.
    return mul(sub(abs(sub(M.terrain(flank), const(mid))), const(half)), const(-1.0))
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
        game.log(string.format("tiamot_default_world density %s REFUSED: %s", name, tostring(field)))
        error(field, 0)
    end
    game.log(string.format("tiamot_default_world density %-18s %3d ops", name, field:len()))
    return field
end
M.compile = compile

M.programs = {}
local P = M.programs
-- The top programs, one set per terrain mode the world needs: the dev
-- switch's one mode, or the three of the real world. The deep bands follow
-- D alone and are the same programs in every set.
local gloam = compile("top.gloam", sub(M.depth(), const(M.GLOAM_D)))
local abyss = compile("top.abyss", sub(M.depth(), const(M.ABYSS_D)))
local function top_programs(mode)
    M.terrain_mode = mode
    local set = {
        solid = compile("top." .. mode .. ".solid", M.terrain(false)),
        stone = compile("top." .. mode .. ".stone", sub(M.terrain(false), const(M.SKIN_DIRT))),
        gloam = gloam,
        abyss = abyss,
    }
    M.terrain_mode = nil
    return set
end
-- The alpine and cross-faded sets read the alpine maps, which exist only
-- after the world pre-pass, so they are compiled at the first chunk that
-- needs them (`top_for`); the rest are compiled here, at load, where
-- `--check-mods` sees them.
P.top = {}
local LAZY = { alpine = true, all = true }
function M.top_for(mode)
    local set = P.top[mode]
    if set == nil then
        set = top_programs(mode)
        P.top[mode] = set
    end
    return set
end
if tdw.config.everywhere then
    local mode = M.default_mode()
    if not LAZY[mode] then
        P.top[mode] = top_programs(mode)
    end
else
    P.top.temperate = top_programs("temperate")
end
P.flank = {
    solid = compile("flank.solid", min(M.terrain(true), M.body())),
    stone = compile("flank.stone", min(sub(M.terrain(true), const(M.SKIN_DIRT)), M.body())),
    gloam = compile("flank.gloam", min(sub(M.depth(), const(M.GLOAM_D)), M.body())),
    abyss = compile("flank.abyss", min(sub(M.depth(), const(M.ABYSS_D)), M.body())),
}
P.shells = {}
for _, shell in ipairs(M.SHELLS) do
    P.shells[shell[1]] = compile("shell." .. shell[1], M.shell(shell[2], shell[3]))
end
P.hollow = compile("hollow", M.inside(M.HOLLOW_R))

-- Plain-Lua evaluations of the same curves, for the generator's gate and the
-- spawn. These are BOUNDS on a chunk, not samples of the field: the fields
-- are the density programs above, and these only decide which programs are
-- worth running. Ordinary + - * / on doubles is IEEE-exact everywhere; no
-- libm here.
-- How far above the base dome a landing player is dropped, beyond the
-- plain's own thirty: the alpine range stands its peaks ALPINE_PEAK km
-- over the dome (the biome file says how high), and a player put down
-- inside a mountain would have to climb out through chunks the vertical
-- view does not reach. The landing scans down and hops, so a valley floor
-- far below the drop is found in a few hops.
function M.spawn_extra_above()
    if M.default_mode() == "alpine" then
        return math.ceil((M.ALPINE_PEAK or 0.4) * 1000) + 10
    end
    return 0
end
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
-- How much of the relief the plain leaves at a given u; the gate takes the
-- larger value at a chunk's two ends, which is the most since the curve is
-- a bowl.
function M.plain_at(u_value)
    local d = (u_value - M.PLAIN_U) / M.PLAIN_HALF_WIDTH_U
    local ramp = d * d
    if ramp > 1.0 then ramp = 1.0 end
    return M.PLAIN_FLOOR + (1.0 - M.PLAIN_FLOOR) * ramp
end
-- The world y of the base dome at the spawn column. The ground is within
-- PLAIN_FLOOR of the full relief of it.
function M.spawn_base_y()
    return M.Y0 + 1000.0 * M.dome_at(M.PLAIN_U)
end

return M
