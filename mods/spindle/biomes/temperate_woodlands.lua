-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- 1.1 Temperate Woodlands.
--
-- Where: the temperate ring (t = 0.18 .. 0.35 from the axis), on the wetter
-- side of the humidity noise. What: grass on the top blocks, oak trees, and
-- the occasional pool.
--
-- Two mechanisms, because the engine offers two:
--
--   * The ground is a native fill. The biome's mask (ring x humidity x
--     "in the top blocks under the surface") is a density program compiled
--     once; the generator runs it, sub-node smooth, for every chunk that can
--     touch this ring. It adds grass cells to the surface the dirt fill
--     shaped and changes nothing else.
--
--   * Everything that stands on the ground GROWS, by random tick on grass. A
--     generator cannot read the terrain it just wrote (a chunk buffer has no
--     `get`), so nothing at generation time knows where the surface is — but
--     `register_random_tick` hands a mod its blocks one at a time once the
--     world exists, which is what the engine offers for "a sapling becoming a
--     tree". A woodland fills in over the first minute you stand in it, then
--     holds its spacing.
--
-- Trees are SCHEMATICS, not noise: a shape the code decides, with the random
-- stream picking sizes and offsets. They are placed with `game.set_block`'s
-- third argument — a 27-cell mask — so the canopy is rounded to the cell and
-- the branches are thin, and the trunk is walked DOWN into the ground until
-- it meets a whole block, so on a smooth slope it never hangs.
--
-- Every structure goes through one paced queue (`spindle.edits`) as a batch
-- that lands whole: a tree is a few hundred edits in several chunks, and
-- each chunk touched is a relight on the server and a remesh on every
-- client, so trees arrive one at a time with a few ticks between them.
--
-- The random tick offers a block only if it is one material, which on a
-- smooth surface the top block is: grass cells and air. The block under it
-- (grass over dirt) never comes up, and need not.

local HUMIDITY_MIN = -0.05     -- the noise runs about -0.42 .. +0.42
local HUMIDITY_FREQ = 1 / 9000

local TREE_CHANCE = 8          -- one grass block in this many is a candidate
local TREE_SPACING = 4         -- no other trunk within this many blocks
local TRUNK_MIN, TRUNK_EXTRA = 8, 4     -- trunk height 8 .. 11
local ROOT_DEPTH = 3           -- how far down the trunk may go looking for whole ground
local CANOPY_R, CANOPY_R_EXTRA = 3.5, 1.5   -- half-width of the main clump, blocks
local CANOPY_FLAT = 0.7        -- height as a share of width
local CLUMPS_MIN, CLUMPS_EXTRA = 2, 3       -- side clumps, each with a branch to it

local POOL_CHANCE = 60000      -- one grass block in this many: very occasional
local POOL_R = 3               -- radius of the bank, blocks; water is one block down
local POOL_APART = 24          -- no other water within this many blocks

local blocks = spindle.blocks
local layers = spindle.layers
local shape = spindle.shape
local edits = spindle.edits

spindle.build_biome("temperate_woodlands", function(ctx)
    local n = ctx.node
    local ring = layers.ring_by_id.temperate
    -- Positive where the mask holds AND we are in the top blocks under the
    -- real surface. The band goes first in the min: it is the big subtree.
    local band = shape.terrain_band(0.0, shape.SKIN_TOP, false)
    local spec = band
    if not ctx.everywhere then
        local humidity = n.noise("humidity", HUMIDITY_FREQ, 2, 1.0)
        local mask = n.min(shape.ring(ring.u[1], ring.u[2]), n.sub(humidity, n.const(HUMIDITY_MIN)))
        spec = n.min(band, mask)
    end
    local field = shape.compile("biome.woodlands.grass", spec)
    return { { field = field, material = blocks.grass } }
end)

-- Reading the world ---------------------------------------------------------

local FULL = game.OCCUPANCY_FULL

