-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- 1.1 Temperate Woodlands.
--
-- Where: the temperate ring (t = 0.18 .. 0.35 from the axis), on the wetter
-- side of the humidity noise.
--
-- The brief (2026-09-09): low rolling hills with soft crests and gentle
-- gradient changes, broken by shallow gullies and seasonal creek beds. Deep
-- dark loam and rich grass turf, irregular patches of brown leaf litter,
-- exposed woody root nodes, and weathered limestone or granite boulders
-- half-buried in the soil. Oaks, with aspens here and there, and dead
-- wood — standing snags and fallen trunks — rarer still. The trees follow
-- the Better Trees idiom: rounded trunks, a fork now and then, branches
-- that each carry a clump of leaves, a canopy that is lumps and gaps.
--
-- The hills and the gullies are the terrain field's (shape.lua). What this
-- file owns is the FLOOR and what stands on it, by two mechanisms:
--
--   * The ground is native fills, run sub-node smooth for every chunk that
--     can touch this ring, each adding cells to the surface the soil fill
--     shaped: grass in the top blocks, leaf litter where a mid-scale noise
--     says so, wet gravel along the creek floors. The soil under all of it
--     is loam — the generator asks the biome what to paint the body as.
--
--   * Everything that stands on the ground GROWS, by random tick on grass.
--     A generator cannot read the terrain it just wrote, so nothing at
--     generation time knows where the surface is — but `register_random_tick`
--     hands a mod its blocks one at a time once the world exists. Trees,
--     rocks and root nodes are SCHEMATICS: shapes the code decides, rounded
--     to the cell with `game.set_block`'s 27-cell mask, with the random
--     stream picking sizes and offsets. Every structure is one batch on the
--     paced queue (edits.lua), since each chunk it touches is a relight on
--     the server and a remesh on every client.
--
-- The random tick offers a block only if it is one material, which on a
-- smooth surface the top block is: grass cells and air.
--
-- **Counted, and never silent.** The handler runs under pcall and logs an
-- error rather than letting the engine disable the mod without a word, and
-- every STATS_EVERY ticks it logs how many turns became what. If nothing
-- grows, that block of the log says why.

local HUMIDITY_MIN = -0.05     -- the noise runs about -0.42 .. +0.42
local HUMIDITY_FREQ = 1 / 9000

local LITTER_FREQ = 1 / 14     -- patches a dozen or so blocks across
local LITTER_MIN = 0.13        -- the noise (+/-0.42) must exceed this: a fifth of the ground

local TREE_CHANCE = 8          -- one grass block in this many is a candidate
local TREE_SPACING = 4         -- no other trunk within this many blocks
local BIRCH_ONE_IN = 7         -- of the trees, one in this many is a birch
local DEAD_ONE_IN = 14         -- of the trees, one in this many is dead wood (half standing, half fallen)
local ROOT_DEPTH = 3           -- how far down a trunk may go looking for whole ground

-- Species, in the Better Trees idiom: a trunk that may fork, a few main
-- branches leaving it at an angle and rising as they go out, and a clump of
-- leaves at the end of every branch and on the top — so the canopy is a
-- lumpy union of clumps with gaps between them, not one blob. Numbers are
-- { least, extra } ranges the stream picks from.
local OAK = {
    log = "spindle:oak_log", leaves = "spindle:oak_leaves",
    trunk = { 6, 4 },              -- blocks of trunk before the crown
    fork_one_in = 4,               -- one oak in this many splits into two leaders
    branches = { 2, 3 },           -- main branches off the upper trunk
    branch_out = { 2, 3 },         -- how far a branch reaches sideways
    branch_up = { 1, 3 },          -- and how far it rises doing so
    clump = { 2.2, 1.2 },          -- half-width of a branch-tip clump
    crown = { 2.6, 1.2 },          -- half-width of the clump on the trunk top
    flat = 0.7,                    -- clump height as a share of its width
    flares = { 2, 3 },
}
local ASPEN = {
    log = "spindle:birch_log", leaves = "spindle:oak_leaves",
    trunk = { 10, 5 },
    fork_one_in = 8,
    branches = { 1, 2 },
    branch_out = { 1, 2 },
    branch_up = { 1, 2 },
    clump = { 1.3, 0.8 },
    crown = { 1.6, 0.8 },
    flat = 1.1,
    flares = { 0, 2 },
}
local BIRCH = ASPEN                -- the block is still called birch_log

