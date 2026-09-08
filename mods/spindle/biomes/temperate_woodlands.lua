-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- 1.1 Temperate Woodlands.
--
-- Where: the temperate ring (t = 0.18 .. 0.35 from the axis), on the wetter
-- side of the humidity noise. What: grass on the top blocks, oak trees.
--
-- Two mechanisms, because the engine offers two:
--
--   * The ground is a native fill. The biome's mask (ring x humidity x
--     "at the surface") is a density program compiled once; the generator
--     runs it for every chunk that can touch this ring.
--
--   * The trees GROW, by random tick on grass. A generator cannot read the
--     terrain it just wrote (a chunk buffer has no `get`), so nothing at
--     generation time knows where the surface is — but `register_random_tick`
--     hands a mod its blocks one at a time once the world exists, which is
--     what the engine offers for "a sapling becoming a tree". A woodland fills
--     in over the first minute you stand in it, then holds at its spacing.

local HUMIDITY_MIN = -0.05     -- the noise runs about -0.42 .. +0.42
local HUMIDITY_FREQ = 1 / 9000
local TREE_CHANCE = 4          -- one in this many turns a grass block gets
local TREE_SPACING = 2         -- no other trunk within this many blocks
local TRUNK_MIN, TRUNK_EXTRA = 4, 3   -- trunk height 4 .. 6

local blocks = spindle.blocks
local layers = spindle.layers
local shape = spindle.shape
local AIR = game.AIR

spindle.build_biome("temperate_woodlands", function(ctx)
    local n = ctx.node
    local ring = layers.ring_by_id.temperate
    local humidity = n.noise("humidity", HUMIDITY_FREQ, 2, 1.0)
    local mask = n.min(shape.ring(ring.u[1], ring.u[2]), n.sub(humidity, n.const(HUMIDITY_MIN)))
    -- Positive where the mask holds AND we are in the top blocks under the
    -- real surface. The band goes first in the min: it is the big subtree.
    local field = shape.compile("biome.temperate_woodlands",
        n.min(shape.terrain_band(0.0, shape.SKIN_TOP), mask))
    return { { field = field, material = blocks.grass } }
end)

-- Trees ---------------------------------------------------------------------

local function is_air(at)
    return at ~= nil and at.material == AIR
end

-- Whether a grass block at (x, y, z) is in this biome's ring. Integer
-- arithmetic on block coordinates; exact.
local function in_ring(x, z)
    local ring = layers.ring_by_id.temperate
    local r2 = x * x + z * z
    local R2 = shape.R_DISC * shape.R_DISC * 1e6
    return r2 >= ring.u[1] * R2 and r2 < ring.u[2] * R2
end

local function grow_tree(x, y, z, rng)
    local height = TRUNK_MIN + rng:below(TRUNK_EXTRA)
    -- Headroom: every block the tree will occupy must be loaded and empty.
    for dy = 1, height + 1 do
        if not is_air(game.get_block{ x = x, y = y + dy, z = z }) then
            return false
        end
    end
    -- Spacing: no trunk in the square around us at trunk height.
    for dx = -TREE_SPACING, TREE_SPACING do
        for dz = -TREE_SPACING, TREE_SPACING do
            if dx ~= 0 or dz ~= 0 then
                local near = game.get_block{ x = x + dx, y = y + 2, z = z + dz }
                if near ~= nil and near.material == blocks.oak_log then
                    return false
                end
            end
        end
    end
    -- Canopy: a 5x5 slab two deep with the corners off, a 3x3 above it, and
    -- a single block on top. Leaves never overwrite the trunk.
    local top = y + height
    for dy = top - 1, top do
        for dx = -2, 2 do
            for dz = -2, 2 do
                local corner = (dx == -2 or dx == 2) and (dz == -2 or dz == 2)
                if not corner and (dx ~= 0 or dz ~= 0) then
                    game.set_block({ x = x + dx, y = dy, z = z + dz }, "spindle:oak_leaves")
                end
            end
        end
    end
    for dx = -1, 1 do
        for dz = -1, 1 do
            game.set_block({ x = x + dx, y = top + 1, z = z + dz }, "spindle:oak_leaves")
        end
    end
    game.set_block({ x = x, y = top + 2, z = z }, "spindle:oak_leaves")
    for dy = 1, height do
        game.set_block({ x = x, y = y + dy, z = z }, "spindle:oak_log")
    end
    return true
end

game.register_random_tick(blocks.grass, function(event)
    if not in_ring(event.x, event.z) then
        return
    end
    -- One stream per block, so two grass blocks in one chunk do not grow the
    -- same tree. The world seed is captured by the generator.
    local rng = game.rng_stream(
        { x = event.x // 16, y = event.y // 16, z = event.z // 16, seed = spindle.seed or 0 },
        "tree:" .. event.x .. ":" .. event.y .. ":" .. event.z)
    if rng:below(TREE_CHANCE) ~= 0 then
        return
    end
    grow_tree(event.x, event.y, event.z, rng)
end)