-- `occupancy` is 0 for empty air and `material` is nil for a mixed block, so
-- these are the questions worth asking of a block on a smooth surface.
local function at(x, y, z)
    return game.get_block{ x = x, y = y, z = z }
end
local function is_empty(b)
    return b ~= nil and b.occupancy == 0
end
local function is_whole(b)
    return b ~= nil and b.occupancy == FULL
end
local function holds(b, material)
    return b ~= nil and b.material == material and b.occupancy ~= 0
end

-- Whether a grass block at (x, z) is in this biome's ring. Integer
-- arithmetic on block coordinates; exact.
local function in_ring(x, z)
    if spindle.config.everywhere == "temperate_woodlands" then
        return true
    end
    local ring = layers.ring_by_id.temperate
    local r2 = x * x + z * z
    local R2 = shape.R_DISC * shape.R_DISC * 1e6
    return r2 >= ring.u[1] * R2 and r2 < ring.u[2] * R2
end

-- Cell masks -----------------------------------------------------------------

-- Bit for cell (cx, cy, cz), each 0..2, indexed x + 3*y + 9*z.
local function bit(cx, cy, cz)
    return 1 << (cx + 3 * cy + 9 * cz)
end

-- A thin bar of three cells through the middle of a block along one axis.
local BAR = {
    x = bit(0, 1, 1) | bit(1, 1, 1) | bit(2, 1, 1),
    y = bit(1, 0, 1) | bit(1, 1, 1) | bit(1, 2, 1),
    z = bit(1, 1, 0) | bit(1, 1, 1) | bit(1, 1, 2),
}

-- The mask of the cells of block (bx, by, bz) whose centres lie inside an
-- ellipsoid centred at (cx, cy, cz) with half-widths (rx, ry, rz). Plain
-- + - * / on doubles and comparisons: nothing here is a library call.
local function ellipsoid_mask(bx, by, bz, cx, cy, cz, rx, ry, rz)
    local mask = 0
    for iz = 0, 2 do
        local dz = (bz + (iz + 0.5) / 3 - cz) / rz
        for iy = 0, 2 do
            local dy = (by + (iy + 0.5) / 3 - cy) / ry
            for ix = 0, 2 do
                local dx = (bx + (ix + 0.5) / 3 - cx) / rx
                if dx * dx + dy * dy + dz * dz <= 1.0 then
                    mask = mask | bit(ix, iy, iz)
                end
            end
        end
    end
    return mask
end

-- Trees ----------------------------------------------------------------------

-- Leaves go only into empty blocks, and never over a trunk; a block two
-- clumps both reach gets the union of their cells.
local function place_leaves(leaf_masks, key, mask)
    leaf_masks[key] = (leaf_masks[key] or 0) | mask
end

