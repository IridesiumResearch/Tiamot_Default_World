-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The generator: one callback, a gate, and a short list of native fills.
--
-- Most of a 120,000-block world is solid rock or open air that no noise can
-- change. The gate classifies each chunk from its integer bounds — always
-- conservatively, so a chunk near a boundary can only pay MORE than it needed,
-- never generate differently — and runs only the fills that can matter.
--
-- Two depths drive it. T is the noisy terrain field: where the real surface
-- is, known to within the relief — and the engine says how far, exactly:
-- `Density:bounds` is an interval extension of the program (since engine
-- 9f01f67), so T's range over a chunk is read off the compiled field rather
-- than derived by hand here, and cannot drift from it. D is the smooth
-- depth below the base dome, known exactly. The skin (the soil, the biome's
-- block) follows T; the deep bands (gloam, abyss) follow D, so a chunk two
-- kilometres down pays for no noise at all.
--
-- **The first fill at a surface gives it its shape**, and sub-node fills
-- only ADD cells (see shape.lua), so the order is: the whole solid body as
-- DIRT, smooth — that is the surface; then stone from five blocks down, the
-- deep bands, and the biome's own top, each writing only where it is
-- positive and leaving the surface's shape alone. Then the core stack over
-- the middle, and the Hollow carved out of it. Rocks, trees and pools are
-- not generated at all: they are grown afterwards, by random tick, where the
-- surface can be read (biomes/temperate_woodlands.lua).
--
-- Nothing here samples a field. Everything in Lua is a BOUND on a chunk,
-- computed with + - * / on doubles, which is IEEE-exact everywhere.

local shape = tdw.shape
local layers = tdw.layers
local blocks = tdw.blocks
local P = shape.programs
local AIR = game.AIR
local DETAIL = shape.SURFACE_DETAIL