local ROCK_CHANCE = 350        -- one grass block in this many, inside a patch
local ROCK_PATCH = 32          -- patches are this many blocks square...
local ROCK_PATCH_ONE_IN = 4    -- ...and one in this many has rocks and roots
local ROCK_R_MIN, ROCK_R_EXTRA = 1.0, 1.6   -- half-width, blocks
local ROCK_BURIED = 0.6        -- share of a rock's height under the grass: half-buried
local ROOT_SHARE = 5           -- one candidate in this many is a root node, not a rock

local POOL_CHANCE = 60000      -- one grass block in this many: very occasional
local POOL_R = 3               -- radius of the bank, blocks; water is one block down
local POOL_APART = 24          -- no other water within this many blocks

local STATS_EVERY = 200        -- ticks between log lines: ten seconds

local blocks = spindle.blocks
local layers = spindle.layers
local shape = spindle.shape
local edits = spindle.edits

spindle.build_biome("temperate_woodlands", function(ctx)
    local n = ctx.node
    local ring = layers.ring_by_id.temperate
    -- Where the biome is, unless it is everywhere.
    local function masked(field)
        if ctx.everywhere then
            return field
        end
        local humidity = n.noise("humidity", HUMIDITY_FREQ, 2, 1.0)
        local mask = n.min(shape.ring(ring.u[1], ring.u[2]), n.sub(humidity, n.const(HUMIDITY_MIN)))
        return n.min(field, mask)
    end
    -- The top blocks under the real surface: one terrain evaluation each.
    local function top()
        return shape.terrain_band(0.0, shape.SKIN_TOP, false)
    end
    local grass = shape.compile("biome.woodlands.grass", masked(top()))
    local litter = shape.compile("biome.woodlands.litter",
        masked(n.min(top(), n.sub(n.noise("litter", LITTER_FREQ, 2, 1.0), n.const(LITTER_MIN)))))
    local creek = shape.compile("biome.woodlands.creek", masked(n.min(top(), shape.gully_floor())))
    -- In order: turf everywhere, litter over it in patches, gravel over both
    -- along the creek floors.
    return {
        { field = grass, material = blocks.grass },
        { field = litter, material = blocks.leaf_litter },
        { field = creek, material = blocks.creek_bed },
    }
end)
spindle.biomes.temperate_woodlands.soil = blocks.loam

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
local function is_wood(b)
    return b ~= nil and b.occupancy ~= 0
        and (b.material == blocks.oak_log or b.material == blocks.birch_log or b.material == blocks.dead_wood)
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

-- Which grass blocks are candidates is decided by an integer hash of the
-- position and the world seed, before anything is read or any stream opened:
-- a busy world hands this handler thousands of blocks a tick and almost all
-- of them must cost nothing. Plain integer arithmetic; exact. `seed_int` is
-- the generator's integer form of the seed — the seed itself can be a float.
local function hash(x, y, z)
    local h = (x * 73856093) ~ (y * 19349663) ~ (z * 83492791) ~ ((spindle.seed_int or 0) * 2654435761)
    return h ~ (h >> 17)
end
local function candidate(x, y, z, one_in)
    return hash(x, y, z) % one_in == 0
end

-- Counts, for the log.
local stats = { turns = 0, candidates = 0, attempts = 0, grown = 0, rocks = 0, pools = 0,
    no_room = 0, headroom = 0, spacing = 0, unloaded = 0, errors = 0 }
