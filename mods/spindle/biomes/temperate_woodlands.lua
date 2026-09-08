-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- 1.1 Temperate Woodlands.
--
-- Where: the temperate ring (t = 0.18 .. 0.35 from the axis), on the wetter
-- side of the humidity noise. What: grass on the top blocks, oak trees.
--
-- The trees are made in two halves, because the engine offers two things:
--
--   * The CANOPIES are a native fill. A high-frequency noise thresholded rare,
--     inside the shell of air three to nine blocks above the ground, gives
--     organic blobs of leaves that sit over the grass — and at sub-node
--     resolution they are leaf-shaped rather than boxes. A generator cannot
--     read the terrain it just wrote, so this is the only way anything at
--     generation time can be placed "above the ground": as a band of the
--     same field that made the ground.
--
--   * The TRUNKS grow, by random tick on grass. When a grass block gets its
--     turn and finds leaves above it with clear air between, it grows a trunk
--     up into them. A blob wide enough gets two or three. Trunks are whole
--     blocks because `game.set_block` writes whole blocks: an organic trunk
--     needs a runtime sub-node write the engine does not have yet.
--
-- The random tick offers a block only if it is one material (a block that is
-- grass cells over dirt cells is "mixed" and never comes up), which is fine:
-- on a smooth surface the top block is grass and air, and that one does.

local HUMIDITY_MIN = -0.05     -- the noise runs about -0.42 .. +0.42
local HUMIDITY_FREQ = 1 / 9000
local CANOPY_LOW, CANOPY_HIGH = 0.003, 0.009   -- km above the ground the leaves live
local CANOPY_FREQ = 1 / 9
local CANOPY_THRESHOLD = 0.20  -- the noise runs +/-0.42; lower is denser woodland
local TRUNK_SPACING = 2        -- no other trunk within this many blocks
local TRUNK_REACH = 10         -- how far up a grass block looks for its canopy

local blocks = spindle.blocks
local layers = spindle.layers
local shape = spindle.shape

spindle.build_biome("temperate_woodlands", function(ctx)
    local n = ctx.node
    local ring = layers.ring_by_id.temperate
    local function mask()
        local humidity = n.noise("humidity", HUMIDITY_FREQ, 2, 1.0)
        return n.min(shape.ring(ring.u[1], ring.u[2]), n.sub(humidity, n.const(HUMIDITY_MIN)))
    end
    -- Grass: the mask, in the top blocks under the real surface. The band
    -- goes first in the min: it is the big subtree.
    local grass = shape.compile("biome.woodlands.grass",
        n.min(shape.terrain_band(0.0, shape.SKIN_TOP), mask()))
    -- Canopies: the mask, in the shell of air above the surface, where a
    -- fine noise is rare enough to make separate blobs.
    local canopy = shape.compile("biome.woodlands.canopy",
        n.min(n.min(shape.terrain_band(-CANOPY_HIGH, -CANOPY_LOW), mask()),
            n.sub(n.noise("canopy", CANOPY_FREQ, 2, 1.0), n.const(CANOPY_THRESHOLD))))
    return {
        { field = grass, material = blocks.grass },
        { field = canopy, material = blocks.oak_leaves },
    }
end)

-- Trunks ---------------------------------------------------------------------

-- `material` is nil for a mixed block and `occupancy` is 0 for empty air, so
-- these are the two questions worth asking of a block on a smooth surface.
local function is_empty(at)
    return at ~= nil and at.occupancy == 0
end
local function holds(at, material)
    return at ~= nil and at.material == material and at.occupancy ~= 0
end

-- Whether a grass block at (x, z) is in this biome's ring. Integer
-- arithmetic on block coordinates; exact.
local function in_ring(x, z)
    local ring = layers.ring_by_id.temperate
    local r2 = x * x + z * z
    local R2 = shape.R_DISC * shape.R_DISC * 1e6
    return r2 >= ring.u[1] * R2 and r2 < ring.u[2] * R2
end

local function grow_trunk(x, y, z)
    -- Look up for leaves, with nothing but air on the way.
    local top = nil
    for dy = 1, TRUNK_REACH do
        local at = game.get_block{ x = x, y = y + dy, z = z }
        if at == nil then
            return false                -- not loaded; another turn
        end
        if holds(at, blocks.oak_leaves) then
            top = y + dy
            break
        end
        if not is_empty(at) then
            return false                -- something else in the way
        end
    end
    if top == nil or top - y < 3 then
        return false                    -- no canopy, or one lying on the ground
    end
    -- Spacing: no trunk in the square around us, checked at chest height.
    for dx = -TRUNK_SPACING, TRUNK_SPACING do
        for dz = -TRUNK_SPACING, TRUNK_SPACING do
            if dx ~= 0 or dz ~= 0 then
                if holds(game.get_block{ x = x + dx, y = y + 2, z = z + dz }, blocks.oak_log) then
                    return false
                end
            end
        end
    end
    -- Up to and one block into the canopy, so it reads as attached.
    for dy = 1, top - y do
        game.set_block({ x = x, y = y + dy, z = z }, "spindle:oak_log")
    end
    return true
end

game.register_random_tick(blocks.grass, function(event)
    if in_ring(event.x, event.z) then
        grow_trunk(event.x, event.y, event.z)
    end
end)
