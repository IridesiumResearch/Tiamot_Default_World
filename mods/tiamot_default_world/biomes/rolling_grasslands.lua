-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- 1.2 Rolling Grasslands: the dry half of the temperate ring.
--
-- Topography: broad, undulating swells and long continuous ridges with
-- wide shallow hollows, gentle everywhere, with sightlines to the horizon
-- — the swell and ridge terms in shape.lua, faded in by the dry weight of
-- the humidity noise so the ground crosses into the woodlands without a
-- step. Surface: grass over thick dirt (the biome's soil is dirt, so the
-- skin under the turf is dirt without a fill); packed dry dirt along the
-- exposed crests of some ridges and along winding game trails; and now and
-- then a smooth solitary glacial erratic, grown by random tick from the
-- shared rocks module with no cuts and a deeper burial than a woodland
-- boulder. The grass itself is the same block as the woodlands' — the
-- tint field runs it from green to sun-bleached gold across the swells.

local TUFT_FREQ = 1 / 3
local TUFT_MIN = -0.12         -- thicker than the woodland meadow
local TUFT_HEIGHT_FREQ = 1 / 2
local COVER_CELL = 0.001 / 3

local TRAIL_FREQ = 1 / 220
local TRAIL_WIDTH = 0.012      -- noise units: a line two or three blocks wide
local TRAIL_PATCH_FREQ = 1 / 700
local TRAIL_PATCH_MIN = 0.08   -- trails in some stretches of the grass, not everywhere

local LEDGE_CREST = 0.7        -- a crest must reach this share of RIDGE_AMP to bare its dirt
local LEDGE_PATCH_FREQ = 1 / 300
local LEDGE_PATCH_MIN = 0.05   -- which crests are bared: the windward ones, as chance has it

local ERRATIC_CHANCE = 400     -- one grass block in this many, in a square that has one (the square and the spacing set the density)
local ERRATIC_CELL = 64        -- squares this wide...
local ERRATIC_CELL_ONE_IN = 3  -- ...one in this many may hold an erratic
local ERRATIC_APART = 40       -- and never within this many blocks of another stone
local ERRATIC_R = { 1.6, 1.4 } -- half-width, blocks: least and extra
local RESERVE = 6              -- a rare structure's reserve on the edit queue

local STATS_EVERY = 200

local blocks = tdw.blocks
local shape = tdw.shape
local edits = tdw.edits
local FULL = game.OCCUPANCY_FULL

tdw.build_biome("rolling_grasslands", function(ctx)
    local n = ctx.node
    local function masked(field)
        local mask = tdw.biome_mask(n, "temperate", false)
        return mask and n.min(field, mask) or field
    end
    local function top()
        return shape.terrain_band(0.0, shape.SKIN_TOP, false)
    end
    local grass = shape.compile("biome.grasslands.grass", masked(top()))
    -- Game trails: a thin band about the zero contour of a noise, in some
    -- stretches only, so they wind across the grass and peter out.
    local trails = shape.compile("biome.grasslands.trails", masked(n.min(n.min(top(),
        n.sub(n.const(TRAIL_WIDTH), n.abs(n.noise("trail", TRAIL_FREQ, 1, 1.0)))),
        n.sub(n.noise("trail_patch", TRAIL_PATCH_FREQ, 1, 1.0), n.const(TRAIL_PATCH_MIN)))))
    -- Bared crests: where the ridge term is near its top, on the crests a
    -- patch noise picks.
    local ledges = shape.compile("biome.grasslands.ledges", masked(n.min(n.min(top(),
        n.sub(shape.ridge(), n.const(LEDGE_CREST * shape.RIDGE_AMP))),
        n.sub(n.noise("ledge_patch", LEDGE_PATCH_FREQ, 1, 1.0), n.const(LEDGE_PATCH_MIN)))))
    -- The grass cover, as in the woodlands: two- or three-cell tufts drawn
    -- as cards, on most cell columns.
    local function reach_half()
        return n.mul(n.add(n.mul(n.noise("tuft_height", TUFT_HEIGHT_FREQ, 1, 1.0), n.const(0.6)), n.const(0.8)),
            n.const(COVER_CELL * 1.5))
    end
    local above = n.mul(shape.terrain(false), n.const(-1.0))
    local tuft_band = n.sub(reach_half(), n.abs(n.sub(above, reach_half())))
    local tufts = shape.compile("biome.grasslands.tufts",
        masked(n.min(tuft_band, n.sub(n.noise("tuft", TUFT_FREQ, 1, 1.0), n.const(TUFT_MIN)))))
    return {
        { field = grass, material = blocks.grass },
        { field = trails, material = blocks.packed_dirt },
        { field = ledges, material = blocks.packed_dirt },
        { field = tufts, material = blocks.tall_grass },
    }
end)
tdw.biomes.rolling_grasslands.soil = blocks.dirt