local last_error = nil

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
-- The bottom two layers of cells: a low hump.
local LOW = 0
-- A log lying along x or z: two cells wide, two tall, through the block.
local LYING = { x = 0, z = 0 }
for c = 0, 2 do
    for d = 0, 2 do
        LOW = LOW | bit(c, 0, d) | bit(c, 1, d)
    end
    for cy = 0, 1 do
        for cw = 0, 1 do
            LYING.x = LYING.x | bit(c, cy, cw)
            LYING.z = LYING.z | bit(cw, cy, c)
        end
    end
end

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

-- Writes an ellipsoid of `material` into the world as part of the current
-- batch: its cells go into empty blocks as they are, and a partly filled
-- block it reaches keeps its own cells and becomes `material` with them, so
-- a buried thing stands in a footprint of itself. (A merge write — cells
-- into a block that keeps its others — is an engine ask; with it the
-- footprint goes away.) Whole blocks are left alone: nothing shows there.
local function push_ellipsoid(material, cx, cy, cz, rx, ry, rz)
    for bz = math.floor(cz - rz), math.floor(cz + rz) do
        for by = math.floor(cy - ry), math.floor(cy + ry) do
            for bx = math.floor(cx - rx), math.floor(cx + rx) do
                local mask = ellipsoid_mask(bx, by, bz, cx, cy, cz, rx, ry, rz)
                if mask ~= 0 then
                    local b = at(bx, by, bz)
                    if b ~= nil and b.occupancy ~= FULL then
                        edits.push({ x = bx, y = by, z = bz }, material, mask | b.occupancy)
                    end
                end
            end
        end
    end
end

-- Between two bounds, inclusive, from the stream.
local function pick(rng, range)
    return range[1] + rng:below(range[2] + 1)
end

-- Trees ----------------------------------------------------------------------

-- The foot of a trunk: down through the grass block and any partial ground
-- under it until it stands on a whole block, so on a slope it is planted
-- rather than perched. Nil if the ground there is not loaded.
local function footing(x, y, z)
    local base = y
    for dy = 0, ROOT_DEPTH do
        local b = at(x, y - dy, z)
        if b == nil then
            return nil
        end
        base = y - dy
        if is_whole(b) then
            break
        end
    end
    return base
end

-- Room for a trunk: air over it, and no other trunk within TREE_SPACING,
-- checked on a ring of points at chest height.
local function clear_for(x, y, z, height)
    for dy = 1, height + 6 do
        if not is_empty(at(x, y + dy, z)) then
            stats.headroom = stats.headroom + 1
            return false
        end
    end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
        for r = 2, TREE_SPACING do
            if is_wood(at(x + d[1] * r, y + 2, z + d[2] * r)) then
                stats.spacing = stats.spacing + 1
                return false
            end
        end
    end
    return true
end

-- A root flare: low humps of wood on the ground beside the foot.
local function push_flares(x, y, z, base, log, count, rng)
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local first = rng:below(4)
    for i = 0, count - 1 do
        local d = dirs[(first + i) % 4 + 1]
        local fx, fz = x + d[1], z + d[2]
        for fy = y, base, -1 do
            local b = at(fx, fy, fz)
            if b ~= nil and b.occupancy ~= FULL then
                edits.push({ x = fx, y = fy, z = fz }, log, LOW | b.occupancy)
                break
            end
        end
    end
end

-- The four corner columns of a block, and the mask with each of them gone.
local CORNER = {
    bit(0, 0, 0) | bit(0, 1, 0) | bit(0, 2, 0),
    bit(2, 0, 0) | bit(2, 1, 0) | bit(2, 2, 0),
    bit(0, 0, 2) | bit(0, 1, 2) | bit(0, 2, 2),
    bit(2, 0, 2) | bit(2, 1, 2) | bit(2, 2, 2),
}
local ROUND = FULL & ~(CORNER[1] | CORNER[2] | CORNER[3] | CORNER[4])

-- A trunk block: whole, minus most of its corner columns — each corner is
-- gone four times in five, so the trunk is round in most places and keeps
-- a knob or a flat here and there.
local function trunk_mask(rng)
    local mask = FULL
    for _, corner in ipairs(CORNER) do
        if rng:below(5) ~= 0 then
            mask = mask & ~corner
        end
    end
    return mask