local function grow_tree(x, y, z, rng)
    local height = TRUNK_MIN + rng:below(TRUNK_EXTRA)
    -- Headroom over the trunk.
    for dy = 1, height + 4 do
        if not is_empty(at(x, y + dy, z)) then
            return false
        end
    end
    -- Spacing: no trunk within TREE_SPACING, checked on a ring of points at
    -- chest height rather than every block of the square.
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
        for r = 2, TREE_SPACING do
            if holds(at(x + d[1] * r, y + 2, z + d[2] * r), blocks.oak_log) then
                return false
            end
        end
    end

    -- Roots: the trunk goes down through the grass block and any partial
    -- ground under it until it stands on a whole block, so on a slope it is
    -- planted rather than perched.
    local base = y
    for dy = 0, ROOT_DEPTH do
        local b = at(x, y - dy, z)
        if b == nil then
            return false
        end
        base = y - dy
        if is_whole(b) then
            break
        end
    end

    -- The canopy: a main clump at the top of the trunk and a few side clumps
    -- around it, each an ellipsoid, unioned cell by cell. The side clumps sit
    -- a little lower and out to one side, which is what makes it a tree
    -- rather than a lollipop.
    local top = y + height
    local leaf_masks = {}
    local clumps = {}
    local r = CANOPY_R + rng:below(16) / 16 * CANOPY_R_EXTRA
    clumps[1] = { cx = x + 0.5, cy = top - 0.5, cz = z + 0.5, rx = r, ry = r * CANOPY_FLAT, rz = r }
    local count = CLUMPS_MIN + rng:below(CLUMPS_EXTRA)
    for i = 1, count do
        local ox = rng:below(7) - 3
        local oz = rng:below(7) - 3
        if ox == 0 and oz == 0 then ox = 2 end
        local oy = -1 - rng:below(3)
        local sr = 1.8 + rng:below(8) / 8
        clumps[#clumps + 1] = {
            cx = x + 0.5 + ox, cy = top + 0.5 + oy, cz = z + 0.5 + oz,
            rx = sr, ry = sr * CANOPY_FLAT + 0.3, rz = sr,
            branch = { ox = ox, oy = oy, oz = oz },
        }
    end
    for _, c in ipairs(clumps) do
        local x0, x1 = math.floor(c.cx - c.rx), math.floor(c.cx + c.rx)
        local y0, y1 = math.floor(c.cy - c.ry), math.floor(c.cy + c.ry)
        local z0, z1 = math.floor(c.cz - c.rz), math.floor(c.cz + c.rz)
        for bz = z0, z1 do
            for by = y0, y1 do
                for bx = x0, x1 do
                    local mask = ellipsoid_mask(bx, by, bz, c.cx, c.cy, c.cz, c.rx, c.ry, c.rz)
                    if mask ~= 0 then
                        place_leaves(leaf_masks, bx .. ":" .. by .. ":" .. bz, mask)
                    end
                end
            end
        end
    end

    -- Branches: from the trunk's upper part out to each side clump, as thin
    -- bars of wood, one block per step, taking the longer axis first.
    local branch_masks = {}
    for _, c in ipairs(clumps) do
        if c.branch then
            local bx, by, bz = x, top + c.branch.oy - 1, z
            local dx, dz = c.branch.ox, c.branch.oz
            local steps = math.max(math.abs(dx), math.abs(dz))
            local sx = dx > 0 and 1 or (dx < 0 and -1 or 0)
            local sz = dz > 0 and 1 or (dz < 0 and -1 or 0)
            for step = 1, steps do
                local along_x = math.abs(dx) >= math.abs(dz)
                if along_x then
                    if step <= math.abs(dx) then bx = bx + sx end
                    if step <= math.abs(dz) then bz = bz + sz end
                else
                    if step <= math.abs(dz) then bz = bz + sz end
                    if step <= math.abs(dx) then bx = bx + sx end
                end
                if step == steps then by = by + 1 end
                local key = bx .. ":" .. by .. ":" .. bz
                branch_masks[key] = (branch_masks[key] or 0) | (along_x and BAR.x or BAR.z)
                if step == steps then
                    branch_masks[key] = branch_masks[key] | BAR.y
                end
            end
        end
    end

    -- One batch, trunk first, then the wood in the canopy, then the leaves
    -- around it. Leaves never overwrite anything.
    edits.begin()
    for by = base, top do
        edits.push({ x = x, y = by, z = z }, "spindle:oak_log")
    end
    for key, mask in pairs(branch_masks) do
        local bx, by, bz = key:match("^(-?%d+):(-?%d+):(-?%d+)$")
        bx, by, bz = tonumber(bx), tonumber(by), tonumber(bz)
        if not (bx == x and bz == z) and is_empty(at(bx, by, bz)) then
            edits.push({ x = bx, y = by, z = bz }, "spindle:oak_log", mask)
        end
        leaf_masks[key] = nil
    end
    for key, mask in pairs(leaf_masks) do
        local bx, by, bz = key:match("^(-?%d+):(-?%d+):(-?%d+)$")
        bx, by, bz = tonumber(bx), tonumber(by), tonumber(bz)
        if not (bx == x and bz == z and by <= top) and is_empty(at(bx, by, bz)) then
            edits.push({ x = bx, y = by, z = bz }, "spindle:oak_leaves", mask)
        end
    end
    return edits.commit()