local SCALE = shape.SCALE
local R2_DISC = shape.R_DISC * shape.R_DISC
local NOISE_BOUND = 0.5           -- the fractal stays within +/-0.42 (the body warp's bound)
local SAFETY = 0.05               -- km, added to every bound
local WARP_HI = 1.0 + shape.FLANK_WARP * NOISE_BOUND
local WARP_LO = 1.0 - shape.FLANK_WARP * NOISE_BOUND
local STACK_Y_BLOCKS = shape.STACK_Y * 1000 + shape.Y0
local HOLLOW_IN = (shape.HOLLOW_R - SAFETY) * (shape.HOLLOW_R - SAFETY)

-- Chunk-class counters, logged now and then so the cost mix is visible.
local stats = { air = 0, hollow = 0, filled = 0, carved = 0, surface = 0, shells = 0, total = 0 }
local LOG_EVERY = 4096

-- Smallest and largest |value| over the integer range [a0, a1].
local function axis_bounds(a0, a1)
    local lo
    if a0 <= 0 and a1 >= 0 then
        lo = 0
    else
        lo = math.min(math.abs(a0), math.abs(a1))
    end
    return lo, math.max(math.abs(a0), math.abs(a1))
end

-- The deepest band a chunk is guaranteed to be in, from the smooth depth:
-- its material and how many of the band fills it already implies.
local function band_for(dmin)
    if dmin > shape.ABYSS_D + SAFETY then return blocks.abyss_stone, 2 end
    if dmin > shape.GLOAM_D + SAFETY then return blocks.gloam_stone, 1 end
    return blocks.stone, 0
end

-- The world seed reaches Lua as an integer when it fits one and as a FLOAT
-- when it does not (half of all seeds), and a float in a bitwise expression
-- is an error that disables the mod. So a hashable integer is derived once,
-- from the low bits, and that is what the random-tick handlers mix in.
local function seed_int(seed)
    local whole = math.tointeger(seed)
    if whole then
        return whole
    end
    return math.tointeger(seed % 4294967296.0) or 0
end

game.register_on_generate(function(buf, pos)
    if tdw.seed ~= pos.seed then
        tdw.seed = pos.seed
        tdw.seed_int = seed_int(pos.seed)
    end
    stats.total = stats.total + 1
    if stats.total % LOG_EVERY == 0 then
        game.log(string.format(
            "tiamot_default_world chunks: %d total — air %d, hollow %d, filled %d, carved %d (surface %d), shells %d",
            stats.total, stats.air, stats.hollow, stats.filled, stats.carved, stats.surface, stats.shells))
    end

    -- Order-independent with any other overworld generator: start empty.
    buf:fill_all(AIR)

    -- Integer bounds of the chunk, in blocks.
    local x0, z0, y0 = pos.x * 16, pos.z * 16, pos.y * 16
    local x1, z1, y1 = x0 + 15, z0 + 15, y0 + 15
    local xlo, xhi = axis_bounds(x0, x1)
    local zlo, zhi = axis_bounds(z0, z1)
    local r2lo = (xlo * xlo + zlo * zlo) * 1e-6     -- km^2
    local r2hi = (xhi * xhi + zhi * zhi) * 1e-6
    local ulo, uhi = r2lo / R2_DISC, r2hi / R2_DISC
    local Ylo, Yhi = (y0 - shape.Y0) * SCALE, (y1 - shape.Y0) * SCALE   -- Spindle km

    -- D, the smooth depth below the base dome: exact bounds.
    local dmax = shape.dome_at(ulo) - Ylo
    local dmin = shape.dome_at(uhi) - Yhi
    -- T, the real depth: the engine's bound on the terrain field over this
    -- chunk. Wrong in one direction only — it may say "maybe" about a chunk
    -- that turns out to be air, never "air" about one that is not.
    local t = P.top.solid:bounds(pos)
    local tmin, tmax = t.low, t.high

    -- Bounds on the body: W is non-decreasing in Y.
    local w_hi = shape.half_width_at(Yhi) * WARP_HI + SAFETY
    local w_lo = shape.half_width_at(Ylo) * WARP_LO - SAFETY
    local outside_body = r2lo > w_hi * w_hi
    local inside_body = w_lo > 0 and r2hi < w_lo * w_lo

    -- Bounds on the squared ellipsoidal distance from the stack centre.
    local dylo, dyhi = axis_bounds(y0 - STACK_Y_BLOCKS, y1 - STACK_Y_BLOCKS)
    local ks = shape.K * SCALE
    local e2lo = r2lo + (dylo * ks) * (dylo * ks)
    local e2hi = r2hi + (dyhi * ks) * (dyhi * ks)

    -- Air: above the surface, beyond the body, or wholly inside the Hollow.
    if tmax < 0 or outside_body then
        stats.air = stats.air + 1
        return
    end
    if e2hi < HOLLOW_IN then
        stats.hollow = stats.hollow + 1
        return
    end

    -- Rock. Which programs, and what it is made of.
    local V = inside_body and P.top or P.flank
    local base, level = band_for(dmin)
    local tail = false
    if Yhi < shape.APEX_Y then
        base, tail = blocks.apex_stone, true
    elseif Yhi < shape.TAIL_Y then
        base, tail = blocks.marrow, true
    end
    -- Within reach of the skin, the body is painted as the biome's soil
    -- first and stone is put back from five blocks down: that keeps the
    -- surface's shape in one smooth fill.
    local skin = not tail and tmin < shape.SKIN_DIRT
    if skin then
        base = tdw.surface_soil(ulo, uhi)
    end

    if inside_body and tmin > 0 then
        buf:fill_all(base)
        stats.filled = stats.filled + 1
    else
        buf:fill_density(V.solid, base, DETAIL)
        stats.carved = stats.carved + 1
    end

    if not tail then
        if skin then
            stats.surface = stats.surface + 1
            if tmax > shape.SKIN_DIRT then
                buf:fill_density(V.stone, blocks.stone, DETAIL)
            end
        end
        -- The deep bands, exact and free of noise.
        if level < 1 and dmax > shape.GLOAM_D - SAFETY then
            buf:fill_density(V.gloam, blocks.gloam_stone, DETAIL)
        end
        if level < 2 and dmax > shape.ABYSS_D - SAFETY then
            buf:fill_density(V.abyss, blocks.abyss_stone, DETAIL)
        end
        if skin and inside_body and tmin < shape.SKIN_TOP then
            -- The biome's own top.
            for _, biome in ipairs(tdw.surface_biomes_in(ulo, uhi)) do
                for _, fill in ipairs(biome.fills) do
                    buf:fill_density(fill.field, fill.material, DETAIL)
                end
            end
        end
    end

    -- The core stack, outermost first, only the shells this chunk can touch.
    local touched = false
    for _, shell in ipairs(shape.SHELLS) do
        local id, outer, inner = shell[1], shell[2], shell[3]
        if e2lo < outer * outer and e2hi > inner * inner then
            buf:fill_density(P.shells[id], blocks[layers.SHELL_MATERIAL[id]], DETAIL)
            touched = true
        end
    end
    if e2lo < shape.HOLLOW_R * shape.HOLLOW_R then
        buf:fill_density(P.hollow, AIR, DETAIL)
        touched = true
    end
    if touched then
        stats.shells = stats.shells + 1
    end
end)

game.log("tiamot_default_world: registered the generator")