end

-- A branch: from (x, y, z) out `out` blocks along the direction (sx, sz),
-- rising `up` as it goes, one block per step. Thick where it leaves the
-- trunk (the rounded trunk mask), a two-cell bar along the middle, and a
-- thin bar at the tip, where it turns upward to meet its clump. Writes into
-- `wood` (key -> {mask, y}) and returns the tip.
local function branch(wood, x, y, z, sx, sz, out, up, rng)
    local bx, by, bz = x, y, z
    local rises = {}
    for i = 1, up do
        rises[1 + rng:below(out)] = (rises[1 + rng:below(out)] or 0) + 1
    end
    local along_x = sx ~= 0 and sz == 0
    for step = 1, out do
        bx, bz = bx + sx, bz + sz
        if rises[step] then
            by = by + rises[step]
        end
        local key = bx .. ":" .. by .. ":" .. bz
        local mask
        if step == 1 then
            mask = trunk_mask(rng)
        elseif step == out then
            mask = (along_x and BAR.x or BAR.z) | BAR.y
        else
            mask = along_x and (LYING.x | (LYING.x << 3)) or (LYING.z | (LYING.z << 3))
            mask = mask & FULL
        end
        wood[key] = { mask = (wood[key] and wood[key].mask or 0) | mask, y = by }
    end
    return bx, by, bz
end