-- Erratics ----------------------------------------------------------------------

local stats = { turns = 0, tries = 0, erratics = 0, spacing = 0, unloaded = 0, errors = 0 }
local last_error = nil

local function at(x, y, z)
    return game.get_block{ x = x, y = y, z = z }
end

local function hash(x, y, z)
    local h = (x * 73856093) ~ (y * 19349663) ~ (z * 83492791) ~ ((tdw.seed_int or 0) * 2654435761)
    return h ~ (h >> 17)
end
local function candidate(x, y, z, one_in)
    return hash(x, y, z) % one_in == 0
end

local function stone_near(x, y, z)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
        for _, r in ipairs({ 6, 14, 26, ERRATIC_APART }) do
            for dy = -2, 2 do
                local b = at(x + d[1] * r, y + dy, z + d[2] * r)
                if b ~= nil and b.occupancy ~= 0 and (b.material == blocks.granite or b.material == blocks.limestone) then
                    return true
                end
            end
        end
    end
    return false
end

-- One smooth boulder, alone: no cuts, a little squat, deeper in the ground
-- than a woodland rock — it has been sitting there since the ice left.
local function place_erratic(x, y, z, rng)
    if not edits.room(RESERVE) then
        return false
    end
    local ground, top = tdw.rocks.surface_at(x, z, y)
    if ground == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    local r = ERRATIC_R[1] + rng:below(15) / 10 * ERRATIC_R[2] / 1.4
    local surface = ground + (top.occupancy == FULL and 1.0 or 0.6)
    edits.begin()
    tdw.rocks.place_rock("tiamot_default_world:granite", x, surface, z, r, rng,
        { cuts = 0, buried = 0.4 + rng:below(3) / 10, squat = 0.65 + rng:below(4) / 10 })
    return edits.commit(RESERVE)
end

local function on_grass(x, y, z)
    stats.turns = stats.turns + 1
    if not candidate(x, y, z, ERRATIC_CHANCE)
        or not candidate(x // ERRATIC_CELL, 5, z // ERRATIC_CELL, ERRATIC_CELL_ONE_IN) then
        return
    end
    stats.tries = stats.tries + 1
    if stone_near(x, y, z) then
        stats.spacing = stats.spacing + 1
        return
    end
    local rng = game.rng_stream(
        { x = x // 16, y = y // 16, z = z // 16, seed = tdw.seed or 0 },
        "erratic:" .. x .. ":" .. y .. ":" .. z)
    if place_erratic(x, y, z, rng) then
        stats.erratics = stats.erratics + 1
    end
end

-- The grass block is shared with the woodlands: a tick is this biome's
-- when the biome is everywhere, or when dirt is under the turf.
tdw.on_random_tick(blocks.grass, function(x, y, z)
    local only = tdw.config.everywhere
    local mine = only == "rolling_grasslands" or (only == nil and tdw.soil_under(x, y, z) == blocks.dirt)
    if not mine then
        return false
    end
    local ok, err = pcall(on_grass, x, y, z)
    if not ok then
        stats.errors = stats.errors + 1
        if last_error ~= tostring(err) then
            last_error = tostring(err)
            game.log("tiamot_default_world grasslands: grass tick failed: " .. last_error)
        end
    end
    return true
end)

local since = 0
tdw.on_tick(function(dt_ticks)
    since = since + dt_ticks
    if since < STATS_EVERY then
        return
    end
    since = 0
    if stats.turns == 0 then
        return
    end
    game.log(string.format(
        "tiamot_default_world grasslands: %d grass turns, %d erratic tries, %d placed; refused: spacing %d, unloaded %d; errors %d (%s)",
        stats.turns, stats.tries, stats.erratics, stats.spacing, stats.unloaded, stats.errors, last_error or "none"))
    for key in pairs(stats) do
        stats[key] = 0
    end
end)