end

-- Pools ----------------------------------------------------------------------

-- A pool is dug, not found: a flat patch of grass gets a bank one block deep
-- and a bowl of water under it, two blocks deep at the middle. The bank is
-- what keeps it in — the water sits a block below the grass, walled by whole
-- blocks of ground — so a smooth slope cannot drain it.
local function dig_pool(x, y, z)
    -- Flat: every block on the bank ring is ground at y with air over it,
    -- and whole ground under it.
    for dz = -POOL_R, POOL_R do
        for dx = -POOL_R, POOL_R do
            if dx * dx + dz * dz <= POOL_R * POOL_R then
                local ground, above, under = at(x + dx, y, z + dz), at(x + dx, y + 1, z + dz), at(x + dx, y - 1, z + dz)
                if ground == nil or ground.occupancy == 0 or not is_empty(above) or not is_whole(under) then
                    return false
                end
            end
        end
    end
    -- Alone: no water nearby already.
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        for _, r in ipairs({ 6, 12, POOL_APART }) do
            for dy = -2, 1 do
                local fluid = game.get_fluid{ x = x + d[1] * r, y = y + dy, z = z + d[2] * r }
                if fluid and not fluid.empty then
                    return false
                end
            end
        end
    end
    -- The bank, then the bowl, then — once the carving has landed — the
    -- water.
    local water = {}
    edits.begin()
    for dz = -POOL_R, POOL_R do
        for dx = -POOL_R, POOL_R do
            local d2 = dx * dx + dz * dz
            if d2 <= POOL_R * POOL_R then
                edits.push({ x = x + dx, y = y, z = z + dz }, "engine:air")
            end
            if d2 <= (POOL_R - 1) * (POOL_R - 1) then
                edits.push({ x = x + dx, y = y - 1, z = z + dz }, "engine:air")
                water[#water + 1] = { x = x + dx, y = y - 1, z = z + dz }
            end
            if d2 <= 1 then
                edits.push({ x = x + dx, y = y - 2, z = z + dz }, "engine:air")
                water[#water + 1] = { x = x + dx, y = y - 2, z = z + dz }
            end
        end
    end
    if not edits.commit() then
        return false
    end
    -- The batch lands within MAX_WAITING * BATCH_EVERY ticks; wait past that.
    edits.later(90, function()
        for _, p in ipairs(water) do
            game.set_fluid(p, { fluid = "spindle:water", volume = 27 })
        end
    end)
    return true
end

-- Which grass blocks are candidates is decided by an integer hash of the
-- position and the world seed, before anything is read or any stream opened:
-- a busy world hands this handler thousands of blocks a tick and almost all
-- of them must cost nothing. Plain integer arithmetic; exact.
local function candidate(x, y, z, one_in)
    local h = (x * 73856093) ~ (y * 19349663) ~ (z * 83492791) ~ ((spindle.seed or 0) * 2654435761)
    h = h ~ (h >> 17)
    return h % one_in == 0
end

game.register_random_tick(blocks.grass, function(event)
    local x, y, z = event.x, event.y, event.z
    if not edits.room() or not in_ring(x, z) then
        return
    end
    if candidate(x, y, z, POOL_CHANCE) then
        dig_pool(x, y, z)
        return
    end
    if not candidate(x, y, z, TREE_CHANCE) then
        return
    end
    -- One stream per block, so two grass blocks in one chunk do not grow the
    -- same tree. The world seed is captured by the generator.
    local rng = game.rng_stream(
        { x = x // 16, y = y // 16, z = z // 16, seed = spindle.seed or 0 },
        "tree:" .. x .. ":" .. y .. ":" .. z)
    grow_tree(x, y, z, rng)
end)