-- A clump of leaves: an ellipsoid, each block of it scaled a little up or
-- down at random so the surface is ragged rather than smooth.
local function clump(leaf_masks, cx, cy, cz, r, flat, rng)
    local rx, rz, ry = r, r, r * flat
    for bz = math.floor(cz - rz), math.floor(cz + rz) do
        for by = math.floor(cy - ry), math.floor(cy + ry) do
            for bx = math.floor(cx - rx), math.floor(cx + rx) do
                local scale = 0.85 + rng:below(6) / 20
                local mask = ellipsoid_mask(bx, by, bz, cx, cy, cz, rx * scale, ry * scale, rz * scale)
                if mask ~= 0 then
                    local key = bx .. ":" .. by .. ":" .. bz
                    leaf_masks[key] = (leaf_masks[key] or 0) | mask
                end
            end
        end
    end
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function grow_tree(x, y, z, rng, species)
    -- No room on the queue is the cheapest refusal, so it comes first: a
    -- canopy is a few thousand cell tests, not worth doing to throw away.
    if not edits.room() then
        stats.no_room = stats.no_room + 1
        return false
    end
    local height = pick(rng, species.trunk)
    if not clear_for(x, y, z, height) then
        return false
    end
    local base = footing(x, y, z)
    if base == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end

    local wood = {}          -- key -> { mask, y }
    local leaf_masks = {}
    local top = y + height

    -- The trunk: whole in the ground, rounded above it.
    for by = base, top do
        local mask = by <= y and FULL or trunk_mask(rng)
        wood[x .. ":" .. by .. ":" .. z] = { mask = mask, y = by }
    end
    -- A fork: a second leader leaving diagonally at about half height and
    -- rising three or four blocks, with a crown of its own.
    if rng:below(species.fork_one_in) == 0 then
        local d = DIRS[rng:below(4) + 1]
        local fy = y + math.max(2, height // 2)
        local fx, fz = x, z
        local rise = 3 + rng:below(2)
        for i = 1, rise do
            if i <= 2 then
                fx, fz = fx + d[1], fz + d[2]
            end
            fy = fy + 1
            wood[fx .. ":" .. fy .. ":" .. fz] = { mask = trunk_mask(rng), y = fy }
        end
        clump(leaf_masks, fx + 0.5, fy + 0.5, fz + 0.5, pick(rng, species.clump), species.flat, rng)
    end
    -- Main branches off the upper trunk, each with a clump at its tip. They
    -- leave in different directions: the first is random, the rest go round.
    local count = pick(rng, species.branches)
    local first = rng:below(4)
    for i = 0, count - 1 do
        local d = DIRS[(first + i) % 4 + 1]
        local from = y + math.max(2, height * 3 // 5) + rng:below(math.max(1, height * 2 // 5))
        local tx, ty, tz = branch(wood, x, math.min(from, top - 1), z, d[1], d[2],
            pick(rng, species.branch_out), pick(rng, species.branch_up), rng)
        clump(leaf_masks, tx + 0.5, ty + 1.0, tz + 0.5, pick(rng, species.clump), species.flat, rng)
    end
    -- The crown on the trunk top.
    clump(leaf_masks, x + 0.5, top + 0.5, z + 0.5, pick(rng, species.crown), species.flat, rng)

    -- One batch: wood from the ground up (so the tree reads as growing),
    -- the root flare, then leaves wherever there is air and no wood.
    edits.begin()
    local keys = {}
    for key, entry in pairs(wood) do
        keys[#keys + 1] = { key = key, y = entry.y, mask = entry.mask }
    end
    table.sort(keys, function(p, q) return p.y < q.y or (p.y == q.y and p.key < q.key) end)
    for _, item in ipairs(keys) do
        local bx, by, bz = item.key:match("^(-?%d+):(-?%d+):(-?%d+)$")
        bx, by, bz = tonumber(bx), tonumber(by), tonumber(bz)
        if by <= y and bx == x and bz == z then
            edits.push({ x = bx, y = by, z = bz }, species.log)
        else
            local b = at(bx, by, bz)
            if is_empty(b) or (bx == x and bz == z) then
                edits.push({ x = bx, y = by, z = bz }, species.log, item.mask == FULL and nil or item.mask)
            end
        end
    end
    push_flares(x, y, z, base, species.log, pick(rng, species.flares), rng)
    -- Leaves go only where there is air, but reading every leaf block back
    -- is three hundred calls a tree and was most of the mod's tick. Terrain
    -- does not overhang a canopy from above, so one read per COLUMN, at its
    -- lowest leaf, decides the column: empty there, empty above.
    local columns = {}
    for key in pairs(leaf_masks) do
        if not wood[key] then
            local bx, by, bz = key:match("^(-?%d+):(-?%d+):(-?%d+)$")
            bx, by, bz = tonumber(bx), tonumber(by), tonumber(bz)
            local ck = bx .. ":" .. bz
            local col = columns[ck]
            if col == nil then
                columns[ck] = { x = bx, z = bz, low = by }
            elseif by < col.low then
                col.low = by
            end
        end
    end
    local clear = {}
    for ck, col in pairs(columns) do
        clear[ck] = is_empty(at(col.x, col.low, col.z))
    end
    for key, mask in pairs(leaf_masks) do
        if not wood[key] then
            local bx, by, bz = key:match("^(-?%d+):(-?%d+):(-?%d+)$")
            bx, by, bz = tonumber(bx), tonumber(by), tonumber(bz)
            if clear[bx .. ":" .. bz] then
                edits.push({ x = bx, y = by, z = bz }, species.leaves, mask)
            end
        end
    end
    return edits.commit()
end

-- Dead wood -------------------------------------------------------------------

-- A snag: a bare trunk, shorter than a living tree, with a stub or two of
-- branch and a broken top — the top block holds only some of its cells.
local function grow_snag(x, y, z, rng)
    local height = 4 + rng:below(5)
    if not clear_for(x, y, z, height) then
        return false
    end
    local base = footing(x, y, z)
    if base == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    if not edits.room() then
        stats.no_room = stats.no_room + 1
        return false
    end
    local top = y + height
    edits.begin()
    for by = base, top - 1 do
        edits.push({ x = x, y = by, z = z }, "spindle:dead_wood")
    end
    -- The broken top: the bottom layer and a few cells above it.
    local jag = 0
    for c = 0, 2 do
        for d = 0, 2 do
            jag = jag | bit(c, 0, d)
        end
    end
    for _ = 1, 2 + rng:below(4) do
        jag = jag | bit(rng:below(3), 1, rng:below(3))
    end
    jag = jag | bit(rng:below(3), 2, rng:below(3))
    edits.push({ x = x, y = top, z = z }, "spindle:dead_wood", jag)
    -- Stubs: one or two bars out from the upper trunk.
    for _ = 1, 1 + rng:below(2) do
        local dirs = { { 1, 0, "x" }, { -1, 0, "x" }, { 0, 1, "z" }, { 0, -1, "z" } }
        local d = dirs[rng:below(4) + 1]
        local sy = top - 1 - rng:below(math.max(1, height - 2))
        local sx, sz = x + d[1], z + d[2]
        if is_empty(at(sx, sy, sz)) then
            edits.push({ x = sx, y = sy, z = sz }, "spindle:dead_wood", BAR[d[3]])
        end
    end
    push_flares(x, y, z, base, "spindle:dead_wood", rng:below(3), rng)
    return edits.commit()
end

-- A fallen trunk: a log two cells thick lying along x or z, four to seven
-- blocks long, sunk into the ground — the surface blocks it lies in keep
-- their cells and become wood with them, so it reads as half in the turf.
-- Its far end drops with the ground if the ground drops.
local function lay_log(x, y, z, rng)
    if not edits.room() then
        stats.no_room = stats.no_room + 1
        return false
    end
    local along_x = rng:next_bool()
    local dir = rng:next_bool() and 1 or -1
    local length = 4 + rng:below(4)
    local lying = along_x and LYING.x or LYING.z
    local placed = 0
    edits.begin()
    for i = 0, length - 1 do
        local lx = along_x and x + i * dir or x
        local lz = along_x and z or z + i * dir
        -- The block whose cells this stretch of log shares: the surface block
        -- at this column, found from the start height downwards, then up.
        local ly = nil
        for dy = 0, -2, -1 do
            local b = at(lx, y + dy, lz)
            if b ~= nil and b.occupancy ~= 0 and b.occupancy ~= FULL then
                ly = y + dy
                break
            end
        end
        if ly == nil and is_empty(at(lx, y, lz)) and is_whole(at(lx, y - 1, lz)) then
            ly = y
        end
        if ly ~= nil then
            local b = at(lx, ly, lz)
            local mask = lying
            if i == length - 1 and rng:next_bool() then
                mask = mask & ~(along_x and (bit(2, 0, 0) | bit(2, 1, 0) | bit(2, 0, 1) | bit(2, 1, 1))
                    or (bit(0, 0, 2) | bit(1, 0, 2) | bit(0, 1, 2) | bit(1, 1, 2)))
            end
            edits.push({ x = lx, y = ly, z = lz }, "spindle:dead_wood", mask | (b and b.occupancy or 0))
            placed = placed + 1
        end
    end
    if placed < 3 then
        edits.commit()          -- an empty-enough batch; commit clears it
        return false
    end
    return edits.commit()
end

-- Rocks and root nodes ------------------------------------------------------

-- A rock is a point and a squat ellipsoid round it, rounded to the cell and
-- more than half buried: weathered limestone or granite. A root node is the
-- same shape, smaller and flatter, in wood — the exposed knuckle of a root.
-- Both come in patches: a coarse grid of the world, one square in a few, is
-- where they may grow at all.
local function place_rock(x, y, z, rng, root)
    if not edits.room() then
        stats.no_room = stats.no_room + 1
        return false
    end
    local r = ROCK_R_MIN + rng:below(9) / 8 * ROCK_R_EXTRA
    local material = rng:next_bool() and "spindle:limestone" or "spindle:granite"
    local ry = r * (0.5 + rng:below(5) / 10)
    if root then
        r = 0.7 + rng:below(7) / 10
        ry = r * 0.5
        material = "spindle:oak_log"
    end
    local rx = r * (0.8 + rng:below(5) / 10)
    local rz = r * (0.8 + rng:below(5) / 10)
    local ground = y + 0.6                       -- about where a partial top block's surface is
    local cy = ground + ry * (1.0 - 2.0 * ROCK_BURIED)
    local cx, cz = x + 0.5 + (rng:below(5) - 2) / 4, z + 0.5 + (rng:below(5) - 2) / 4
    edits.begin()
    push_ellipsoid(material, cx, cy, cz, rx, ry, rz)
    return edits.commit()
end

-- Pools ----------------------------------------------------------------------

-- A pool is dug, not found: a flat patch of grass gets a bank one block deep
-- and a bowl of water under it, two blocks deep at the middle. The bank is
-- what keeps it in — the water sits a block below the grass, walled by whole
-- blocks of ground — so a smooth slope cannot drain it.
local function dig_pool(x, y, z)
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
    if not edits.room() then
        stats.no_room = stats.no_room + 1
        return false
    end
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

-- The random tick -------------------------------------------------------------

local function on_grass(x, y, z)
    stats.turns = stats.turns + 1
    if not in_ring(x, z) then
        return
    end
    if candidate(x, y, z, POOL_CHANCE) then
        if dig_pool(x, y, z) then stats.pools = stats.pools + 1 end
        return
    end
    local rock = candidate(x, y, z, ROCK_CHANCE)
        and candidate(x // ROCK_PATCH, 7, z // ROCK_PATCH, ROCK_PATCH_ONE_IN)
    if not rock and not candidate(x, y, z, TREE_CHANCE) then
        return
    end
    stats.candidates = stats.candidates + 1
    if not edits.room() then
        stats.no_room = stats.no_room + 1
        return
    end
    -- One stream per block, so two grass blocks in one chunk do not grow the
    -- same thing. The world seed is captured by the generator.
    local rng = game.rng_stream(
        { x = x // 16, y = y // 16, z = z // 16, seed = spindle.seed or 0 },
        "grow:" .. x .. ":" .. y .. ":" .. z)
    if rock then
        if place_rock(x, y, z, rng, candidate(x, y, z, ROOT_SHARE)) then
            stats.rocks = stats.rocks + 1
        end
        return
    end
    stats.attempts = stats.attempts + 1
    -- Which tree: the hash again, on a different axis so it is independent
    -- of being a candidate at all.
    local kind = hash(x, y + 1, z)
    local grown
    if kind % DEAD_ONE_IN == 0 then
        grown = (kind // DEAD_ONE_IN) % 2 == 0 and grow_snag(x, y, z, rng) or lay_log(x, y, z, rng)
    elseif kind % BIRCH_ONE_IN == 0 then
        grown = grow_tree(x, y, z, rng, BIRCH)
    else
        grown = grow_tree(x, y, z, rng, OAK)
    end
    if grown then
        stats.grown = stats.grown + 1
    end
end

game.register_random_tick(blocks.grass, function(event)
    local ok, err = pcall(on_grass, event.x, event.y, event.z)
    if not ok then
        stats.errors = stats.errors + 1
        if last_error ~= tostring(err) then
            last_error = tostring(err)
            game.log("spindle woodlands: grass tick failed: " .. last_error)
        end
    end
end)

local function report()
    game.log(string.format(
        "spindle woodlands: %d grass turns, %d candidates, %d tree attempts, %d grown, %d rocks, %d pools; refused: room %d, headroom %d, spacing %d, unloaded %d; errors %d (%s); batches waiting %d",
        stats.turns, stats.candidates, stats.attempts, stats.grown, stats.rocks, stats.pools,
        stats.no_room, stats.headroom, stats.spacing, stats.unloaded, stats.errors, last_error or "none",
        edits.waiting()))
    for key in pairs(stats) do
        stats[key] = 0
    end
end

local ticks = 0
spindle.on_tick(function(dt_ticks)
    ticks = ticks + dt_ticks
    if ticks >= STATS_EVERY then
        ticks = 0
        report()
    end
end)

-- Say "stats" in chat for the counts now, without waiting for the timer.
spindle.on_chat("stats", report)

game.log("spindle: woodlands grow oaks, birches, dead wood, rocks, root nodes and pools by random tick")
