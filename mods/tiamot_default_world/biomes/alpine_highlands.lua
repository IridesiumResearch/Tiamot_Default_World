-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- 1.3 Alpine Highlands: the frost ring's dry half, and the first biome to
-- fake erosion in the field itself.
--
-- The brief: stepped plateaus, razor-thin ridgeways, steep glacial cirques
-- flanked by jagged crags; slopes of loose permafrost and chert with sudden
-- 15-30 block sheer drop-offs; stone (granite and slate) broken by gravel
-- drifts, patches of thin dirt, permafrost, and windswept crusts of packed
-- snow. The terrain is `shape.alpine_terms` (see shape.lua for the numbers):
-- a staircase of hard-clamped ramps on one slow noise makes the plateaus
-- and their sheer risers; a tent along a noise's zero contour makes the
-- ridgeways; a clamped bowl on another makes the cirques; a fine ridged
-- noise makes the crags. "Erosion" here is what those shapes imply — the
-- materials follow the shape: scree on the risers and cirque walls, thin
-- dirt and snow on the flats, permafrost in the lee, slate in seams.
--
-- Nothing is grown by random tick yet: no trees, and the drifts are fills.

local blocks = tdw.blocks
local shape = tdw.shape

local COVER_CELL = 0.001 / 3

local SLATE_FREQ = 1 / 90
local SLATE_MIN = 0.12         -- seams of slate in the granite: about a quarter of the rock
local SCREE_FREQ = 1 / 40
local SCREE_MIN = -0.05        -- gravel drifts over most of a riser, in tongues
local PERMAFROST_FREQ = 1 / 120
local PERMAFROST_MIN = 0.06    -- frozen ground in patches on the flats and gentle slopes
local DIRT_FREQ = 1 / 70
local DIRT_MIN = 0.16          -- thin dirt: small patches, on the flats only
local DIRT_DEPTH = 0.0015      -- km: a block and a half of it
local SNOW_FREQ = 1 / 60
local SNOW_MIN = 0.0           -- windswept: half the flats carry a crust
local FLAT_MAX = 0.35          -- a place counts as flat below this share of a riser

tdw.biomes.alpine_highlands.ring_mode = "alpine"
tdw.build_biome("alpine_highlands", function(ctx)
    local n = ctx.node
    local function masked(field)
        local mask = tdw.biome_mask(n, "frost", false)
        return mask and n.min(field, mask) or field
    end
    local function top()
        return shape.terrain_band(0.0, shape.SKIN_TOP, false)
    end
    -- How much of a riser or a cirque wall a place is, 0 on the flats to 1
    -- on the face: the terraces' own ramps, read back (shape.alpine_steep).
    local function steep()
        return shape.alpine_steep()
    end
    local function flat()
        return n.sub(n.const(FLAT_MAX), steep())
    end
    -- The rock: granite as the skin, slate in seams through it.
    local granite = shape.compile("biome.alpine.granite", masked(top()))
    local slate = shape.compile("biome.alpine.slate", masked(n.min(top(),
        n.sub(n.noise("slate", SLATE_FREQ, 1, 1.0), n.const(SLATE_MIN)))))
    -- Scree: gravel drifts on the risers and the cirque walls, in tongues.
    local scree = shape.compile("biome.alpine.scree", masked(n.min(n.min(top(),
        n.sub(steep(), n.const(0.5))),
        n.sub(n.noise("scree", SCREE_FREQ, 1, 1.0), n.const(SCREE_MIN)))))
    -- Permafrost: frozen ground in patches where it is not steep.
    local permafrost = shape.compile("biome.alpine.permafrost", masked(n.min(n.min(top(), flat()),
        n.sub(n.noise("permafrost", PERMAFROST_FREQ, 1, 1.0), n.const(PERMAFROST_MIN)))))
    -- Thin dirt: small patches on the flats, a block and a half deep.
    local dirt = shape.compile("biome.alpine.dirt", masked(n.min(n.min(
        shape.terrain_band(0.0, DIRT_DEPTH, false), flat()),
        n.sub(n.noise("thin_dirt", DIRT_FREQ, 1, 1.0), n.const(DIRT_MIN)))))
    -- Snow: a crust one cell thick stood on the flats where the wind lets
    -- it lie — a cover, so it sits on whatever the flat is made of. Within a
    -- sixth of a block of the ground, as the grass cover is, so cirque
    -- floors under a roof of rock get none.
    local snow = shape.compile("biome.alpine.snow", masked(n.min(n.min(
        n.sub(n.const(COVER_CELL / 2), shape.terrain(false)), flat()),
        n.sub(n.noise("windswept", SNOW_FREQ, 1, 1.0), n.const(SNOW_MIN)))))
    return {
        { field = granite, material = blocks.granite },
        { field = slate, material = blocks.slate },
        { field = scree, material = blocks.creek_bed },
        { field = permafrost, material = blocks.permafrost },
        { field = dirt, material = blocks.dirt },
        { cover = blocks.snow, cells = 1, take = snow },
    }
end)
tdw.biomes.alpine_highlands.soil = blocks.granite
